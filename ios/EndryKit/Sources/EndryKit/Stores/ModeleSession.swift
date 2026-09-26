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
    @ObservationIgnored private let groupeWidget: String?
    @ObservationIgnored private var apiDemo: APIDemo?

    public init(coffre: CoffreJeton, cache: CacheHorsLigne, transport: TransportHTTP = TransportURLSession(), groupeWidget: String? = nil) {
        self.coffre = coffre
        self.cache = cache
        self.transport = transport
        self.groupeWidget = groupeWidget
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

    public var hoteAffiche: String? {
        switch etat {
        case .connecte(let i): LienAcces(base: i.base, secret: "").hoteAffiche
        case .demo: "Mode démo"
        case .deconnecte: nil
        }
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
            identifiants = try await ClientAPI.ouvrirSession(lien, transport: transport)
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
    public func activerDemo(latence: Duration = .milliseconds(450)) {
        let demo = APIDemo(latence: latence)
        apiDemo = demo
        api = demo
        etat = .demo
        connexionPerdue = false
    }

    public func reinitialiserDemo() async {
        await apiDemo?.reinitialiser()
    }

    public func deconnecter() async {
        coffre.effacer()
        await cache.effacer()
        if let groupeWidget { ResumeWidget.effacer(groupe: groupeWidget) }
        apiDemo = nil
        api = nil
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

    public func publierResume(_ accueil: Accueil) {
        guard let groupeWidget else { return }
        ResumeWidget(accueil: accueil).enregistrer(groupe: groupeWidget)
    }
}
