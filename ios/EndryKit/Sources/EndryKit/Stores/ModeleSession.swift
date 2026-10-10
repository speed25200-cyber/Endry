import Foundation
import Observation

public enum ErreurConnexion: Error, Equatable, Sendable {
    case lien(ErreurLien)
    case api(ErreurAPI)
    case trousseau

    public var message: String {
        switch self {
        case .lien(let e): e.message
        case .api(let e): e.message
        case .trousseau: "Impossible d’enregistrer l’accès dans le trousseau de l’iPhone."
        }
    }
}

/// Qui est connecté, à quel serveur, et avec quel client API.
@MainActor
@Observable
public final class ModeleSession {
    public enum Etat: Equatable, Sendable {
        case deconnecte
        case connecte(Identifiants)
        case demo
    }

    public private(set) var etat: Etat
    public private(set) var api: (any EndryAPI)?
    /// 401 ou serveur injoignable : afficher « Connexion perdue : collez le nouveau lien ».
    public var connexionPerdue = false

    public let cache: CacheHorsLigne
    @ObservationIgnored private let coffre: CoffreJeton
    @ObservationIgnored private let transport: TransportHTTP
    @ObservationIgnored private var apiDemo: APIDemo?

    /// Nom et modèle de cet iPhone, envoyés au PC pour obtenir un jeton propre à l'appareil (v1.1).
    @ObservationIgnored public var appareil: (nom: String, modele: String)?

    public init(coffre: CoffreJeton, cache: CacheHorsLigne, transport: TransportHTTP = TransportURLSession()) {
        self.coffre = coffre
        self.cache = cache
        self.transport = transport
        if let identifiants = coffre.lire(), !identifiants.estExpire {
            etat = .connecte(identifiants)
            api = ClientAPI(identifiants: identifiants, transport: transport)
        } else {
            etat = .deconnecte
            api = nil
        }
    }

    public var estConnecte: Bool { etat != .deconnecte }
    public var estDemo: Bool { etat == .demo }

    /// Démo du mode équipe (tests, captures, présentation aux ouvriers).
    public private(set) var demoOuvrier = false

    /// Lien d'équipe (v1.3) : l'app n'affiche que les chantiers du jour, les heures et les photos.
    public var estOuvrier: Bool {
        switch etat {
        case .connecte(let i): i.estOuvrier
        case .demo: demoOuvrier
        case .deconnecte: false
        }
    }

    /// Accès directeur (v1.12) : les montants et « Poser une question », en lecture seule.
    public var estDirecteur: Bool {
        if case .connecte(let i) = etat { return i.estDirecteur }
        return false
    }

    /// Nom de l'ouvrier connecté (lien d'équipe).
    public var nomOuvrier: String? {
        switch etat {
        case .connecte(let i): i.nom
        case .demo: demoOuvrier ? "Marco" : nil
        case .deconnecte: nil
        }
    }

    public var hoteAffiche: String? {
        switch etat {
        case .connecte(let i): LienAcces(base: i.base, secret: "").hoteAffiche
        case .demo: "Mode démo"
        case .deconnecte: nil
        }
    }

    /// Serveur actuellement enregistré (pour juger un lien profond).
    public var baseEnregistree: URL? {
        if case .connecte(let i) = etat { return i.base }
        return nil
    }

    public var appareilId: String? {
        if case .connecte(let i) = etat { return i.appareilId }
        return nil
    }

    public var entreprise: String {
        if case .connecte(let i) = etat, let e = i.entreprise { return e }
        return "Endry SA"
    }

    /// Colle un lien d'accès : extraction hôte + secret, échange contre un jeton, rangement dans le trousseau.
    public func connecter(texte: String) async throws(ErreurConnexion) {
        let lien: LienAcces
        do {
            lien = try LienAcces.analyser(texte)
        } catch {
            throw .lien(error)
        }
        let identifiants: Identifiants
        do {
            identifiants = try await ClientAPI.ouvrirSession(lien, appareil: appareil, transport: transport)
        } catch {
            throw .api(error)
        }
        do {
            try coffre.enregistrer(identifiants)
        } catch {
            throw .trousseau
        }
        if case .connecte(let ancien) = etat, ancien.base != identifiants.base {
            await cache.effacer()
        }
        etat = .connecte(identifiants)
        api = ClientAPI(identifiants: identifiants, transport: transport)
        connexionPerdue = false
    }

    /// Mode démo : données fictives, aucune requête réseau.
    public func activerDemo(latence: Duration = .milliseconds(450), ouvrier: Bool = false) {
        let demo = APIDemo(latence: latence)
        apiDemo = demo
        api = demo
        demoOuvrier = ouvrier
        etat = .demo
        connexionPerdue = false
    }

    public func reinitialiserDemo() async {
        await apiDemo?.reinitialiser()
    }

    public enum ResultatDeconnexion: Equatable, Sendable {
        /// Le PC a révoqué le jeton de cet iPhone.
        case revoque
        /// Jeton commun, ou PC trop ancien (405) : effacé ici, mais pas révocable à distance.
        case nonRevocable
        /// PC injoignable : effacé ici ; le jeton reste valable côté PC jusqu'à sa révocation.
        case pcInjoignable
    }

    /// Révoque le jeton de cet iPhone côté PC (`DELETE /appareils/{id}`), puis efface tout localement.
    /// Même si le PC est injoignable, l'iPhone est déconnecté.
    @discardableResult
    public func deconnecterCetAppareil() async -> ResultatDeconnexion {
        var resultat = ResultatDeconnexion.nonRevocable
        if let api, let id = appareilId {
            do {
                try await api.supprimerAppareil(id)
                resultat = .revoque
            } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
                resultat = .nonRevocable
            } catch {
                resultat = error.estProblemeReseau ? .pcInjoignable : .nonRevocable
            }
        }
        await deconnecter()
        return resultat
    }

    /// Au lancement : un ancien jeton commun (sans `appareil_id`) est échangé une fois contre un jeton propre
    /// à cet iPhone (`POST /session/appareil`), sans nouveau lien. Vrai si le jeton a changé.
    public func migrerSiNecessaire() async -> Bool {
        guard case .connecte(let i) = etat, i.appareilId == nil, i.migrationTentee != true, let appareil else { return false }
        let client = ClientAPI(identifiants: i, transport: transport)
        do {
            let data = try await client.envoyer(.migrationAppareil(nom: appareil.nom, modele: appareil.modele))
            let session = try client.decoder(SessionOuverte.self, depuis: data)
            var nouveaux = Identifiants(base: i.base, jeton: session.jeton, entreprise: session.entreprise ?? i.entreprise,
                                        expireLe: session.valableJours.map { Date().addingTimeInterval(TimeInterval($0) * 86_400) } ?? i.expireLe,
                                        appareilId: session.appareilId)
            nouveaux.migrationTentee = true
            nouveaux.role = session.role ?? i.role
            nouveaux.nom = session.nom ?? i.nom
            try? coffre.enregistrer(nouveaux)
            etat = .connecte(nouveaux)
            api = ClientAPI(identifiants: nouveaux, transport: transport)
            return true
        } catch .dejaParAppareil {
            marquerMigration(i)
        } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
            marquerMigration(i)
        } catch {
            // Réseau ou autre : on réessaiera au prochain lancement.
        }
        return false
    }

    private func marquerMigration(_ i: Identifiants) {
        var marque = i
        marque.migrationTentee = true
        try? coffre.enregistrer(marque)
        etat = .connecte(marque)
    }

    public func deconnecter() async {
        coffre.effacer()
        await cache.effacer()
        apiDemo = nil
        api = nil
        demoOuvrier = false
        etat = .deconnecte
        connexionPerdue = false
    }

    /// Appelé par les écrans quand une requête échoue.
    public func signaler(_ erreur: ErreurAPI) {
        guard !estDemo else { return }
        switch erreur {
        case .nonAuthentifie, .lienInvalide:
            connexionPerdue = true
        default:
            break
        }
    }
}
