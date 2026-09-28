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
    var nom: String {
        if canal != nil { return "Conversation continue · sur l’iPhone" }
        return cerveau == nil ? "Sur l’iPhone" : "Apple Intelligence · sur l’iPhone"
    }

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

    // MARK: Conversation continue (micro ouvert pendant qu'Endry parle)

    /// Même moteur audio pour le micro et la voix d'Endry : l'annulation d'écho du système efface sa voix
    /// de ce que le micro entend, et le patron peut le couper en parlant. `nil` : mode classique (tour à tour).
    private var canal: CanalAudioTempsReel?
    private var oreille: (any Oreille)?
    /// Ce qui est entendu compte comme le tour du patron (faux pendant la réflexion).
    private var ecouteOuverte = false
    /// Endry a été coupé : le tour suivant garde ce que le patron a déjà dit.
    private var interrompu = false
    /// Phrase qu'Endry disait quand il a été coupé : ses mots sont écartés (écho) au début du tour suivant.
    private var filtreEcho = ""
    /// Texte en train d'être dit (pour reconnaître l'écho).
    private var texteEnCours = ""
    private var dernierEntendu: (definitif: String, provisoire: String) = ("", "")
    /// Début de la réponse en cours, et délai après lequel le patron l'a coupée (suite de sa phrase ?).
    private var debutReponse: Date?
    private var coupeApres: TimeInterval?
    private var questionPrecedente = ""
    /// Réponse du bureau en cours d'annonce.
    private var enAnnonce = false
    /// Une réponse est en cours (parole, ou pause entre deux phrases qui s'écrivent) : le patron peut la couper.
    private var enReponse = false
    /// Décalage de la phrase dite dans le texte affiché (`nil` : phrase hors texte, comme « Je regarde »).
    private var decalagePhrase: Int? = 0

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
            // Conversation continue : la progression suit la lecture réelle, pas la synthèse.
            guard let self, self.actif, self.canal == nil, let decalage = self.decalagePhrase else { return }
            let lu = decalage + fin
            self.surEvenement?(.progressionParole(min(lu, self.bornePhrase ?? lu)))
        }
        // Sans micro (refusé, ou tests d'interface), la conversation continue au clavier.
        guard !Configuration.testsUI else {
            surEvenement(.phase(.ecoute))
            return
        }
        guard await MoteurDictee.demanderAutorisations() else { throw ErreurVoix.autorisationRefusee }
        if ReglageVoix.conversationContinue, await demarrerConversationContinueDansLeDelai() {
            try await ecouter()
            return
        }
        transcripteur = await FabriqueTranscripteur.meilleur()
        try await ecouter()
    }

    /// La conversation continue a 4 s pour démarrer ; sinon, le tour à tour éprouvé prend le relais
    /// (et ce qui démarrerait trop tard est arrêté aussitôt).
    private func demarrerConversationContinueDansLeDelai() async -> Bool {
        let unique = ReponseUnique()
        let resultat: ConversationContinuePrete? = await withCheckedContinuation { suite in
            Task { @MainActor in
                let pret = await self.preparerConversationContinue()
                if !unique.donner(pret, a: suite), let pret {
                    // Trop tard : le mode classique a pris le relais, on n'y touche pas.
                    pret.oreille.arreter()
                    pret.canal.arreter(desactiverSession: false)
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(4))
                _ = unique.donner(nil, a: suite)
            }
        }
        guard let resultat else { return false }
        oreille = resultat.oreille
        canal = resultat.canal
        return true
    }

    /// Micro et voix sur le même moteur audio, annulation d'écho : on peut couper Endry en parlant.
    /// `nil` (mode classique tour à tour) si la dictée d'iOS 26 manque ou si l'audio ne démarre pas.
    private func preparerConversationContinue() async -> ConversationContinuePrete? {
        guard #available(iOS 26.0, *), await TranscripteurAnalyseur.disponible() else { return nil }
        let ecoute = TranscripteurAnalyseur()
        let audio = CanalAudioTempsReel()
        do {
            try await ecoute.demarrerSansMicro { [weak self] definitif, provisoire in
                Task { @MainActor in self?.entendu(definitif: definitif, provisoire: provisoire) }
            }
            try audio.demarrer(
                surMorceau: { _ in },
                surNiveau: { [weak self] niveau in
                    Task { @MainActor in
                        guard let self, self.ecouteOuverte else { return }
                        self.surEvenement?(.niveauMicro(niveau))
                    }
                },
                surTampon: { tampon in ecoute.nourrir(tampon) }
            )
        } catch {
            ecoute.arreter()
            audio.arreter()
            return nil
        }
        return ConversationContinuePrete(oreille: ecoute, canal: audio)
    }

    /// Tout ce que le micro entend (conversation continue) : le tour du patron, ou il coupe Endry.
    private func entendu(definitif: String, provisoire: String) {
        guard actif else { return }
        dernierEntendu = (definitif, provisoire)
        let tout = [definitif, provisoire].filter { !$0.isEmpty }.joined(separator: " ")
        if enParole || enReponse {
            // Endry répond : seuls de vrais mots du patron (pas l'écho de sa voix) le coupent.
            if Interruption.couper(tout, pendant: texteEnCours) { couperEndry() }
            return
        }
        guard ecouteOuverte else { return }
        guard !filtreEcho.isEmpty else {
            recu(definitif: definitif, provisoire: provisoire)
            return
        }
        // Juste après une interruption : les derniers mots d'Endry encore entendus sont écartés.
        let propre = Interruption.sansEcho(tout, pendant: filtreEcho)
        guard !propre.isEmpty else { return }
        if provisoire.isEmpty {
            recu(definitif: propre, provisoire: "")
        } else {
            recu(definitif: "", provisoire: propre)
        }
    }

    /// Le patron parle pendant qu'Endry répond : Endry se tait aussitôt et l'écoute.
    private func couperEndry() {
        guard enParole || enReponse, !interrompu else { return }
        interrompu = true
        filtreEcho = texteEnCours
        coupeApres = debutReponse.map { Date().timeIntervalSince($0) }
        _ = canal?.interrompre()
        synthese.stopSpeaking(at: .immediate)
    }

    func arreter() {
        actif = false
        silence?.cancel()
        pulsation?.cancel()
        transcripteur?.arreter()
        transcripteur = nil
        if enParole { synthese.stopSpeaking(at: .immediate) }
        oreille?.arreter()
        oreille = nil
        canal?.arreter()
        canal = nil
        ecouteOuverte = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        surEvenement = nil
    }

    // MARK: - Écoute

    private func ecouter() async throws {
        guard actif else { return }
        if canal != nil {
            // Conversation continue : le micro n'a jamais été coupé, on ouvre simplement le tour du patron.
            dernierDefinitif = ""
            dernierProvisoire = ""
            tourCommence = false
            let repris = interrompu
            interrompu = false
            if !repris {
                oreille?.reinitialiser()
                filtreEcho = ""
                dernierEntendu = ("", "")
            }
            ecouteOuverte = true
            surEvenement?(.phase(.ecoute))
            // Coupé : ce que le patron a déjà dit est repris tout de suite.
            if repris { entendu(definitif: dernierEntendu.definitif, provisoire: dernierEntendu.provisoire) }
            return
        }
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
        // Réponse au toucher : on attend que le patron touche la sphère, quelles que soient ses pauses.
        guard !ReglageVoix.reponseAuToucher else { return }
        // Fin de phrase adaptative, jamais pressée : plus de patience sur « euh… », réglable (Réglages › Voix).
        let delai = FinDePhrase.delai(definitif: definitif, provisoire: provisoire, patience: ReglageVoix.patience)
        silence = Task { [weak self] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled else { return }
            await self?.conclure()
        }
    }

    /// Toucher de la sphère pendant l'écoute : la phrase est finie, réponse tout de suite.
    func terminerPhrase() {
        guard actif, !enReflexion, tourCommence else { return }
        silence?.cancel()
        Task { await conclure() }
    }

    /// Question tapée au clavier : même chemin que la voix.
    func poser(_ question: String) async {
        guard actif else { return }
        silence?.cancel()
        transcripteur?.arreter()
        ecouteOuverte = false
        if enParole {
            _ = canal?.interrompre()
            synthese.stopSpeaking(at: .immediate)
        }
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
        cerveau?.retenir(question: question, reponse: reponse)
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
        guard enParole || enReponse else { return }
        if canal == nil { interrompu = true }
        if canal != nil {
            // Toucher : Endry se tait, sans reprendre ce que le micro a pu entendre de sa voix.
            interrompu = true
            filtreEcho = texteEnCours
            dernierEntendu = ("", "")
            _ = canal?.interrompre()
        }
        synthese.stopSpeaking(at: .word)
    }

    /// Fin de phrase détectée : réponse d'Apple Intelligence, sinon réponse locale ou transmission au PC.
    private func conclure() async {
        guard !enReflexion else { return }
        enReflexion = true
        transcripteur?.arreter()
        ecouteOuverte = false
        var question = [dernierDefinitif, dernierProvisoire]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        // Coupé juste après avoir commencé à répondre : le patron continuait sa phrase.
        if let apres = coupeApres, !question.isEmpty {
            question = Interruption.suite(de: questionPrecedente, nouvelle: question, apres: apres)
        }
        coupeApres = nil
        filtreEcho = ""
        if !question.isEmpty { questionPrecedente = question }
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

        // Envoi direct (réglage par défaut) : ce que l'iPhone sait déjà, il le dit tout de suite (et le modèle
        // d'Apple le saura au tour suivant) ; une demande de travail part aussitôt au bureau.
        if ReglageVoix.envoiDirect {
            switch RepondeurLocal.repondre(question, avec: donnees()) {
            case .dire(let texte, let carte):
                surEvenement?(.effet(carte))
                await dire(texte)
                cerveau?.retenir(question: question, reponse: texte)
                await terminerTour()
                return
            case .transmettre(let demande):
                surEvenement?(.effet(.saisieAConfirmer(texte: demande)))
                await dire("J’envoie la demande au bureau.")
                cerveau?.retenir(question: question, reponse: "Demande transmise au bureau.")
                await terminerTour()
                return
            case .demanderClaude(let q):
                // Sans modèle sur l'iPhone : directement au bureau. Avec : le modèle converse, lit les données
                // et pose lui-même la question au bureau quand il le faut.
                if cerveau == nil {
                    await demanderClaude(q)
                    await terminerTour()
                    return
                }
            case .etatBureau:
                break
            }
        }

        // Le modèle d'Apple, sur l'iPhone : réponse dite phrase par phrase pendant qu'elle s'écrit.
        if let cerveau, await direEnFlux(cerveau, question: question) {
            await terminerTour()
            return
        }
        if ReglageVoix.envoiDirect, cerveau != nil, !interrompu {
            // Le modèle n'a pas su répondre : la question part au bureau.
            await demanderClaude(question)
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
            cerveau?.oublier()
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
                await dire("Voici la question pour l’assistant du bureau\(cote). Touchez Envoyer : le bureau s’en occupe tout de suite.")
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
        // Le patron vient de couper Endry : on l'écoute d'abord, l'annonce attendra le tour suivant.
        if !annoncesEnAttente.isEmpty, actif, !interrompu {
            let annonce = annoncesEnAttente.removeFirst()
            enReflexion = true
            surEvenement?(.nouveauTour)
            if let question = annonce.question { surEvenement?(.patron(definitif: question, provisoire: "")) }
            enAnnonce = true
            await dire(annonce.texte, affiche: annonce.affiche, borne: annonce.borne)
            enAnnonce = false
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
        guard !Configuration.testsUI else {
            // Tests d'interface : pas de synthèse (le simulateur de la CI n'a pas de sortie audio fiable).
            try? await Task.sleep(for: .milliseconds(300))
            bornePhrase = nil
            surEvenement?(.progressionParole((affiche ?? texte).utf16.count))
            return
        }
        commencerReponse()
        await prononcer(texte, decalage: 0)
        finirReponse(affiche ?? texte)
    }

    /// Réponse du modèle d'Apple dite phrase par phrase pendant qu'elle s'écrit (comme une conversation en direct).
    /// Faux : le modèle n'a rien su répondre (le moteur passe au bureau ou aux réponses locales).
    private func direEnFlux(_ cerveau: any CerveauVocal, question: String) async -> Bool {
        guard actif else { return false }
        let flux = cerveau.repondreEnFlux(question)
        let etat = EtatFlux()
        let lecture = Task { @MainActor [weak self] in
            do {
                for try await partiel in flux {
                    let propre = TexteParle.nettoyer(partiel, fini: false)
                    guard !propre.isEmpty else { continue }
                    etat.texte = propre
                    self?.surEvenement?(.assistant(propre))
                }
                etat.texte = TexteParle.nettoyer(etat.texte)
            } catch {
                etat.echec = true
            }
            etat.fini = true
        }
        commencerReponse()
        // Le texte s'écrit à l'écran en pâle ; les mots s'allument quand ils sont dits.
        surEvenement?(.progressionParole(0))
        var dit = 0
        var montres: Set<ExecuteurOutils.Effet> = []
        var premier = true
        var patienceDite = false
        let debut = Date()
        while actif, !interrompu {
            for effet in cerveau.effetsEnCours() where !montres.contains(effet) {
                montres.insert(effet)
                surEvenement?(.effet(effet))
            }
            if let suivante = DecoupeurPhrases.prochaine(etat.texte, depuis: dit, fini: etat.fini) {
                let (phrase, fin) = (suivante.phrase, suivante.fin)
                if premier {
                    premier = false
                    surEvenement?(.phase(.parole))
                }
                if Configuration.testsUI {
                    try? await Task.sleep(for: .milliseconds(150))
                    surEvenement?(.progressionParole(fin))
                } else {
                    await prononcer(phrase, decalage: dit)
                }
                dit = fin
                continue
            }
            if etat.fini { break }
            let attente = Date().timeIntervalSince(debut)
            if etat.texte.isEmpty {
                // Un outil lit les données : un mot pour que le patron sache qu'Endry travaille.
                if !patienceDite, attente > 1.2, cerveau.outilEnCours, !Configuration.testsUI {
                    patienceDite = true
                    surEvenement?(.phase(.parole))
                    await prononcer("Je regarde.", decalage: nil)
                    surEvenement?(.phase(.reflexion))
                }
                if attente > (cerveau.outilEnCours ? 15 : 8) {
                    // Trop long pour une conversation : on passe la main.
                    lecture.cancel()
                    break
                }
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        if interrompu || !actif { lecture.cancel() }
        for effet in cerveau.effetsEnCours() where !montres.contains(effet) { surEvenement?(.effet(effet)) }
        let texte = etat.texte
        if dit == 0, !interrompu {
            enReponse = false
            enParole = false
            return !texte.isEmpty
        }
        derniereReponse = texte
        finirReponse(texte)
        return true
    }

    private func commencerReponse() {
        // Une réponse du bureau annoncée n'est pas la suite d'une phrase du patron.
        debutReponse = enAnnonce ? nil : Date()
        texteEnCours = ""
        if canal != nil, !interrompu {
            oreille?.reinitialiser()
            dernierEntendu = ("", "")
        }
        interrompu = false
        ecouteOuverte = false
        enReponse = true
    }

    private func finirReponse(_ affiche: String) {
        if !interrompu { surEvenement?(.progressionParole(affiche.utf16.count)) }
        enReponse = false
        enParole = false
        bornePhrase = nil
        surEvenement?(.niveauVoix(0))
    }

    /// Dit une phrase ; les mots s'allument à partir de `decalage` dans le texte affiché (`nil` : rien à allumer).
    private func prononcer(_ phrase: String, decalage: Int?) async {
        guard actif, !interrompu else { return }
        let enonce = AVSpeechUtterance(string: phrase)
        enonce.voice = Self.meilleureVoix()
        enonce.rate = min(AVSpeechUtteranceDefaultSpeechRate * Float(ReglageVoix.debit), AVSpeechUtteranceMaximumSpeechRate)
        enonce.pitchMultiplier = 0.98
        // Durée maximale : si la synthèse vocale se bloque (service audio indisponible), Endry passe à la suite.
        let dureeMax = 3 + Double(phrase.count) * 0.1
        decalagePhrase = decalage
        if let canal {
            await prononcerEnContinu(enonce, phrase: phrase, decalage: decalage, canal: canal, dureeMax: dureeMax)
            return
        }
        enonce.postUtteranceDelay = 0.05
        delegue.termine = false
        enParole = true
        synthese.speak(enonce)
        // La synthèse ne publie pas son niveau : la sphère suit une pulsation calée sur le débit de parole.
        let debut = Date()
        while actif, !interrompu, !delegue.termine || Date().timeIntervalSince(debut) < 0.3, Date().timeIntervalSince(debut) < dureeMax {
            let t = Date().timeIntervalSince(debut)
            let niveau = Float(0.45 + 0.35 * abs(sin(t * 7.3)) * (0.7 + 0.3 * sin(t * 2.1)))
            surEvenement?(.niveauVoix(niveau))
            try? await Task.sleep(for: .milliseconds(50))
        }
        if !delegue.termine { synthese.stopSpeaking(at: .immediate) }
        enParole = false
    }

    /// Conversation continue : la voix passe par le moteur audio du micro (annulation d'écho) et le patron
    /// peut la couper en parlant. Les mots s'allument au rythme de la lecture réelle.
    private func prononcerEnContinu(_ enonce: AVSpeechUtterance, phrase: String, decalage: Int?, canal: CanalAudioTempsReel,
                                    dureeMax: Double) async {
        // Toute la réponse dite jusqu'ici sert à reconnaître l'écho de sa voix.
        texteEnCours = texteEnCours.isEmpty ? phrase : texteEnCours + " " + phrase
        canal.nouvelItem()
        let lue = SyntheseLue()
        delegue.termine = false
        enParole = true
        synthese.write(enonce, toBufferCallback: Self.rappelTampons(lue: lue, canal: canal))
        let longueur = phrase.utf16.count
        let debut = Date()
        while actif, !interrompu {
            let t = Date().timeIntervalSince(debut)
            let (total, fini) = lue.etat
            if t > dureeMax { break }
            if (fini || delegue.termine) && !canal.lectureEnCours && t > 0.3 { break }
            let niveau = Float(0.45 + 0.35 * abs(sin(t * 7.3)) * (0.7 + 0.3 * sin(t * 2.1)))
            surEvenement?(.niveauVoix(niveau))
            if total > 0, let decalage {
                let lu = decalage + Int(Double(longueur) * min(Double(canal.framesLues) / Double(total), 1))
                surEvenement?(.progressionParole(min(lu, bornePhrase ?? lu)))
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if !interrompu { _ = canal.interrompre() }
        synthese.stopSpeaking(at: .immediate)
        enParole = false
    }

    /// Rappel de la synthèse, appelé hors du fil principal : fabriqué hors de l'acteur principal
    /// (un bloc créé sur l'acteur principal y resterait lié et planterait appelé ailleurs).
    nonisolated private static func rappelTampons(lue: SyntheseLue, canal: CanalAudioTempsReel) -> @Sendable (AVAudioBuffer) -> Void {
        { tampon in
            guard let pcm = tampon as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                lue.terminer()
            } else {
                lue.ajouter(canal.jouerTampon(pcm))
            }
        }
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

/// Avancement de la synthèse vocale écrite en tampons (conversation continue).
nonisolated final class SyntheseLue: @unchecked Sendable {
    private let verrou = NSLock()
    private var images = 0
    private var fini = false

    func ajouter(_ n: Int) { verrou.withLock { images += n } }
    func terminer() { verrou.withLock { fini = true } }
    /// Images produites (24 kHz) et fin de la synthèse.
    var etat: (Int, Bool) { verrou.withLock { (images, fini) } }
}

/// Réponse du modèle qui s'écrit (lue par la boucle de parole).
@MainActor
final class EtatFlux {
    var texte = ""
    var fini = false
    var echec = false
}

/// Oreille et moteur audio de la conversation continue, démarrés.
struct ConversationContinuePrete: Sendable {
    let oreille: any Oreille
    let canal: CanalAudioTempsReel
}

/// Première réponse gagnante entre le démarrage et le délai de garde.
nonisolated final class ReponseUnique: @unchecked Sendable {
    private let verrou = NSLock()
    private var donnee = false

    /// Vrai si cette réponse est la première (la suite reprend avec elle).
    func donner<T: Sendable>(_ valeur: T, a suite: CheckedContinuation<T, Never>) -> Bool {
        let premiere = verrou.withLock { () -> Bool in
            if donnee { return false }
            donnee = true
            return true
        }
        if premiere { suite.resume(returning: valeur) }
        return premiere
    }
}
