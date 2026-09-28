import AppIntents
import CoreSpotlight
import EndryKit
import Foundation
import Observation

/// Demandes venues de Siri, de Spotlight ou du bouton Action, en attente que l'app soit déverrouillée.
@MainActor
@Observable
final class DemandesRaccourcis {
    static let partage = DemandesRaccourcis()
    var assistantDemande = false
    var outil: OutilTerrain?
    var chantier: String?
    var briefingDemande = false
    /// « Dis Siri, nouvelle offre Endry » : la rédaction s'ouvre, dictée prête.
    var creation: TypeDemandeDocument?
    /// « Écrire au bureau » : la conversation s'ouvre, clavier prêt.
    var conversationDemande = false

    var enAttente: Bool {
        assistantDemande || outil != nil || chantier != nil || briefingDemande || creation != nil || conversationDemande
    }
}

// MARK: - Ouvrir l'app sur une fonction

/// « Dis Siri, parler à Endry » : ouvre l'app sur l'assistant vocal, prêt à écouter.
/// L'assistant ne s'ouvre qu'après Face ID : rien n'est lu à voix haute sur un iPhone verrouillé.
struct ParlerAEndry: AppIntent {
    static let title: LocalizedStringResource = "Parler à Endry"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DemandesRaccourcis.partage.assistantDemande = true
        return .result()
    }
}

/// « Écrire au bureau » : la conversation avec l'assistant du bureau (écrite ou dictée), comme un chat ouvert.
struct EcrireAuBureau: AppIntent {
    static let title: LocalizedStringResource = "Écrire au bureau"
    static let description: IntentDescription? = IntentDescription("Ouvre la conversation avec l’assistant du bureau : écrivez ou dictez, il répond ici.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DemandesRaccourcis.partage.conversationDemande = true
        return .result()
    }
}

struct NouveauBonRegie: AppIntent {
    static let title: LocalizedStringResource = "Bon de régie"
    static let description: IntentDescription? = IntentDescription("Ouvre un bon de régie à remplir et à faire signer sur place.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DemandesRaccourcis.partage.outil = .regie
        return .result()
    }
}

struct ScannerBonLivraison: AppIntent {
    static let title: LocalizedStringResource = "Scanner un bon de livraison"
    static let description: IntentDescription? = IntentDescription("Photographie un bon fournisseur et le rattache au chantier.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DemandesRaccourcis.partage.outil = .bonLivraison
        return .result()
    }
}

struct ReleverUnePiece: AppIntent {
    static let title: LocalizedStringResource = "Relevé 3D d’une pièce"
    static let description: IntentDescription? = IntentDescription("Mesure une pièce avec le LiDAR pour préparer l’offre.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DemandesRaccourcis.partage.outil = .releve
        return .result()
    }
}

struct NouvelleOffre: AppIntent {
    static let title: LocalizedStringResource = "Nouvelle offre"
    static let description: IntentDescription? = IntentDescription("Dictez l’offre : l’assistant la prépare dans Bexio, elle attend votre Oui avant de partir.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DemandesRaccourcis.partage.creation = .offre
        return .result()
    }
}

struct NouvelleFacture: AppIntent {
    static let title: LocalizedStringResource = "Nouvelle facture"
    static let description: IntentDescription? = IntentDescription("Dictez la facture : l’assistant la prépare dans Bexio, elle attend votre Oui avant de partir.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DemandesRaccourcis.partage.creation = .facture
        return .result()
    }
}

// MARK: - Réponses de Siri (sans ouvrir l'app)

/// « Dis Siri, briefing Endry » : lu par Siri, même en voiture (CarPlay). Lecture seule : rien n'est validé.
/// Montants seulement si le patron l'a choisi (Réglages › Suivi et rappels).
struct BriefingEndry: AppIntent {
    static let title: LocalizedStringResource = "Briefing Endry"
    static let description: IntentDescription? = IntentDescription("Chantiers du jour, décisions en attente, suivis : lu à voix haute, sans rien valider.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let montants = UserDefaults.standard.bool(forKey: BriefingMatin.cleMontantsSiri)
        guard let briefing = await DonneesArrierePlan.briefing(masquerMontants: !montants) else {
            return .result(dialog: "Je n’arrive pas à joindre le bureau. Ouvrez Endry pour vérifier la connexion.")
        }
        return .result(dialog: "\(briefing.texteParle)")
    }
}

/// « Dis Siri, décisions Endry » : combien, lesquelles. La validation se fait toujours dans l'app.
struct DecisionsEndry: AppIntent {
    static let title: LocalizedStringResource = "Décisions Endry"
    static let description: IntentDescription? = IntentDescription("Dit combien de décisions vous attendent et lesquelles. La validation se fait dans l’app.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let api = DonneesArrierePlan.api(), let reponse = try? await api.decisions() else {
            return .result(dialog: "Je n’arrive pas à joindre le bureau.")
        }
        let cartes = reponse.decisions
        guard !cartes.isEmpty else { return .result(dialog: "Aucune décision ne vous attend.") }
        let titres = cartes.prefix(3).map(\.titre)
        let envois = cartes.filter(\.partChezUnTiers).count
        let debut = cartes.count == 1 ? "Une décision vous attend" : "\(cartes.count) décisions vous attendent"
        let detail = envois > 0 ? ", dont \(envois == 1 ? "un envoi" : "\(envois) envois") à un tiers" : ""
        return .result(dialog: "\(debut)\(detail) : \(Briefing.enPhrase(titres)). Ouvrez Endry pour décider.")
    }
}

/// « Dis Siri, demande à Endry combien Gander nous doit » : réponse sur l'iPhone, à partir des données du PC.
/// Une demande de travail ou une question pour le bureau n'est jamais transmise d'ici : elle se confirme dans l'app.
struct DemanderAEndry: AppIntent {
    static let title: LocalizedStringResource = "Demander à Endry"
    static let description: IntentDescription? = IntentDescription("Pose une question sur les chantiers, les décisions ou l’argent.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Question", requestValueDialog: "Que voulez-vous savoir ?")
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let lot = await DonneesArrierePlan.charger() else {
            return .result(dialog: "Je n’arrive pas à joindre le bureau.")
        }
        let donnees = RepondeurLocal.Donnees(accueil: lot.accueil, argent: lot.argent, chantiers: lot.chantiers?.chantiers ?? [])
        switch RepondeurLocal.repondre(question, avec: donnees) {
        case .dire(let texte, _):
            return .result(dialog: "\(TexteParle.nettoyer(texte))")
        case .transmettre:
            return .result(dialog: "C’est une demande de travail pour le bureau. Ouvrez Endry pour la relire et la transmettre.")
        case .demanderClaude:
            return .result(dialog: "C’est une question pour l’assistant du bureau. Ouvrez Endry pour l’envoyer ; il répondra à son prochain passage.")
        case .etatBureau:
            let pause = lot.accueil?.pause ?? false
            return .result(dialog: "\(pause ? "L’assistant du bureau est en pause : vos décisions s’exécutent, il ne prépare rien de nouveau." : "L’assistant du bureau travaille. Ouvrez Endry pour voir ce qu’il fait.")")
        }
    }
}

// MARK: - Chantiers (Siri, Spotlight)

/// Un chantier, tel que Siri et Spotlight le connaissent (titre, client, lieu : aucun montant).
struct ChantierEntite: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Chantier"
    static let defaultQuery = RequeteChantiers()

    var id: String
    var titre: String
    var sousTitre: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(titre)", subtitle: "\(sousTitre)", image: .init(systemName: "hammer.fill"))
    }

    init(id: String, titre: String, sousTitre: String) {
        self.id = id
        self.titre = titre
        self.sousTitre = sousTitre
    }

    init(_ d: Dossier) {
        self.init(id: d.id, titre: d.titre, sousTitre: [d.client, d.lieu].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
    }
}

struct RequeteChantiers: EntityStringQuery {
    func entities(for identifiers: [ChantierEntite.ID]) async throws -> [ChantierEntite] {
        RepertoireChantiers.lire().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ChantierEntite] {
        let q = string.lowercased()
        return RepertoireChantiers.lire().filter { "\($0.titre) \($0.sousTitre)".lowercased().contains(q) }
    }

    func suggestedEntities() async throws -> [ChantierEntite] {
        Array(RepertoireChantiers.lire().prefix(12))
    }
}

/// Ouvre la fiche d'un chantier (Siri, Spotlight, bouton Action).
struct OuvrirChantier: OpenIntent {
    static let title: LocalizedStringResource = "Ouvrir un chantier"

    @Parameter(title: "Chantier")
    var target: ChantierEntite

    @MainActor
    func perform() async throws -> some IntentResult {
        DemandesRaccourcis.partage.chantier = target.id
        return .result()
    }
}

/// Liste des chantiers connue de Siri et de Spotlight, mise à jour quand l'app charge ses données.
enum RepertoireChantiers {
    private static let cle = "repertoire-chantiers"

    static func lire() -> [ChantierEntite] {
        guard let lignes = UserDefaults.standard.array(forKey: cle) as? [[String]] else { return [] }
        return lignes.compactMap { l in l.count == 3 ? ChantierEntite(id: l[0], titre: l[1], sousTitre: l[2]) : nil }
    }

    static func mettreAJour(_ chantiers: [Dossier]) async {
        let entites = chantiers.map(ChantierEntite.init)
        UserDefaults.standard.set(entites.map { [$0.id, $0.titre, $0.sousTitre] }, forKey: cle)
        RaccourcisEndry.updateAppShortcutParameters()
        try? await CSSearchableIndex.default().indexAppEntities(entites)
    }

    static func effacer() async {
        UserDefaults.standard.removeObject(forKey: cle)
        try? await CSSearchableIndex.default().deleteAppEntities(ofType: ChantierEntite.self)
    }
}

// MARK: - Phrases

struct RaccourcisEndry: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: BriefingEndry(), phrases: [
            "Briefing \(.applicationName)",
            "Le briefing \(.applicationName)",
            "Quoi de neuf chez \(.applicationName)",
        ], shortTitle: "Briefing", systemImageName: "sunrise.fill")
        AppShortcut(intent: ParlerAEndry(), phrases: [
            "Parler à \(.applicationName)",
            "Ouvrir l’assistant \(.applicationName)",
        ], shortTitle: "Parler à Endry", systemImageName: "waveform")
        AppShortcut(intent: DemanderAEndry(), phrases: [
            "Demander à \(.applicationName)",
            "Question pour \(.applicationName)",
        ], shortTitle: "Demander", systemImageName: "questionmark.bubble")
        AppShortcut(intent: DecisionsEndry(), phrases: [
            "Décisions \(.applicationName)",
            "Qu’est-ce qui m’attend dans \(.applicationName)",
        ], shortTitle: "Décisions", systemImageName: "checkmark.seal")
        AppShortcut(intent: NouveauBonRegie(), phrases: [
            "Bon de régie \(.applicationName)",
            "Nouvelle régie \(.applicationName)",
        ], shortTitle: "Bon de régie", systemImageName: "signature")
        AppShortcut(intent: ScannerBonLivraison(), phrases: [
            "Bon de livraison \(.applicationName)",
            "Scanner un bon avec \(.applicationName)",
        ], shortTitle: "Bon de livraison", systemImageName: "shippingbox")
        AppShortcut(intent: NouvelleOffre(), phrases: [
            "Nouvelle offre \(.applicationName)",
            "Faire une offre avec \(.applicationName)",
        ], shortTitle: "Nouvelle offre", systemImageName: "doc.badge.plus")
        AppShortcut(intent: NouvelleFacture(), phrases: [
            "Nouvelle facture \(.applicationName)",
            "Faire une facture avec \(.applicationName)",
        ], shortTitle: "Nouvelle facture", systemImageName: "doc.text")
        AppShortcut(intent: ReleverUnePiece(), phrases: [
            "Relevé 3D \(.applicationName)",
            "Mesurer une pièce avec \(.applicationName)",
        ], shortTitle: "Relevé 3D", systemImageName: "cube.transparent")
        AppShortcut(intent: OuvrirChantier(), phrases: [
            "Ouvrir \(\.$target) dans \(.applicationName)",
            "Chantier \(\.$target) \(.applicationName)",
        ], shortTitle: "Chantier", systemImageName: "hammer")
    }

    static let shortcutTileColor: ShortcutTileColor = .orange
}
