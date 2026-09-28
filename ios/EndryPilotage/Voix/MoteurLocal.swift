import AVFoundation
import EndryKit
import Foundation

/// Moteur sur l'iPhone, gratuit, sans clé et sans le PC.
///
/// Écoute sur l'iPhone (SpeechAnalyzer, ou SFSpeechRecognizer fr-CH), comprend et répond avec le modèle
/// d'Apple Intelligence embarqué (qui lit les données par les outils), parle avec la meilleure voix française
/// installée. Sans Apple Intelligence, il répond aux questions simples à partir des données en cache.
/// Rien ne part au PC par la voix : une question ou une demande s'affiche, le patron la relit et la confirme.
@MainActor
final class MoteurLocal: MoteurVoix {
    var nom: String { cerveau == nil ? "Sur l’iPhone" : "Apple Intelligence · sur l’iPhone" }

    private let donnees: @MainActor () -> RepondeurLocal.Donnees
    private let cerveau: (any CerveauVocal)?
    /// Outils (Claude sur le PC, données) ; `nil` tant que l'app n'est pas connectée.
    private let executeur: ExecuteurOutils?
    /// Réponses du PC ou informations arrivées pendant un tour : dites juste après.
    private var annoncesEnAttente: [(question: String?, texte: String, affiche: String?, borne: Int?)] = []
    private let synthese = AVSpeechSynthesizer()
    private let delegue = DelegueSynthese()
    private var transcripteur: (any Transcripteur)?
    private var surEvenement: (@MainActor (EvenementVoix) -> Void)?
    private var dernierDefinitif = ""
    private var dernierProvisoire = ""
    private var silence: Task<Void, Never>?
    private var pulsation: Task<Void, Never>?
    private var tourCommence = false
    private var actif = false
    private var enReflexion = false
    private var questionEnAttente: String?
    /// Endry est en train de parler (suivi local : on n'interroge pas la synthèse, qui peut se bloquer).
    private var enParole = false
    /// Dernière réponse dite (« répète »).
    private var derniereReponse: String?
    /// Réponse dite en résumé : les mots allumés s'arrêtent à la fin du résumé.
    private var bornePhrase: Int?

    init(donnees: @escaping @MainActor () -> RepondeurLocal.Donnees,
         cerveau: (any CerveauVocal)? = nil,
         executeur: ExecuteurOutils? = nil) {
        self.donnees = donnees
        self.cerveau = cerveau
        self.executeur = executeur
        synthese.delegate = delegue
    }

    func demarrer(surEvenement: @escaping @MainActor (EvenementVoix) -> Void) async throws {
        self.surEvenement = surEvenement
        actif = true
        delegue.surMot = { [weak self] fin in
            guard let self, self.actif else { return }
            self.surEvenement?(.progressionParole(min(fin, self.bornePhrase ?? fin)))
        }
        // Sans micro (refusé, ou tests d'interface), la conversation continue au clavier.
        guard !Configuration.testsUI else {
            surEvenement(.phase(.ecoute))
            return
        }
        guard await MoteurDictee.demanderAutorisations() else { throw ErreurVoix.autorisationRefusee }
        transcripteur = await FabriqueTranscripteur.meilleur()
        try await ecouter()
    }

    func arreter() {
        actif = false
        silence?.cancel()
        pulsation?.cancel()
        transcripteur?.arreter()
        transcripteur = nil
        if enParole { synthese.stopSpeaking(at: .immediate) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        surEvenement = nil
    }

    // MARK: - Écoute

    private func ecouter() async throws {
        guard actif else { return }
        guard let transcripteur else {
            surEvenement?(.phase(.ecoute))
            return
        }
        dernierDefinitif = ""
        dernierProvisoire = ""
        tourCommence = false
        try await transcripteur.demarrer(
            surTexte: { [weak self] definitif, provisoire in
                Task { @MainActor in self?.recu(definitif: definitif, provisoire: provisoire) }
            },
            surNiveau: { [weak self] niveau in
                Task { @MainActor in self?.surEvenement?(.niveauMicro(niveau)) }
            }
        )
        surEvenement?(.phase(.ecoute))
    }

    private func recu(definitif: String, provisoire: String) {
        guard actif else { return }
        if !tourCommence {
            tourCommence = true
            surEvenement?(.nouveauTour)
        }
        dernierDefinitif = definitif
        dernierProvisoire = provisoire
        surEvenement?(.patron(definitif: definitif, provisoire: provisoire))
        silence?.cancel()
        // Fin de phrase adaptative : réponse plus rapide quand la phrase est finie, plus de patience sur « euh… ».
        let delai = FinDePhrase.delai(definitif: definitif, provisoire: provisoire)
        silence = Task { [weak self] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled else { return }
            await self?.conclure()
        }
    }

    /// Question tapée au clavier : même chemin que la voix.
    func poser(_ question: String) async {
        guard actif else { return }
        silence?.cancel()
        transcripteur?.arreter()
        if enParole { synthese.stopSpeaking(at: .immediate) }
        guard !enReflexion else {
            // Un tour est encore en cours : la question passe juste après.
            questionEnAttente = question
            return
        }
        dernierDefinitif = question
        dernierProvisoire = ""
        surEvenement?(.nouveauTour)
        await conclure()
    }

    /// Réponse de Claude arrivée du PC : dite tout de suite si Endry est libre, sinon juste après le tour en cours.
    func annoncer(question: String, reponse: String, agent: String?) async {
        let qui = agent.map { "L’assistant, côté \($0), répond : " } ?? "L’assistant répond : "
        // Longue réponse : le début est dit, tout est affiché (et gardé dans la conversation).
        let resume = ResumeOral.pourLaVoix(reponse)
        if ReglageVoix.lectureComplete || resume.complet {
            await annoncer(question: question, texte: qui + ResumeOral.lisible(reponse))
        } else {
            await annoncer(question: question, texte: qui + resume.dit + ResumeOral.renvoi,
                           affiche: qui + ResumeOral.lisible(reponse), borne: (qui + resume.dit).utf16.count)
        }
    }

    func signaler(_ texte: String) async {
        await annoncer(question: nil, texte: texte)
    }

    private func annoncer(question: String?, texte: String, affiche: String? = nil, borne: Int? = nil) async {
        guard actif else { return }
        annoncesEnAttente.append((question, texte, affiche, borne))
        guard !enReflexion else { return }
        enReflexion = true
        silence?.cancel()
        transcripteur?.arreter()
        await terminerTour()
    }

    /// Toucher la sphère pendant qu'Endry parle : il se tait et écoute.
    func interrompre() {
        if enParole { synthese.stopSpeaking(at: .word) }
    }

    /// Fin de phrase détectée : réponse d'Apple Intelligence, sinon réponse locale ou transmission au PC.
    private func conclure() async {
        guard !enReflexion else { return }
        enReflexion = true
        transcripteur?.arreter()
        let question = [dernierDefinitif, dernierProvisoire]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !question.isEmpty else {
            await terminerTour()
            return
        }
        surEvenement?(.patron(definitif: question, provisoire: ""))
        surEvenement?(.phase(.reflexion))

        // « Répète », « merci, c'est tout », « plus lentement »… : tout de suite, sans modèle ni bureau.
        if let commande = CommandeVocale.detecter(question) {
            await executer(commande)
            return
        }

        // Envoi direct (réglage par défaut) : ce que l'iPhone sait déjà, il le dit tout de suite ; tout le reste part
        // aussitôt au bureau, sans passer par le modèle de l'iPhone (plus rapide, et c'est Claude qui a les dossiers).
        if ReglageVoix.envoiDirect {
            switch RepondeurLocal.repondre(question, avec: donnees()) {
            case .dire(let texte, let carte):
                surEvenement?(.effet(carte))
                await dire(texte)
                await terminerTour()
                return
            case .demanderClaude(let q):
                await demanderClaude(q)
                await terminerTour()
                return
            case .transmettre(let demande):
                surEvenement?(.effet(.saisieAConfirmer(texte: demande)))
                await dire("J’envoie la demande au bureau.")
                await terminerTour()
                return
            case .etatBureau:
                break
            }
        }

        if let cerveau, let reponse = await cerveau.repondre(question, delai: .seconds(20)) {
            for effet in reponse.effets { surEvenement?(.effet(effet)) }
            await dire(reponse.texte)
            await terminerTour()
            return
        }

        switch RepondeurLocal.repondre(question, avec: donnees()) {
        case .dire(let texte, let carte):
            surEvenement?(.effet(carte))
            await dire(texte)
        case .demanderClaude(let q):
            await demanderClaude(q)
        case .etatBureau:
            if let executeur, let etat = await BureauClaude(api: executeur.api).etat() {
                // « Que fait le secrétariat ? » : cet agent seulement ; sinon tout le bureau.
                await dire(etat.agent(cite: question).map { etat.phrase(agent: $0) } ?? etat.phrase)
            } else {
                await dire("Je n’arrive pas à voir l’activité du PC pour l’instant.")
            }
        case .transmettre(let demande):
            // Jamais transmis d'office : la demande s'affiche, le patron la relit et touche « Transmettre ».
            surEvenement?(.effet(.saisieAConfirmer(texte: demande)))
            await dire("Voici la demande pour le bureau. Relisez-la, puis touchez Transmettre.")
        }
        await terminerTour()
    }

    private func executer(_ commande: CommandeVocale) async {
        switch commande {
        case .repeter:
            if let derniere = derniereReponse {
                await dire(derniere)
            } else {
                await dire("Je n’ai encore rien dit. Posez-moi une question.", memoriser: false)
            }
        case .terminer:
            await dire("Avec plaisir.", memoriser: false)
            // Pas de nouveau tour : l'écran se ferme.
            surEvenement?(.commande(.fermer))
            return
        case .ouvrirConversation:
            await dire("J’ouvre la conversation.", memoriser: false)
            surEvenement?(.commande(.ouvrirConversation))
            return
        case .nouvelleConversation:
            surEvenement?(.commande(.nouvelleConversation))
            await dire("C’est noté, on change de sujet.", memoriser: false)
        case .plusLentement:
            ReglageVoix.changerDebit(de: -1)
            await dire("D’accord, je parle plus lentement.", memoriser: false)
        case .plusVite:
            ReglageVoix.changerDebit(de: 1)
            await dire("D’accord, je parle plus vite.", memoriser: false)
        }
        await terminerTour()
    }

    /// Question pour l'assistant du PC : elle s'affiche, le patron la relit et touche « Envoyer ».
    private func demanderClaude(_ question: String) async {
        guard let executeur else {
            await dire("Connectez d’abord l’app au bureau pour interroger l’assistant.")
            return
        }
        let r = await executeur.executer(nom: "demander_assistant", arguments: Self.json(["question": question]))
        surEvenement?(.effet(r.effet))
        if case .questionAConfirmer(_, let agent, _) = r.effet {
            let cote = agent.map { ", côté \($0)" } ?? ""
            if ReglageVoix.envoiDirect {
                await dire("Je pose la question au bureau\(cote).")
            } else {
                await dire("Voici la question pour l’assistant du bureau\(cote). Touchez Envoyer : il répondra à son prochain passage.")
            }
        } else {
            await dire("Je n’ai pas pu préparer la question.")
        }
    }

    private static func json(_ objet: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: objet) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Fin du tour : réponse de Claude arrivée entre-temps, question tapée, sinon on rend le micro au patron.
    private func terminerTour() async {
        if !annoncesEnAttente.isEmpty, actif {
            let annonce = annoncesEnAttente.removeFirst()
            enReflexion = true
            surEvenement?(.nouveauTour)
            if let question = annonce.question { surEvenement?(.patron(definitif: question, provisoire: "")) }
            await dire(annonce.texte, affiche: annonce.affiche, borne: annonce.borne)
            await terminerTour()
            return
        }
        enReflexion = false
        if let suivante = questionEnAttente {
            questionEnAttente = nil
            dernierDefinitif = suivante
            dernierProvisoire = ""
            surEvenement?(.nouveauTour)
            await conclure()
        } else {
            try? await ecouter()
        }
    }

    // MARK: - Parole

    /// `affiche` : texte montré (plus long que le texte dit quand la réponse est dite en résumé) ;
    /// `borne` : fin du texte dit dans le texte montré.
    private func dire(_ texte: String, affiche: String? = nil, borne: Int? = nil, memoriser: Bool = true) async {
        guard actif else { return }
        if memoriser { derniereReponse = texte }
        bornePhrase = borne
        surEvenement?(.assistant(affiche ?? texte))
        surEvenement?(.progressionParole(0))
        surEvenement?(.phase(.parole))
        // Durée maximale : si la synthèse vocale se bloque (service audio indisponible), Endry passe à la suite
        // au lieu d'attendre indéfiniment la fin de sa phrase.
        let dureeMax = 3 + Double(texte.count) * 0.1
        guard !Configuration.testsUI else {
            // Tests d'interface : pas de synthèse (le simulateur de la CI n'a pas de sortie audio fiable).
            try? await Task.sleep(for: .milliseconds(300))
            bornePhrase = nil
            surEvenement?(.progressionParole((affiche ?? texte).utf16.count))
            return
        }
        let enonce = AVSpeechUtterance(string: texte)
        enonce.voice = Self.meilleureVoix()
        enonce.rate = min(AVSpeechUtteranceDefaultSpeechRate * Float(ReglageVoix.debit), AVSpeechUtteranceMaximumSpeechRate)
        enonce.pitchMultiplier = 0.98
        enonce.postUtteranceDelay = 0.1
        delegue.termine = false
        enParole = true
        synthese.speak(enonce)
        // La synthèse ne publie pas son niveau : la sphère suit une pulsation calée sur le débit de parole.
        let debut = Date()
        while actif, !delegue.termine || Date().timeIntervalSince(debut) < 0.3, Date().timeIntervalSince(debut) < dureeMax {
            let t = Date().timeIntervalSince(debut)
            let niveau = Float(0.45 + 0.35 * abs(sin(t * 7.3)) * (0.7 + 0.3 * sin(t * 2.1)))
            surEvenement?(.niveauVoix(niveau))
            try? await Task.sleep(for: .milliseconds(50))
        }
        if !delegue.termine { synthese.stopSpeaking(at: .immediate) }
        enParole = false
        bornePhrase = nil
        surEvenement?(.niveauVoix(0))
        surEvenement?(.progressionParole((affiche ?? texte).utf16.count))
    }


    /// Voix choisie dans Réglages › Voix d'Endry, sinon la meilleure voix française installée :
    /// Premium, puis Améliorée ; fr-CH avant fr-FR.
    static func meilleureVoix() -> AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: VoixEndry.cle), let choisie = AVSpeechSynthesisVoice(identifier: id) {
            return choisie
        }
        func score(_ voix: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            switch voix.quality {
            case .premium: s += 30
            case .enhanced: s += 20
            default: break
            }
            if voix.language == "fr-CH" { s += 5 } else if voix.language == "fr-FR" { s += 3 }
            return s
        }
        let francaises = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("fr") }
        return francaises.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: "fr-FR")
    }
}

/// Suit la synthèse vocale mot à mot, pour allumer la réponse au rythme de la voix.
final class DelegueSynthese: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    /// Posé une fois, sur l'acteur principal, avant la première phrase.
    var surMot: (@MainActor @Sendable (Int) -> Void)?
    private let verrou = NSLock()
    private var fini = false
    /// Vrai quand la phrase en cours est dite jusqu'au bout (ou annulée).
    var termine: Bool {
        get { verrou.withLock { fini } }
        set { verrou.withLock { fini = newValue } }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        termine = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        termine = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        let fin = characterRange.location + characterRange.length
        guard let rappel = surMot else { return }
        Task { @MainActor in rappel(fin) }
    }
}
