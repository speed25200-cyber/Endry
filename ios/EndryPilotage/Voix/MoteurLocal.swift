import AVFoundation
import EndryKit
import Foundation

/// Moteur sur l'iPhone, gratuit, sans clé et sans le PC.
///
/// Écoute sur l'iPhone (SpeechAnalyzer, ou SFSpeechRecognizer fr-CH), comprend et répond avec le modèle
/// d'Apple Intelligence embarqué (qui lit les données par les outils), parle avec la meilleure voix française
/// installée. Sans Apple Intelligence, il répond aux questions simples à partir des données en cache et
/// transmet tout le reste à l'assistant du PC sous forme de saisie.
@MainActor
final class MoteurLocal: MoteurVoix {
    var nom: String { cerveau == nil ? "Sur l’iPhone" : "Apple Intelligence · sur l’iPhone" }

    private let donnees: @MainActor () -> RepondeurLocal.Donnees
    private let transmettre: @MainActor (String) async -> ModeleSaisie.ResultatDemande
    private let cerveau: (any CerveauVocal)?
    private let synthese = AVSpeechSynthesizer()
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

    /// Fin de phrase : silence après la dernière parole reconnue.
    private static let delaiSilence: Duration = .milliseconds(1_300)

    init(donnees: @escaping @MainActor () -> RepondeurLocal.Donnees,
         transmettre: @escaping @MainActor (String) async -> ModeleSaisie.ResultatDemande,
         cerveau: (any CerveauVocal)? = nil) {
        self.donnees = donnees
        self.transmettre = transmettre
        self.cerveau = cerveau
    }

    func demarrer(surEvenement: @escaping @MainActor (EvenementVoix) -> Void) async throws {
        self.surEvenement = surEvenement
        actif = true
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
        if synthese.isSpeaking { synthese.stopSpeaking(at: .immediate) }
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
        silence = Task { [weak self] in
            try? await Task.sleep(for: Self.delaiSilence)
            guard !Task.isCancelled else { return }
            await self?.conclure()
        }
    }

    /// Question tapée au clavier : même chemin que la voix.
    func poser(_ question: String) async {
        guard actif else { return }
        silence?.cancel()
        transcripteur?.arreter()
        if synthese.isSpeaking { synthese.stopSpeaking(at: .immediate) }
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

    /// Toucher la sphère pendant qu'Endry parle : il se tait et écoute.
    func interrompre() {
        if synthese.isSpeaking { synthese.stopSpeaking(at: .word) }
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

        if let cerveau, let reponse = await cerveau.repondre(question) {
            for effet in reponse.effets { surEvenement?(.effet(effet)) }
            await dire(reponse.texte)
            await terminerTour()
            return
        }

        switch RepondeurLocal.repondre(question, avec: donnees()) {
        case .dire(let texte, let carte):
            surEvenement?(.effet(carte))
            await dire(texte)
        case .transmettre(let demande):
            switch await transmettre(demande) {
            case .transmise:
                await dire("C’est transmis à l’assistant du bureau. Vous verrez la proposition dans vos décisions.")
            case .gardee:
                await dire("Pas de réseau pour l’instant : la demande est gardée et partira toute seule.")
            case .refusee(let raison):
                await dire("Je n’ai pas pu transmettre la demande. \(raison)")
            }
        }
        await terminerTour()
    }

    /// Fin du tour : question tapée entre-temps, sinon on rend le micro au patron.
    private func terminerTour() async {
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

    private func dire(_ texte: String) async {
        guard actif else { return }
        surEvenement?(.assistant(texte))
        surEvenement?(.phase(.parole))
        let enonce = AVSpeechUtterance(string: texte)
        enonce.voice = Self.meilleureVoix()
        enonce.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        enonce.pitchMultiplier = 0.98
        enonce.postUtteranceDelay = 0.1
        synthese.speak(enonce)
        // La synthèse ne publie pas son niveau : la sphère suit une pulsation calée sur le débit de parole.
        let debut = Date()
        while actif, synthese.isSpeaking || Date().timeIntervalSince(debut) < 0.3 {
            let t = Date().timeIntervalSince(debut)
            let niveau = Float(0.45 + 0.35 * abs(sin(t * 7.3)) * (0.7 + 0.3 * sin(t * 2.1)))
            surEvenement?(.niveauVoix(niveau))
            try? await Task.sleep(for: .milliseconds(50))
        }
        surEvenement?(.niveauVoix(0))
    }

    /// Meilleure voix française installée : Premium, puis Enhanced ; fr-CH avant fr-FR.
    static func meilleureVoix() -> AVSpeechSynthesisVoice? {
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
