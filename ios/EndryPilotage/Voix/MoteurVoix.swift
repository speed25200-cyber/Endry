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
    /// Commande dite (« merci, c'est tout », « ouvre la conversation »…) que l'écran exécute.
    case commande(CommandeEcran)
}

/// Ce que l'écran de l'assistant fait sur commande vocale.
enum CommandeEcran: Equatable, Sendable {
    case fermer
    case ouvrirConversation
    case nouvelleConversation
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
    /// Le patron a fini sa phrase (toucher de la sphère) : réponse tout de suite, sans attendre le silence.
    func terminerPhrase()
    /// Réponse arrivée plus tard (Claude, sur le PC) : dite dès que la conversation le permet.
    func annoncer(question: String, reponse: String, agent: String?) async
    /// Courte information à dire (demande transmise, assistant hors horaires…).
    func signaler(_ texte: String) async
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
/// Réglages de l'assistant vocal.
enum ReglageVoix {
    static let cleEnvoiDirect = "voix.envoiDirect"
    /// Questions et demandes dites à voix haute : envoyées au bureau tout de suite (un instant pour annuler),
    /// comme dans une conversation ouverte avec l'assistant. Les Oui et les envois à des tiers gardent leur geste.
    static var envoiDirect: Bool { UserDefaults.standard.object(forKey: cleEnvoiDirect) as? Bool ?? true }
    /// Délai laissé pour annuler un envoi direct.
    static let delaiAnnulation: Duration = .milliseconds(1_400)

    static let cleDebit = "voix.debit"
    /// Débit de la voix d'Endry (multiplie le débit normal) : posé, normal, rapide, très rapide.
    static let debits: [(libelle: String, valeur: Double)] = [("Posé", 0.92), ("Normal", 1.02), ("Rapide", 1.12), ("Très rapide", 1.24)]
    static var debit: Double { UserDefaults.standard.object(forKey: cleDebit) as? Double ?? 1.02 }

    /// « Plus vite » / « plus lentement » : un cran de débit, sans sortir des quatre réglages.
    static func changerDebit(de pas: Int) {
        let valeurs = debits.map(\.valeur)
        let actuel = valeurs.indices.min { abs(valeurs[$0] - debit) < abs(valeurs[$1] - debit) } ?? 1
        let suivant = min(max(actuel + pas, 0), valeurs.count - 1)
        UserDefaults.standard.set(valeurs[suivant], forKey: cleDebit)
    }

    static let clePatience = "voix.patience"
    /// Temps de silence avant qu'Endry réponde (multiplie les délais de fin de phrase) : court, normal, long.
    static var patience: Double { UserDefaults.standard.object(forKey: clePatience) as? Double ?? 1.0 }

    static let cleReponseAuToucher = "voix.reponseAuToucher"
    /// Vrai : Endry ne répond que quand le patron touche la sphère (on peut marquer des pauses sans être coupé).
    static var reponseAuToucher: Bool { UserDefaults.standard.bool(forKey: cleReponseAuToucher) }

    static let cleConversationContinue = "voix.conversationContinue"
    /// Vrai : le micro reste ouvert pendant qu'Endry parle (annulation d'écho) ; on le coupe en parlant.
    /// Expérimental, donc désactivé par défaut : le tour à tour éprouvé reste le mode normal.
    static var conversationContinue: Bool { UserDefaults.standard.bool(forKey: cleConversationContinueV2) }
    /// Nouvelle clé : l'ancien réglage (actif par défaut) ne s'applique plus.
    static let cleConversationContinueV2 = "voix.conversationContinue.v2"

    static let cleLectureComplete = "voix.lectureComplete"
    /// Faux (par défaut) : une longue réponse du bureau est dite en résumé, le détail reste à l'écran.
    static var lectureComplete: Bool { UserDefaults.standard.bool(forKey: cleLectureComplete) }
}

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
    /// Dernière commande dite que l'écran doit exécuter (fermer, ouvrir la conversation), avec un identifiant
    /// pour que la même commande dite deux fois soit vue deux fois.
    private(set) var commande: (id: UUID, action: CommandeEcran)?
    /// Cartes qui partent d'elles-mêmes dans un instant (envoi direct), sauf « Annuler » ou modification.
    private(set) var envoisAuto: [ExecuteurOutils.Effet] = []
    /// Fil de la conversation avec le bureau (questions et réponses), le plus récent en dernier.
    private(set) var fil: [(question: String, reponse: String)] = []

    @ObservationIgnored private var moteur: (any MoteurVoix)?
    @ObservationIgnored private let bureau: BureauClaude?
    /// Transmission d'une demande de travail confirmée (file hors ligne de la saisie).
    @ObservationIgnored private let transmettre: (@MainActor (String) async -> ModeleSaisie.ResultatDemande)?
    @ObservationIgnored private var suivis: [String: Task<Void, Never>] = [:]
    /// Questions sans réponse après 60 s : revérifiées à chaque événement `maj saisies` du PC.
    @ObservationIgnored private var enAttente: [SuiviQuestion: (question: String, agent: String?)] = [:]
    @ObservationIgnored private var veille: Task<Void, Never>?
    @ObservationIgnored private var minuteries: [(effet: ExecuteurOutils.Effet, tache: Task<Void, Never>)] = []
    /// Même conversation pour les questions qui se suivent ; nouvelle après 30 min de silence.
    @ObservationIgnored private var conversation = UUID().uuidString
    @ObservationIgnored private var derniereQuestion = Date.distantPast
    /// Fil partagé avec l'écran « Conversation » : même `conversation_id`, même historique.
    @ObservationIgnored let partagee: ModeleConversation?
    /// Message du fil correspondant à chaque question en attente.
    @ObservationIgnored private var messagesSuivis: [SuiviQuestion: String] = [:]
    @ObservationIgnored private let fabrique: @MainActor () async -> any MoteurVoix
    @ObservationIgnored private let repli: @MainActor () -> any MoteurVoix

    init(fabrique: @escaping @MainActor () async -> any MoteurVoix, repli: @escaping @MainActor () -> any MoteurVoix,
         bureau: BureauClaude? = nil, transmettre: (@MainActor (String) async -> ModeleSaisie.ResultatDemande)? = nil,
         conversation: ModeleConversation? = nil) {
        self.partagee = conversation
        self.fabrique = fabrique
        self.repli = repli
        self.bureau = bureau
        self.transmettre = transmettre
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
        minuteries.forEach { $0.tache.cancel() }
        minuteries.removeAll()
        envoisAuto.removeAll()
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

    /// Toucher de la sphère pendant l'écoute : « j'ai fini », Endry répond sans attendre.
    func terminerPhrase() {
        moteur?.terminerPhrase()
    }


    func retirer(_ carte: ExecuteurOutils.Effet) {
        suspendreEnvoiAuto(carte)
        cartes.removeAll { $0 == carte }
    }

    /// Le patron touche le texte pour le modifier : il enverra lui-même.
    func suspendreEnvoiAuto(_ carte: ExecuteurOutils.Effet) {
        minuteries.filter { $0.effet == carte }.forEach { $0.tache.cancel() }
        minuteries.removeAll { $0.effet == carte }
        envoisAuto.removeAll { $0 == carte }
    }

    /// Envoi direct : la question (ou la demande) part après un court délai, sans autre geste.
    private func programmerEnvoi(_ effet: ExecuteurOutils.Effet, texte: String) {
        guard ReglageVoix.envoiDirect, !envoisAuto.contains(effet) else { return }
        envoisAuto.append(effet)
        let tache = Task { [weak self] in
            try? await Task.sleep(for: ReglageVoix.delaiAnnulation)
            guard !Task.isCancelled, let self, self.envoisAuto.contains(effet), self.cartes.contains(effet) else { return }
            self.envoisAuto.removeAll { $0 == effet }
            self.minuteries.removeAll { $0.effet == effet }
            await self.confirmer(effet, texte: texte)
        }
        minuteries.append((effet, tache))
    }

    /// Derniers échanges, pour que le bureau suive le fil (« et pour la Villa Morel ? »).
    private var contexte: String? {
        guard !fil.isEmpty else { return nil }
        return fil.suffix(3).map { "Q : \($0.question)\nR : \($0.reponse)" }.joined(separator: "\n")
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
            // Réponse qui s'écrit (modèle en flux) : les mots déjà dits restent allumés.
            if !texte.hasPrefix(reponse) { reponseLue = nil }
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
            switch effet {
            case .questionAConfirmer(let question, _, _): programmerEnvoi(effet, texte: question)
            case .saisieAConfirmer(let texte): programmerEnvoi(effet, texte: texte)
            default: break
            }
            if case .questionClaude(let suivi, let question, let agent, let message) = effet {
                if let message {
                    // Hors horaires : on le dit, on ne sonde pas ; la réponse viendra par notification.
                    enAttente[suivi] = (question, agent)
                    Task { await moteur?.signaler(message) }
                } else {
                    suivre(suivi, question: question, agent: agent)
                }
            }
        case .nouveauTour:
            definitif = ""
            provisoire = ""
            reponse = ""
            reponseLue = nil
        case .commande(let action):
            if action == .nouvelleConversation {
                partagee?.nouvelleConversation()
                conversation = UUID().uuidString
                fil.removeAll()
            }
            commande = (UUID(), action)
        }
    }

    // MARK: - Claude, sur le PC

    /// Le patron a relu et touche « Envoyer » ou « Transmettre » : c'est seulement maintenant que ça part.
    func confirmer(_ effet: ExecuteurOutils.Effet, texte: String) async {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return }
        switch effet {
        case .saisieAConfirmer:
            retirer(effet)
            guard let transmettre else {
                await moteur?.signaler("Connectez d’abord l’app au bureau.")
                return
            }
            let resultat = await transmettre(propre)
            partagee?.consignerDemande(propre, source: .voix, resultat: resultat)
            switch resultat {
            case .transmise: await moteur?.signaler("Transmis au bureau. Je vous préviens dès que c’est prêt.")
            case .gardee: await moteur?.signaler("Pas de réseau : la demande est gardée et partira toute seule.")
            case .refusee(let raison): await moteur?.signaler("La demande n’est pas partie. \(raison)")
            }
        case .questionAConfirmer(_, let agent, let agentId):
            guard let bureau else { return }
            if Date().timeIntervalSince(derniereQuestion) > 30 * 60 {
                conversation = UUID().uuidString
                fil.removeAll()
            }
            derniereQuestion = Date()
            // Le fil partagé passe d'abord : ce qui est dit ici se retrouve dans « Conversation », et inversement.
            let contexteEnvoye = partagee?.contexte ?? contexte
            let idMessage = partagee?.consignerQuestion(propre, source: .voix, agent: agent)
            let idFil = idMessage.flatMap { id in partagee?.messages.first { $0.id == id }?.conversation } ?? conversation
            do {
                let posee = try await bureau.poser(propre, agentId: agentId, nomAgent: agent, conversation: idFil, contexte: contexteEnvoye)
                retirer(effet)
                switch posee {
                case .reponse(let r):
                    fil.append((propre, r.reponse ?? ""))
                    if let idMessage { partagee?.repondre(idMessage, avec: r) }
                    let finale = ExecuteurOutils.Effet.reponseClaude(question: propre, reponse: r.reponse ?? "", agent: agent)
                    ajouter(finale)
                    await moteur?.annoncer(question: propre, reponse: r.reponse ?? "", agent: agent)
                case .enAttente(let suivi, let message):
                    if let idMessage {
                        messagesSuivis[suivi] = idMessage
                        partagee?.attendre(idMessage, suivi: suivi, message: message)
                        if message != nil { partagee?.differer(idMessage, message: message) }
                    }
                    recevoir(.effet(.questionClaude(suivi: suivi, question: propre, agent: agent, message: message)))
                }
            } catch {
                if let idMessage { partagee?.repondre(idMessage, texte: "La question n’est pas partie. \(error.message)", etat: .erreur) }
                await moteur?.signaler("La question n’est pas partie. \(error.message)")
            }
        default:
            break
        }
    }

    /// Réponses arrivées depuis (appelé sur chaque `maj saisies` du PC).
    func verifierEnAttente() async {
        guard let bureau else { return }
        for (suivi, infos) in enAttente {
            guard let r = await bureau.verifier(suivi) else { continue }
            enAttente[suivi] = nil
            await finaliser(suivi, resultat: r, question: infos.question, agent: infos.agent)
        }
    }

    private func ajouter(_ effet: ExecuteurOutils.Effet) {
        cartes.removeAll { $0 == effet }
        cartes.insert(effet, at: 0)
        if cartes.count > 3 { cartes.removeLast() }
    }

    /// Attend la réponse 60 s (`GET /questions/{id}` toutes les 2 s) ; ensuite, on attend `maj saisies`.
    private func suivre(_ suivi: SuiviQuestion, question: String, agent: String?) {
        let cle = "\(suivi)"
        guard let bureau, suivis[cle] == nil else { return }
        suivis[cle] = Task { [weak self] in
            let resultat = await bureau.attendre(suivi)
            guard !Task.isCancelled, let self else { return }
            self.suivis[cle] = nil
            guard let resultat else {
                self.enAttente[suivi] = (question, agent)
                if let id = self.messagesSuivis[suivi] { self.partagee?.differer(id, message: nil) }
                let attente = ExecuteurOutils.Effet.questionClaude(suivi: suivi, question: question, agent: agent, message: nil)
                if let index = self.cartes.firstIndex(of: attente) {
                    self.cartes[index] = .questionClaude(suivi: suivi, question: question, agent: agent,
                                                         message: BureauClaude.reponseAVenir)
                }
                return
            }
            await self.finaliser(suivi, resultat: resultat, question: question, agent: agent)
        }
    }

    private func finaliser(_ suivi: SuiviQuestion, resultat: ReponseAgent, question: String, agent: String?) async {
        let reponse: String
        if resultat.statut == .repondu, let texte = resultat.reponse, !texte.isEmpty {
            reponse = texte
        } else {
            reponse = resultat.message ?? "L’assistant n’a pas pu traiter la question sur le PC."
        }
        cartes.removeAll {
            if case .questionClaude(let s, _, _, _) = $0 { return s == suivi }
            return false
        }
        fil.append((question, reponse))
        if fil.count > 20 { fil.removeFirst(fil.count - 20) }
        if let id = messagesSuivis.removeValue(forKey: suivi) { partagee?.repondre(id, avec: resultat) }
        ajouter(.reponseClaude(question: question, reponse: reponse, agent: agent))
        await moteur?.annoncer(question: question, reponse: reponse, agent: agent)
        if let bureau { etatBureau = await bureau.etat() ?? etatBureau }
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
