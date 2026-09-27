import Foundation
import Observation

/// Message éphémère en verre, en bas de l'écran.
public struct Toast: Identifiable, Equatable, Sendable {
    public enum Style: Sendable { case succes, info, erreur }

    public let id = UUID()
    public var message: String
    public var style: Style

    public init(_ message: String, style: Style = .succes) {
        self.message = message
        self.style = style
    }
}

/// État de chargement commun à tous les écrans.
public enum EtatChargement: Equatable, Sendable {
    case initial
    case chargement
    case pret
    case erreur(ErreurAPI)
}

/// Point de passage des erreurs vers la session (connexion perdue) et vers le toast global.
public typealias RapportErreur = @MainActor (ErreurAPI) -> Void

// MARK: - Décisions (écran principal)

@MainActor
@Observable
public final class ModeleDecisions {
    public private(set) var accueil: Accueil?
    public private(set) var cartes: [Carte] = []
    public private(set) var etat: EtatChargement = .initial
    public private(set) var majLe: Date?
    /// Données issues du cache : lecture seule, actions désactivées.
    public private(set) var horsLigne = false
    public private(set) var decisionsAutorisees = true
    /// Références en cours d'envoi (boutons désactivés, indicateur).
    public private(set) var enCours: Set<String> = []
    public var toast: Toast?

    @ObservationIgnored private let api: any EndryAPI
    @ObservationIgnored private let cache: CacheHorsLigne?
    @ObservationIgnored private let rapport: RapportErreur?
    @ObservationIgnored public var surAccueil: (@MainActor (Accueil) -> Void)?

    public init(api: any EndryAPI, cache: CacheHorsLigne? = nil, rapport: RapportErreur? = nil) {
        self.api = api
        self.cache = cache
        self.rapport = rapport
    }

    public var nombreDecisions: Int { cartes.count }
    /// L'assistant est en pause : on lit tout, mais aucune action n'est envoyée.
    public var enPause: Bool { accueil?.pause ?? false }
    public var actionsPossibles: Bool { !horsLigne && decisionsAutorisees && !enPause }

    /// Pause / reprise pilotée depuis l'app (v1.1) : mise à jour immédiate de l'état affiché.
    public func appliquerPause(_ pause: Bool) {
        accueil?.pause = pause
    }

    public func charger() async {
        if accueil == nil { etat = .chargement }
        do {
            let charge = try await api.charger(Accueil.self, .accueil, cache: cache)
            accueil = charge.valeur
            cartes = charge.valeur.decisions
            majLe = charge.majLe
            horsLigne = charge.depuisCache
            etat = .pret
            if let e = charge.erreur { rapport?(e) }
            if !charge.depuisCache { surAccueil?(charge.valeur) }
        } catch {
            etat = accueil == nil ? .erreur(error) : .pret
            if accueil != nil { horsLigne = error.estProblemeReseau }
            rapport?(error)
            if accueil != nil { toast = Toast(error.message, style: .erreur) }
        }
        // `decisions_autorisees` n'est donné que par /decisions : on le lit sans bloquer l'écran.
        if !horsLigne, let reponse = try? await api.decisions() {
            decisionsAutorisees = reponse.decisionsAutorisees
        }
    }

    /// Oui / Non / Corriger. Retourne `true` si la carte a été traitée (elle disparaît).
    @discardableResult
    public func agir(_ action: ActionDecision, sur carte: Carte, consignes: String? = nil) async -> Bool {
        guard actionsPossibles else {
            toast = Toast(horsLigne ? ErreurAPI.horsLigne.message
                          : enPause ? "L’assistant est en pause : reprenez-le pour agir."
                          : "Les décisions sont en lecture seule.", style: .erreur)
            return false
        }
        // Une question se répond toujours par écrit (action `repondre`).
        let action: ActionDecision = carte.estQuestion ? .repondre : action
        let texte = consignes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if action == .corriger || action == .repondre, (texte ?? "").isEmpty {
            toast = Toast(carte.estQuestion ? "Écrivez ou dictez votre réponse." : "Indiquez ce qu’il faut corriger.", style: .erreur)
            return false
        }
        guard !enCours.contains(carte.reference) else { return false }
        enCours.insert(carte.reference)
        defer { enCours.remove(carte.reference) }
        do {
            let reponse = try await api.agir(action, sur: carte.reference, consignes: texte)
            cartes.removeAll { $0.reference == carte.reference }
            accueil?.decisions = cartes
            toast = Toast(reponse.message, style: action == .non ? .info : .succes)
            if let accueil { surAccueil?(accueil) }
            return true
        } catch {
            rapport?(error)
            toast = Toast(error.message, style: .erreur)
            if case .refus = error {
                // La carte a peut-être déjà été traitée ailleurs : on rafraîchit.
                await charger()
            }
            return false
        }
    }
}

// MARK: - Chantiers

@MainActor
@Observable
public final class ModeleChantiers {
    public private(set) var etapes: [CompteurEtape] = []
    /// Tous les chantiers (indépendants du filtre : Entreprise et Planning s'en servent).
    public private(set) var tous: [Dossier] = []
    public private(set) var semaine: [Semaine] = []
    public private(set) var calendrierICS: String?
    public private(set) var etat: EtatChargement = .initial
    public private(set) var majLe: Date?
    public private(set) var horsLigne = false
    public private(set) var actualisation = false
    public var filtre = "tous"
    public var toast: Toast?

    @ObservationIgnored private let api: any EndryAPI
    @ObservationIgnored private let cache: CacheHorsLigne?
    @ObservationIgnored private let rapport: RapportErreur?

    public init(api: any EndryAPI, cache: CacheHorsLigne? = nil, rapport: RapportErreur? = nil) {
        self.api = api
        self.cache = cache
        self.rapport = rapport
    }

    /// Chantiers de l'étape choisie (filtre appliqué localement, sans requête).
    public var chantiers: [Dossier] {
        filtre == "tous" ? tous : tous.filter { $0.etape == filtre }
    }

    /// Compteurs par étape, avec « Tous » en tête.
    public var compteurs: [CompteurEtape] {
        let parEtape = etapes.filter { $0.cle != "tous" }
        return [CompteurEtape(cle: "tous", libelle: "Tous", nombre: tous.count)] + parEtape
    }

    public func charger() async {
        if tous.isEmpty { etat = .chargement }
        do {
            let charge = try await api.charger(ReponseChantiers.self, .chantiers(etape: "tous"), cache: cache)
            etapes = charge.valeur.etapes
            tous = charge.valeur.chantiers
            semaine = charge.valeur.semaine
            calendrierICS = charge.valeur.calendrierICS
            majLe = charge.majLe
            horsLigne = charge.depuisCache
            etat = .pret
            if let e = charge.erreur { rapport?(e) }
        } catch {
            etat = tous.isEmpty ? .erreur(error) : .pret
            rapport?(error)
        }
    }

    public func choisir(_ etape: String) {
        filtre = etape
    }

    /// Tirer pour actualiser : demande au PC de relire Bexio et les e-mails, puis recharge.
    public func actualiser() async {
        guard !actualisation else { return }
        actualisation = true
        defer { actualisation = false }
        do {
            _ = try await api.actualiser()
        } catch {
            rapport?(error)
            toast = Toast(error.message, style: .erreur)
        }
        await charger()
    }

    /// URL `webcal://` pour s'abonner au planning dans Calendrier.
    public var urlAbonnement: URL? {
        guard let calendrierICS, let url = api.urlAbsolue(calendrierICS),
              var composants = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        composants.scheme = "webcal"
        return composants.url
    }
}

@MainActor
@Observable
public final class ModeleDossier {
    public private(set) var dossier: Dossier
    public private(set) var etat: EtatChargement = .initial
    public private(set) var horsLigne = false

    @ObservationIgnored private let api: any EndryAPI
    @ObservationIgnored private let cache: CacheHorsLigne?
    @ObservationIgnored private let rapport: RapportErreur?

    public init(dossier: Dossier, api: any EndryAPI, cache: CacheHorsLigne? = nil, rapport: RapportErreur? = nil) {
        self.dossier = dossier
        self.api = api
        self.cache = cache
        self.rapport = rapport
    }

    public func charger() async {
        etat = .chargement
        do {
            let charge = try await api.charger(Dossier.self, .chantier(id: dossier.id), cache: cache)
            dossier = charge.valeur
            horsLigne = charge.depuisCache
            etat = .pret
        } catch {
            etat = .erreur(error)
            rapport?(error)
        }
    }
}

// MARK: - Argent

@MainActor
@Observable
public final class ModeleArgent {
    public private(set) var argent: Argent?
    public private(set) var etat: EtatChargement = .initial
    public private(set) var majLe: Date?
    public private(set) var horsLigne = false

    @ObservationIgnored private let api: any EndryAPI
    @ObservationIgnored private let cache: CacheHorsLigne?
    @ObservationIgnored private let rapport: RapportErreur?

    public init(api: any EndryAPI, cache: CacheHorsLigne? = nil, rapport: RapportErreur? = nil) {
        self.api = api
        self.cache = cache
        self.rapport = rapport
    }

    public func charger() async {
        if argent == nil { etat = .chargement }
        do {
            let charge = try await api.charger(Argent.self, .argent, cache: cache)
            argent = charge.valeur
            majLe = charge.majLe
            horsLigne = charge.depuisCache
            etat = .pret
            if let e = charge.erreur { rapport?(e) }
        } catch {
            etat = argent == nil ? .erreur(error) : .pret
            rapport?(error)
        }
    }
}

// MARK: - Saisie terrain

public struct PieceSaisie: Identifiable, Sendable, Equatable {
    public enum Origine: Sendable { case photo, scan, fichier }

    public let id = UUID()
    public var nom: String
    public var typeMIME: String
    public var donnees: Data
    public var origine: Origine

    public init(nom: String, typeMIME: String, donnees: Data, origine: Origine) {
        self.nom = nom
        self.typeMIME = typeMIME
        self.donnees = donnees
        self.origine = origine
    }

    public var tailleLisible: String {
        let ko = Double(donnees.count) / 1024
        return ko < 1024 ? "\(Int(ko.rounded())) Ko" : String(format: "%.1f Mo", ko / 1024)
    }
}

@MainActor
@Observable
public final class ModeleSaisie {
    public enum Etat: Equatable, Sendable {
        case edition
        case envoi
        case transmis(String)
        case erreur(String)
    }

    public var texte = ""
    public private(set) var pieces: [PieceSaisie] = []
    public private(set) var etat: Etat = .edition

    @ObservationIgnored private let api: any EndryAPI
    @ObservationIgnored private let rapport: RapportErreur?

    public init(api: any EndryAPI, rapport: RapportErreur? = nil) {
        self.api = api
        self.rapport = rapport
    }

    public var peutEnvoyer: Bool {
        etat != .envoi && (!texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pieces.isEmpty)
    }

    /// Pré-remplit la saisie depuis un chantier (« Chantier Rochat — Épalinges : »).
    public func preparer(prefixe: String) {
        if texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            texte = prefixe
        } else if !texte.hasPrefix(prefixe) {
            texte = prefixe + texte
        }
        etat = .edition
    }

    @discardableResult
    public func ajouter(_ piece: PieceSaisie) -> Bool {
        guard piece.donnees.count <= FormulaireMultipart.tailleMaxFichier else {
            etat = .erreur("« \(piece.nom) » dépasse 15 Mo.")
            return false
        }
        pieces.append(piece)
        if case .erreur = etat { etat = .edition }
        return true
    }

    public func retirer(_ piece: PieceSaisie) {
        pieces.removeAll { $0.id == piece.id }
    }

    public func envoyer() async {
        guard peutEnvoyer else { return }
        etat = .envoi
        let fichiers = pieces.map {
            FormulaireMultipart.Fichier(champ: "photos", nomFichier: $0.nom, typeMIME: $0.typeMIME, donnees: $0.donnees)
        }
        do {
            let reponse = try await api.saisie(texte: texte.trimmingCharacters(in: .whitespacesAndNewlines), fichiers: fichiers)
            etat = .transmis(reponse.message ?? "Transmis")
        } catch {
            rapport?(error)
            etat = .erreur(error.message)
        }
    }

    public func recommencer() {
        texte = ""
        pieces = []
        etat = .edition
    }
}
