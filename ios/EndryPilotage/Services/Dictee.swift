import AVFoundation
import EndryKit
import Foundation
import Observation
import Speech

/// Dictée en français de Suisse (`fr-CH`), sur l'appareil quand c'est possible.
///
/// L'audio et la reconnaissance tournent hors du fil principal ; seul l'état publié est sur le MainActor.
@MainActor
@Observable
final class Dictee {
    enum Etat: Equatable {
        case repos
        case ecoute
        case refuse(String)
        case indisponible(String)
    }

    private(set) var etat: Etat = .repos
    /// Texte reconnu pendant la session en cours.
    private(set) var transcription = ""
    /// Niveau audio lissé (0…1) pour les anneaux et la forme d'onde.
    private(set) var niveau: Float = 0
    /// Derniers niveaux, pour dessiner la forme d'onde.
    private(set) var historique: [Float] = Array(repeating: 0, count: 28)

    @ObservationIgnored private let moteur = MoteurDictee()

    var ecoute: Bool { etat == .ecoute }

    func basculer() async {
        if ecoute { arreter() } else { await demarrer() }
    }

    func demarrer() async {
        guard !ecoute else { return }
        transcription = ""
        guard await MoteurDictee.demanderAutorisations() else {
            etat = .refuse("Autorisez le micro et la reconnaissance vocale dans Réglages › Endry.")
            return
        }
        do {
            try moteur.demarrer(
                surTexte: { [weak self] texte, fini in
                    Task { @MainActor in
                        guard let self else { return }
                        self.transcription = texte
                        if fini { self.arreter() }
                    }
                },
                surNiveau: { [weak self] valeur in
                    Task { @MainActor in
                        guard let self else { return }
                        self.niveau = self.niveau * 0.6 + valeur * 0.4
                        self.historique.removeFirst()
                        self.historique.append(self.niveau)
                    }
                }
            )
            etat = .ecoute
        } catch {
            etat = .indisponible("La dictée n’est pas disponible pour le moment.")
        }
    }

    func arreter() {
        moteur.arreter()
        if ecoute { etat = .repos }
        niveau = 0
        historique = Array(repeating: 0, count: historique.count)
    }
}

/// Partie non isolée : AVAudioEngine + SFSpeechRecognizer. Les rappels arrivent sur des files audio.
nonisolated final class MoteurDictee: @unchecked Sendable {
    private let verrou = NSLock()
    private let moteurAudio = AVAudioEngine()
    private var requete: SFSpeechAudioBufferRecognitionRequest?
    private var tache: SFSpeechRecognitionTask?
    private let reconnaisseur = SFSpeechRecognizer(locale: Locale(identifier: "fr-CH")) ?? SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))

    static func demanderAutorisations() async -> Bool {
        let parole = await withCheckedContinuation { (suite: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { statut in
                suite.resume(returning: statut == .authorized)
            }
        }
        guard parole else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// `conversation` : micro et haut-parleur partagés avec la synthèse vocale (assistant local).
    func demarrer(conversation: Bool = false, surTexte: @escaping @Sendable (String, Bool) -> Void, surNiveau: @escaping @Sendable (Float) -> Void) throws {
        verrou.lock()
        defer { verrou.unlock() }
        guard let reconnaisseur, reconnaisseur.isAvailable else { throw ErreurDictee.indisponible }

        tache?.cancel()
        tache = nil

        let session = AVAudioSession.sharedInstance()
        if conversation {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
        } else {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        }
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let requete = SFSpeechAudioBufferRecognitionRequest()
        requete.shouldReportPartialResults = true
        requete.addsPunctuation = true
        requete.taskHint = .dictation
        // Vocabulaire métier : marques, pièces, lieux romands.
        requete.contextualStrings = VocabulaireMetier.termes
        if reconnaisseur.supportsOnDeviceRecognition {
            requete.requiresOnDeviceRecognition = true
        }
        self.requete = requete

        let entree = moteurAudio.inputNode
        let format = entree.outputFormat(forBus: 0)
        entree.removeTap(onBus: 0)
        nonisolated(unsafe) let requeteAudio = requete
        entree.installTap(onBus: 0, bufferSize: 1024, format: format) { tampon, _ in
            requeteAudio.append(tampon)
            surNiveau(Self.niveau(de: tampon))
        }
        moteurAudio.prepare()
        try moteurAudio.start()

        tache = reconnaisseur.recognitionTask(with: requete) { resultat, erreur in
            if let resultat {
                surTexte(resultat.bestTranscription.formattedString, resultat.isFinal)
            } else if erreur != nil {
                surTexte("", true)
            }
        }
    }

    func arreter(garderSession: Bool = false) {
        verrou.lock()
        defer { verrou.unlock() }
        if moteurAudio.isRunning {
            moteurAudio.stop()
            moteurAudio.inputNode.removeTap(onBus: 0)
        }
        requete?.endAudio()
        requete = nil
        tache?.finish()
        tache = nil
        if !garderSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Niveau RMS normalisé 0…1.
    private static func niveau(de tampon: AVAudioPCMBuffer) -> Float {
        guard let canal = tampon.floatChannelData?[0] else { return 0 }
        let n = Int(tampon.frameLength)
        guard n > 0 else { return 0 }
        var somme: Float = 0
        for i in 0..<n { somme += canal[i] * canal[i] }
        let rms = sqrt(somme / Float(n))
        let db = 20 * log10(max(rms, 0.000_01))
        return min(max((db + 50) / 45, 0), 1)
    }

    enum ErreurDictee: Error { case indisponible }
}
