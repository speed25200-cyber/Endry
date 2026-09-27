import AVFoundation
import EndryKit
import Foundation
import Speech

/// Transcription en direct pour l'assistant local.
///
/// iOS 26 et suivants : `SpeechAnalyzer` + `DictationTranscriber` (le moteur de la dictée d'Apple, sur l'appareil,
/// ponctué), orienté par le vocabulaire du moment (`AnalysisContext.contextualStrings` : termes du métier, clients,
/// chantiers, fournisseurs). Si la dictée française manque : `SpeechTranscriber`, qui ignore le vocabulaire.
/// Avant iOS 26 : `SFSpeechRecognizer` fr-CH sur l'appareil (`MoteurDictee`), vocabulaire en `contextualStrings`.
nonisolated protocol Transcripteur: AnyObject, Sendable {
    /// `surTexte(definitif, provisoire)` ; `surNiveau` : niveau du micro 0…1.
    func demarrer(surTexte: @escaping @Sendable (String, String) -> Void, surNiveau: @escaping @Sendable (Float) -> Void) async throws
    func arreter()
}

/// Oreille : transcrit en direct un micro tenu par un autre moteur (temps réel), pour afficher les mots
/// pendant que le patron parle — le moteur temps réel ne livre sa transcription qu'en fin de phrase.
nonisolated protocol Oreille: AnyObject, Sendable {
    func nourrir(_ tampon: AVAudioPCMBuffer)
    /// Nouveau tour de parole : on repart d'une page blanche.
    func reinitialiser()
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
nonisolated final class TranscripteurAnalyseur: Transcripteur, Oreille, @unchecked Sendable {
    private let verrou = NSLock()
    /// Texte confirmé du tour en cours (les segments définitifs, séparés par une espace).
    private var definitif = ""
    private var formatAnalyse: AVAudioFormat?
    private let moteurAudio = AVAudioEngine()
    private var analyseur: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var lecture: Task<Void, Never>?
    private var convertisseur: AVAudioConverter?

    static func disponible() async -> Bool {
        if await localeDictee() != nil { return true }
        guard SpeechTranscriber.isAvailable else { return false }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "fr-CH")) != nil
    }

    /// Français de Suisse, sinon de France (même reconnaissance).
    private static func localeDictee() async -> Locale? {
        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "fr-CH")) { return locale }
        return await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "fr-FR"))
    }

    /// Module de transcription et lecture de ses résultats (`texte`, `definitif`).
    private static func module(surResultat: @escaping @Sendable (String, Bool) -> Void) async -> (any SpeechModule, Task<Void, Never>) {
        if let locale = await localeDictee() {
            let dictee = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation],
                                              reportingOptions: [.volatileResults], attributeOptions: [])
            let lecture = Task {
                do {
                    for try await resultat in dictee.results { surResultat(String(resultat.text.characters), resultat.isFinal) }
                } catch {
                    // Fin de l'analyse : rien à signaler, le moteur conclut le tour.
                }
            }
            return (dictee, lecture)
        }
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "fr-CH")) ?? Locale(identifier: "fr-FR")
        let transcripteur = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        let lecture = Task {
            do {
                for try await resultat in transcripteur.results { surResultat(String(resultat.text.characters), resultat.isFinal) }
            } catch {
                // Fin de l'analyse.
            }
        }
        return (transcripteur, lecture)
    }

    /// Prépare l'analyse (modèle fr-CH installé si besoin) et lance la lecture des résultats.
    private func preparer(surTexte: @escaping @Sendable (String, String) -> Void)
        async throws -> (SpeechAnalyzer, AVAudioFormat, AsyncStream<AnalyzerInput>, AsyncStream<AnalyzerInput>.Continuation) {
        verrou.withLock { definitif = "" }
        let (module, lecture) = await Self.module { [weak self] brut, estFinal in
            guard let self else { return }
            let texte = brut.trimmingCharacters(in: .whitespaces)
            if estFinal {
                let confirme = self.verrou.withLock {
                    self.definitif = [self.definitif, texte].filter { !$0.isEmpty }.joined(separator: " ")
                    return self.definitif
                }
                surTexte(confirme, "")
            } else {
                surTexte(self.verrou.withLock { self.definitif }, texte)
            }
        }
        self.lecture = lecture
        do {
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await installation.downloadAndInstall()
            }
        } catch {
            lecture.cancel()
            throw error
        }
        let analyseur = SpeechAnalyzer(modules: [module])
        // Vocabulaire du moment : 100 expressions au plus (limite d'Apple). Sans effet sur SpeechTranscriber.
        let contexte = AnalysisContext()
        contexte.contextualStrings[.general] = VocabulaireVocal.partage.termes
        try? await analyseur.setContext(contexte)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            lecture.cancel()
            throw ErreurVoix.indisponible
        }
        let (flux, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        return (analyseur, format, flux, continuation)
    }

    /// Mode oreille : l'audio vient d'un autre moteur (`nourrir`) ; la session audio n'est pas touchée.
    func demarrerSansMicro(surTexte: @escaping @Sendable (String, String) -> Void) async throws {
        let (analyseur, format, flux, continuation) = try await preparer(surTexte: surTexte)
        verrou.withLock {
            self.analyseur = analyseur
            self.continuation = continuation
            self.formatAnalyse = format
        }
        try await analyseur.start(inputSequence: flux)
    }

    func nourrir(_ tampon: AVAudioPCMBuffer) {
        let (continuation, pret) = verrou.withLock { () -> (AsyncStream<AnalyzerInput>.Continuation?, Bool) in
            if convertisseur == nil, let formatAnalyse {
                convertisseur = AVAudioConverter(from: tampon.format, to: formatAnalyse)
            }
            return (self.continuation, convertisseur != nil)
        }
        guard pret, let continuation, let converti = convertir(tampon) else { return }
        continuation.yield(AnalyzerInput(buffer: converti))
    }

    func reinitialiser() {
        verrou.withLock { definitif = "" }
    }

    func demarrer(surTexte: @escaping @Sendable (String, String) -> Void, surNiveau: @escaping @Sendable (Float) -> Void) async throws {
        let (analyseur, format, flux, continuation) = try await preparer(surTexte: surTexte)

        let session = AVAudioSession.sharedInstance()
        // Mode par défaut, pas « appel » : le traitement téléphonique (filtre, compression) dégrade la reconnaissance.
        // Endry ne parle pas pendant qu'il écoute : pas besoin d'annulation d'écho ici.
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let entree = moteurAudio.inputNode
        let formatMicro = entree.outputFormat(forBus: 0)
        let convertisseur = AVAudioConverter(from: formatMicro, to: format)
        verrou.withLock {
            self.analyseur = analyseur
            self.continuation = continuation
            self.convertisseur = convertisseur
        }

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
