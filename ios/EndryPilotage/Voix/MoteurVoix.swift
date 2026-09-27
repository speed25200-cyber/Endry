import EndryKit
import Foundation
import Observation

/// Phase de la conversation, qui pilote la sphère.
enum PhaseVoix: Equatable, Sendable {
    case preparation
    case ecoute
    case reflexion
    case parole
    case erreur(String)
}

/// Ce que remonte un moteur vocal pendant la conversation.
enum EvenementVoix: Sendable {
    case phase(PhaseVoix)
    /// Transcription du patron : partie définitive et partie encore provisoire (affichée plus pâle).
    case patron(definitif: String, provisoire: String)
    /// Ce que dit l'assistant (texte cumulé du tour en cours).
    case assistant(String)
    /// Niveau du micro (0…1).
    case niveauMicro(Float)
    /// Niveau de la voix de l'assistant (0…1).
    case niveauVoix(Float)
    /// Carte contextuelle à faire surgir (chantier, facture, décision à valider par un geste).
    case effet(ExecuteurOutils.Effet)
    /// Nouveau tour de parole : on efface la transcription précédente.
    case nouveauTour
}

/// Protocole commun aux deux moteurs : temps réel (parole-à-parole) et local (repli gratuit).
@MainActor
protocol MoteurVoix: AnyObject {
    /// Nom lisible, affiché discrètement (« Temps réel », « Sur l'iPhone »).
    var nom: String { get }
    func demarrer(surEvenement: @escaping @MainActor (EvenementVoix) -> Void) async throws
    func arreter()
}

enum ErreurVoix: Error {
    case autorisationRefusee
    case indisponible
    case connexion
}

/// Conversation vocale : choisit le moteur, agrège les événements pour la vue plein écran.
///
/// Le moteur temps réel est essayé d'abord (session éphémère demandée au PC, l'app ne détient aucune clé) ;
/// si le PC répond `disponible: false` ou si la connexion échoue, on bascule sans bruit sur le moteur local.
@MainActor
@Observable
final class AssistantVocal {
    private(set) var phase: PhaseVoix = .preparation
    private(set) var definitif = ""
    private(set) var provisoire = ""
    private(set) var reponse = ""
    private(set) var niveauMicro: Float = 0
    private(set) var niveauVoix: Float = 0
    /// Cartes contextuelles, de la plus récente à la plus ancienne.
    private(set) var cartes: [ExecuteurOutils.Effet] = []
    private(set) var nomMoteur = ""

    @ObservationIgnored private var moteur: (any MoteurVoix)?
    @ObservationIgnored private let fabrique: @MainActor () async -> any MoteurVoix
    @ObservationIgnored private let repli: @MainActor () -> any MoteurVoix

    init(fabrique: @escaping @MainActor () async -> any MoteurVoix, repli: @escaping @MainActor () -> any MoteurVoix) {
        self.fabrique = fabrique
        self.repli = repli
    }

    func demarrer() async {
        phase = .preparation
        let premier = await fabrique()
        do {
            try await lancer(premier)
        } catch ErreurVoix.autorisationRefusee {
            phase = .erreur("Autorisez le micro et la reconnaissance vocale dans Réglages › Endry.")
        } catch {
            // Repli silencieux sur le moteur local.
            premier.arreter()
            do {
                try await lancer(repli())
            } catch {
                phase = .erreur("L’assistant vocal n’est pas disponible pour le moment.")
            }
        }
    }

    func arreter() {
        moteur?.arreter()
        moteur = nil
        niveauMicro = 0
        niveauVoix = 0
    }

    func retirer(_ carte: ExecuteurOutils.Effet) {
        cartes.removeAll { $0 == carte }
    }

    private func lancer(_ m: any MoteurVoix) async throws {
        moteur = m
        nomMoteur = m.nom
        try await m.demarrer { [weak self] evenement in
            self?.recevoir(evenement)
        }
    }

    private func recevoir(_ evenement: EvenementVoix) {
        switch evenement {
        case .phase(let p):
            phase = p
            if p != .parole { niveauVoix = 0 }
        case .patron(let d, let p):
            definitif = d
            provisoire = p
        case .assistant(let texte):
            reponse = texte
        case .niveauMicro(let n):
            niveauMicro = niveauMicro * 0.55 + n * 0.45
        case .niveauVoix(let n):
            niveauVoix = niveauVoix * 0.5 + n * 0.5
        case .effet(let effet):
            guard effet != .aucun else { return }
            cartes.removeAll { $0 == effet }
            cartes.insert(effet, at: 0)
            if cartes.count > 3 { cartes.removeLast() }
        case .nouveauTour:
            definitif = ""
            provisoire = ""
            reponse = ""
        }
    }
}
