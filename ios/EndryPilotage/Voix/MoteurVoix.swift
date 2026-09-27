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
    /// La synthèse vocale a dit la réponse jusqu'à ce décalage (UTF-16) : les mots s'allument au fil de la voix.
    case progressionParole(Int)
}

/// Protocole commun aux deux moteurs : temps réel (parole-à-parole) et local (repli gratuit).
@MainActor
protocol MoteurVoix: AnyObject {
    /// Nom lisible, affiché discrètement (« Temps réel », « Sur l'iPhone »).
    var nom: String { get }
    func demarrer(surEvenement: @escaping @MainActor (EvenementVoix) -> Void) async throws
    func arreter()
    /// Question tapée au clavier, traitée comme une question dite.
    func poser(_ question: String) async
    /// L'assistant se tait et rend la parole au patron.
    func interrompre()
    /// Réponse arrivée plus tard (Claude, sur le PC) : dite dès que la conversation le permet.
    func annoncer(question: String, reponse: String, agent: String?) async
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
    /// Partie de la réponse déjà dite (UTF-16) ; `nil` : tout est affiché.
    private(set) var reponseLue: Int?
    private(set) var niveauMicro: Float = 0
    private(set) var niveauVoix: Float = 0
    /// Cartes contextuelles, de la plus récente à la plus ancienne.
    private(set) var cartes: [ExecuteurOutils.Effet] = []
    private(set) var nomMoteur = ""
    /// Le moteur accepte les questions (dites ou tapées).
    private(set) var pret = false

    /// Activité de Claude sur le PC (pastille en haut de l'écran), rafraîchie toutes les 10 s.
    private(set) var etatBureau: EtatBureau?

    @ObservationIgnored private var moteur: (any MoteurVoix)?
    @ObservationIgnored private let bureau: BureauClaude?
    @ObservationIgnored private var suivis: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var veille: Task<Void, Never>?
    @ObservationIgnored private let fabrique: @MainActor () async -> any MoteurVoix
    @ObservationIgnored private let repli: @MainActor () -> any MoteurVoix

    init(fabrique: @escaping @MainActor () async -> any MoteurVoix, repli: @escaping @MainActor () -> any MoteurVoix,
         bureau: BureauClaude? = nil) {
        self.fabrique = fabrique
        self.repli = repli
        self.bureau = bureau
    }

    func demarrer() async {
        phase = .preparation
        pret = false
        surveillerBureau()
        let premier = await fabrique()
        do {
            try await lancer(premier)
        } catch ErreurVoix.autorisationRefusee {
            // Sans micro, on peut encore écrire à Endry.
            pret = true
            phase = .erreur("Micro non autorisé (Réglages › Endry). Vous pouvez écrire votre question.")
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
        pret = false
        veille?.cancel()
        veille = nil
        suivis.values.forEach { $0.cancel() }
        suivis.removeAll()
        niveauMicro = 0
        niveauVoix = 0
    }

    /// Question tapée ou suggestion touchée.
    func poser(_ question: String) async {
        let texte = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty, let moteur else { return }
        await moteur.poser(texte)
    }

    func interrompre() {
        moteur?.interrompre()
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
        pret = true
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
            if texte != reponse { reponseLue = nil }
            reponse = texte
        case .progressionParole(let lu):
            reponseLue = lu
        case .niveauMicro(let n):
            niveauMicro = niveauMicro * 0.55 + n * 0.45
        case .niveauVoix(let n):
            niveauVoix = niveauVoix * 0.5 + n * 0.5
        case .effet(let effet):
            guard effet != .aucun else { return }
            cartes.removeAll { $0 == effet }
            cartes.insert(effet, at: 0)
            if cartes.count > 3 { cartes.removeLast() }
            if case .questionClaude(let id, let texte, let question, let agent) = effet {
                suivre(saisieId: id, texte: texte, question: question, agent: agent)
            }
        case .nouveauTour:
            definitif = ""
            provisoire = ""
            reponse = ""
            reponseLue = nil
        }
    }

    // MARK: - Claude, sur le PC

    /// Attend la réponse de Claude ; dès qu'elle arrive, la carte « Claude cherche » devient la réponse, et Endry la dit.
    private func suivre(saisieId: String?, texte: String, question: String, agent: String?) {
        guard let bureau, suivis[texte] == nil else { return }
        suivis[texte] = Task { [weak self] in
            let saisie = await bureau.attendre(saisieId: saisieId, texte: texte)
            guard !Task.isCancelled, let self else { return }
            self.suivis[texte] = nil
            let attente = ExecuteurOutils.Effet.questionClaude(saisieId: saisieId, texte: texte, question: question, agent: agent)
            let reponse: String
            if let saisie, saisie.statut == .traite, let resume = saisie.resume, !resume.isEmpty {
                reponse = resume
            } else if saisie?.statut == .erreur {
                reponse = "Claude n’a pas pu traiter la question sur le PC."
            } else {
                reponse = "Claude n’a pas encore répondu. Sa réponse apparaîtra dans l’historique de Dicter."
            }
            let finale = ExecuteurOutils.Effet.reponseClaude(question: question, reponse: reponse, agent: agent)
            if let index = self.cartes.firstIndex(of: attente) {
                self.cartes[index] = finale
            } else {
                self.cartes.insert(finale, at: 0)
                if self.cartes.count > 3 { self.cartes.removeLast() }
            }
            await self.moteur?.annoncer(question: question, reponse: reponse, agent: agent)
            self.etatBureau = await bureau.etat() ?? self.etatBureau
        }
    }

    /// Pastille « Claude travaille · 2 en cours » : rafraîchie tant que l'assistant est ouvert.
    private func surveillerBureau() {
        guard let bureau, veille == nil else { return }
        veille = Task { [weak self] in
            while !Task.isCancelled {
                let etat = await bureau.etat()
                guard !Task.isCancelled, let self else { return }
                if let etat { self.etatBureau = etat }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
}
