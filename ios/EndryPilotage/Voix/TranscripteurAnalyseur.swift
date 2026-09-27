import AVFoundation
import EndryKit
import Foundation
import Speech

/// Transcription en direct pour l'assistant local.
///
/// iOS 26 : `SpeechAnalyzer` + `SpeechTranscriber` (sur l'appareil, résultats provisoires).
/// Avant, ou si la langue n'est pas installable : `SFSpeechRecognizer` fr-CH sur l'appareil
/// (`MoteurDictee`), avec le vocabulaire métier en `contextualStrings`.
nonisolated protocol Transcripteur: AnyObject, Sendable {
    /// `surTexte(definitif, provisoire)` ; `surNiveau` : niveau du micro 0…1.
    func demarrer(surTexte: @escaping @Sendable (String, String) -> Void, surNiveau: @escaping @Sendable (Float) -> Void) async throws
    func arreter()
}

enum FabriqueTranscripteur {
    static func meilleur() async -> any Transcripteur {
        if #available(iOS 26.0, *), await TranscripteurAnalyseur.disponible() {
            return TranscripteurAnalyseur()
        }
        return TranscripteurClassique()
    }
}

/// Repli : reconnaissance classique fr-CH, sur l'appareil quand c'est possible.
nonisolated final class TranscripteurClassique: Transcripteur, @unchecked Sendable {
    private let moteur = MoteurDictee()

    func demarrer(surTexte: @escaping @Sendable (String, String) -> Void, surNiveau: @escaping @Sendable (Float) -> Void) async throws {
        try moteur.demarrer(conversation: true, surTexte: { texte, _ in surTexte("", texte) }, surNiveau: surNiveau)
    }

    func arreter() {
        moteur.arreter(garderSession: true)
    }
}

@available(iOS 26.0, *)
nonisolated final class TranscripteurAnalyseur: Transcripteur, @unchecked Sendable {
    private let verrou = NSLock()
    private let moteurAudio = AVAudioEngine()
    private var analyseur: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var lecture: Task<Void, Never>?
    private var convertisseur: AVAudioConverter?

    static func disponible() async -> Bool {
        guard SpeechTranscriber.isAvailable else { return false }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "fr-CH")) != nil
    }

    func demarrer(surTexte: @escaping @Sendable (String, String) -> Void, surNiveau: @escaping @Sendable (Float) -> Void) async throws {
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "fr-CH")) ?? Locale(identifier: "fr-FR")
        let transcripteur = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcripteur]) {
            try await installation.downloadAndInstall()
        }
        let analyseur = SpeechAnalyzer(modules: [transcripteur])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcripteur]) else {
            throw ErreurVoix.indisponible
        }
        let (flux, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let entree = moteurAudio.inputNode
        let formatMicro = entree.outputFormat(forBus: 0)
        let convertisseur = AVAudioConverter(from: formatMicro, to: format)
        verrou.lock()
        self.analyseur = analyseur
        self.continuation = continuation
        self.convertisseur = convertisseur
        verrou.unlock()

        entree.removeTap(onBus: 0)
        entree.installTap(onBus: 0, bufferSize: 2_048, format: formatMicro) { [weak self] tampon, _ in
            guard let self else { return }
            surNiveau(CanalAudioTempsReel.niveau(de: tampon))
            if let converti = self.convertir(tampon) {
                continuation.yield(AnalyzerInput(buffer: converti))
            }
        }
        moteurAudio.prepare()
        try moteurAudio.start()
        try await analyseur.start(inputSequence: flux)

        lecture = Task {
            var definitif = ""
            do {
                for try await resultat in transcripteur.results {
                    let texte = String(resultat.text.characters)
                    if resultat.isFinal {
                        definitif += texte
                        surTexte(definitif, "")
                    } else {
                        surTexte(definitif, texte)
                    }
                }
            } catch {
                // Fin de l'analyse : rien à signaler, le moteur local conclut le tour.
            }
        }
    }

    func arreter() {
        verrou.lock()
        let continuation = self.continuation
        let analyseur = self.analyseur
        self.continuation = nil
        self.analyseur = nil
        verrou.unlock()
        if moteurAudio.isRunning {
            moteurAudio.inputNode.removeTap(onBus: 0)
            moteurAudio.stop()
        }
        continuation?.finish()
        lecture?.cancel()
        if let analyseur {
            Task { await analyseur.cancelAndFinishNow() }
        }
    }

    private func convertir(_ tampon: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        verrou.lock()
        let convertisseur = self.convertisseur
        verrou.unlock()
        guard let convertisseur else { return nil }
        if convertisseur.inputFormat == convertisseur.outputFormat { return tampon }
        let ratio = convertisseur.outputFormat.sampleRate / tampon.format.sampleRate
        let capacite = AVAudioFrameCount(Double(tampon.frameLength) * ratio) + 64
        guard let sortie = AVAudioPCMBuffer(pcmFormat: convertisseur.outputFormat, frameCapacity: capacite) else { return nil }
        let fourni = Drapeau()
        nonisolated(unsafe) let source = tampon
        var erreur: NSError?
        _ = convertisseur.convert(to: sortie, error: &erreur) { _, statut in
            if fourni.leve {
                statut.pointee = .noDataNow
                return nil
            }
            fourni.leve = true
            statut.pointee = .haveData
            return source
        }
        return erreur == nil && sortie.frameLength > 0 ? sortie : nil
    }
}
