import AVFoundation
import EndryKit
import Foundation

/// Moteur parole-à-parole : API Realtime (WebSocket), avec une session éphémère obtenue du PC.
///
/// - L'app ne détient jamais de clé : `POST /app/api/v1/voix/session` renvoie un `client_secret` de courte durée.
/// - Audio : `AVAudioSession` en `.voiceChat` (annulation d'écho, haut-parleur, AirPods, CarPlay),
///   PCM 16 bits 24 kHz dans les deux sens.
/// - Barge-in : dès que le patron parle, la voix de l'assistant s'arrête net et la réponse est tronquée
///   à ce qui a réellement été entendu.
/// - Outils : exécutés avec le jeton de l'appareil ; `proposer_decision` n'affiche qu'une carte
///   qui attend le geste du patron.
@MainActor
final class MoteurTempsReel: MoteurVoix {
    let nom = "Temps réel"

    private let session: SessionVoix
    private let executeur: ExecuteurOutils
    private var socket: URLSessionWebSocketTask?
    private var audio: CanalAudioTempsReel?
    private var reception: Task<Void, Never>?
    private var surEvenement: (@MainActor (EvenementVoix) -> Void)?

    private var patronDefinitif = ""
    private var patronProvisoire = ""
    private var texteAssistant = ""
    private var itemEnCours: String?
    private var phase: PhaseVoix = .preparation
    private var reponseTerminee = true

    init(session: SessionVoix, executeur: ExecuteurOutils) {
        self.session = session
        self.executeur = executeur
    }

    func demarrer(surEvenement: @escaping @MainActor (EvenementVoix) -> Void) async throws {
        guard session.disponible, let secret = session.clientSecret, !secret.isEmpty else { throw ErreurVoix.indisponible }
        guard await AVAudioApplication.requestRecordPermission() else { throw ErreurVoix.autorisationRefusee }
        self.surEvenement = surEvenement

        var composants = URLComponents(string: CommandeRealtime.url)
        composants?.queryItems = [URLQueryItem(name: "model", value: session.modele ?? "gpt-realtime")]
        guard let url = composants?.url else { throw ErreurVoix.connexion }
        var requete = URLRequest(url: url)
        requete.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: requete)
        self.socket = socket
        socket.resume()

        do {
            try await socket.send(.string(Self.texte(CommandeRealtime.configuration(session: session, vocabulaire: VocabulaireMetier.termes))))
            // Première réponse du serveur : la connexion est bien établie (sinon, repli sur le moteur local).
            let premier = try await socket.receive()
            traiter(Self.donnees(premier))
        } catch {
            socket.cancel(with: .goingAway, reason: nil)
            throw ErreurVoix.connexion
        }

        let canalReseau = socket
        let canal = CanalAudioTempsReel()
        canal.surVide = { [weak self] in
            Task { @MainActor in self?.lectureTerminee() }
        }
        try canal.demarrer(
            surMorceau: { pcm in
                canalReseau.send(.string(Self.texte(CommandeRealtime.audio(pcm)))) { _ in }
            },
            surNiveau: { [weak self] niveau in
                Task { @MainActor in self?.surEvenement?(.niveauMicro(niveau)) }
            }
        )
        audio = canal

        reception = Task { [weak self] in
            await self?.boucleReception(socket)
        }
        changerPhase(.ecoute)
    }

    func arreter() {
        reception?.cancel()
        reception = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        audio?.arreter()
        audio = nil
        surEvenement = nil
    }

    // MARK: - Réception

    private func boucleReception(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                traiter(Self.donnees(message))
            } catch {
                if !Task.isCancelled {
                    changerPhase(.erreur("La conversation s’est interrompue. Touchez la sphère pour reprendre."))
                }
                return
            }
        }
    }

    private func traiter(_ data: Data) {
        switch EvenementRealtime.lire(data) {
        case .sessionPrete, .autre:
            break
        case .paroleDebut:
            interrompreAssistant()
            patronDefinitif = ""
            patronProvisoire = ""
            texteAssistant = ""
            surEvenement?(.nouveauTour)
            changerPhase(.ecoute)
        case .paroleFin:
            changerPhase(.reflexion)
        case .transcriptionPatron(let texte, let finale):
            if finale {
                patronDefinitif = texte
                patronProvisoire = ""
            } else {
                patronProvisoire += texte
            }
            surEvenement?(.patron(definitif: patronDefinitif, provisoire: patronProvisoire))
        case .audio(let pcm, let itemId):
            if let itemId, itemId != itemEnCours {
                itemEnCours = itemId
                audio?.nouvelItem()
            }
            reponseTerminee = false
            let niveau = audio?.jouer(pcm) ?? 0
            changerPhase(.parole)
            surEvenement?(.niveauVoix(niveau))
        case .transcriptionAssistant(let texte, let finale):
            if finale { texteAssistant = texte } else { texteAssistant += texte }
            surEvenement?(.assistant(texteAssistant))
        case .appelOutil(let callId, let nom, let arguments):
            changerPhase(.reflexion)
            Task { await executer(callId: callId, nom: nom, arguments: arguments) }
        case .reponseTerminee:
            reponseTerminee = true
            if audio?.lectureEnCours != true, phase != .reflexion { changerPhase(.ecoute) }
        case .erreur:
            // Erreurs non bloquantes (réponse déjà annulée, troncature tardive) : la conversation continue.
            break
        }
    }

    private func executer(callId: String, nom: String, arguments: String) async {
        let resultat = await executeur.executer(nom: nom, arguments: arguments)
        envoyer(CommandeRealtime.resultatOutil(callId: callId, sortie: resultat.sortie))
        envoyer(CommandeRealtime.creerReponse)
        surEvenement?(.effet(resultat.effet))
    }

    func poser(_ question: String) async {
        interrompreAssistant()
        surEvenement?(.nouveauTour)
        surEvenement?(.patron(definitif: question, provisoire: ""))
        envoyer(CommandeRealtime.messageTexte(question))
        envoyer(CommandeRealtime.creerReponse)
        changerPhase(.reflexion)
    }

    func annoncer(question: String, reponse: String) async {
        envoyer(CommandeRealtime.messageTexte(
            "[Réponse de Claude, l’assistant du bureau sur le PC, à la question « \(question) »] \(reponse)\nTransmets-la fidèlement au patron, en commençant par « Claude répond »."))
        envoyer(CommandeRealtime.creerReponse)
    }

    func interrompre() {
        interrompreAssistant()
        changerPhase(.ecoute)
    }

    /// Barge-in : la voix s'arrête net, la réponse est tronquée à ce qui a été entendu.
    private func interrompreAssistant() {
        guard let audio, audio.lectureEnCours || !reponseTerminee else { return }
        let joueMs = audio.interrompre()
        if !reponseTerminee { envoyer(CommandeRealtime.annulerReponse) }
        if let itemEnCours { envoyer(CommandeRealtime.tronquer(itemId: itemEnCours, jouéMs: joueMs)) }
        itemEnCours = nil
        reponseTerminee = true
        surEvenement?(.niveauVoix(0))
    }

    private func lectureTerminee() {
        guard phase == .parole, reponseTerminee else { return }
        changerPhase(.ecoute)
    }

    private func changerPhase(_ nouvelle: PhaseVoix) {
        guard nouvelle != phase else { return }
        phase = nouvelle
        surEvenement?(.phase(nouvelle))
    }

    private func envoyer(_ data: Data) {
        socket?.send(.string(Self.texte(data))) { _ in }
    }

    nonisolated private static func texte(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func donnees(_ message: URLSessionWebSocketTask.Message) -> Data {
        switch message {
        case .string(let s): Data(s.utf8)
        case .data(let d): d
        @unknown default: Data()
        }
    }
}

/// Partie audio, hors du fil principal : micro → PCM16 24 kHz, et lecture de la voix de l'assistant.
nonisolated final class CanalAudioTempsReel: @unchecked Sendable {
    private let moteur = AVAudioEngine()
    private let lecteur = AVAudioPlayerNode()
    private let verrou = NSLock()
    private var convertisseur: AVAudioConverter?
    private var enAttente = 0
    private var framesJouees: AVAudioFramePosition = 0
    private var generation = 0
    var surVide: (@Sendable () -> Void)?

    static let frequence: Double = 24_000
    private let formatReseau = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: CanalAudioTempsReel.frequence, channels: 1, interleaved: true)
    private let formatLecture = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: CanalAudioTempsReel.frequence, channels: 1, interleaved: false)

    var lectureEnCours: Bool {
        verrou.lock()
        defer { verrou.unlock() }
        return enAttente > 0
    }

    func demarrer(surMorceau: @escaping @Sendable (Data) -> Void, surNiveau: @escaping @Sendable (Float) -> Void) throws {
        guard let formatReseau, let formatLecture else { throw ErreurVoix.indisponible }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let entree = moteur.inputNode
        // Annulation d'écho et réduction de bruit du système.
        try entree.setVoiceProcessingEnabled(true)

        moteur.attach(lecteur)
        moteur.connect(lecteur, to: moteur.mainMixerNode, format: formatLecture)

        let formatMicro = entree.outputFormat(forBus: 0)
        convertisseur = AVAudioConverter(from: formatMicro, to: formatReseau)
        entree.removeTap(onBus: 0)
        entree.installTap(onBus: 0, bufferSize: 2_400, format: formatMicro) { [weak self] tampon, _ in
            guard let self else { return }
            surNiveau(Self.niveau(de: tampon))
            if let pcm = self.convertir(tampon) { surMorceau(pcm) }
        }
        moteur.prepare()
        try moteur.start()
        lecteur.play()
    }

    func arreter() {
        verrou.lock()
        generation += 1
        enAttente = 0
        verrou.unlock()
        lecteur.stop()
        if moteur.isRunning {
            moteur.inputNode.removeTap(onBus: 0)
            moteur.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Joue un morceau PCM16 24 kHz ; renvoie son niveau (0…1) pour la sphère.
    func jouer(_ pcm: Data) -> Float {
        guard let formatLecture else { return 0 }
        let n = pcm.count / 2
        guard n > 0, let tampon = AVAudioPCMBuffer(pcmFormat: formatLecture, frameCapacity: AVAudioFrameCount(n)),
              let sortie = tampon.floatChannelData?[0] else { return 0 }
        tampon.frameLength = AVAudioFrameCount(n)
        var somme: Float = 0
        pcm.withUnsafeBytes { brut in
            let echantillons = brut.bindMemory(to: Int16.self)
            for i in 0..<n {
                let v = Float(Int16(littleEndian: echantillons[i])) / 32_768
                sortie[i] = v
                somme += v * v
            }
        }
        verrou.lock()
        enAttente += 1
        let gen = generation
        verrou.unlock()
        lecteur.scheduleBuffer(tampon) { [weak self] in
            self?.termine(frames: n, generation: gen)
        }
        if !lecteur.isPlaying { lecteur.play() }
        let rms = sqrt(somme / Float(n))
        return min(max((20 * log10(max(rms, 0.000_01)) + 45) / 40, 0), 1)
    }

    /// Nouvelle réponse : le compteur de lecture (pour la troncature) repart de zéro.
    func nouvelItem() {
        verrou.lock()
        framesJouees = 0
        verrou.unlock()
    }

    /// Coupe la lecture ; renvoie les millisecondes réellement jouées de la réponse en cours.
    func interrompre() -> Int {
        verrou.lock()
        let ms = Int(Double(framesJouees) / Self.frequence * 1_000)
        generation += 1
        enAttente = 0
        framesJouees = 0
        verrou.unlock()
        lecteur.stop()
        lecteur.play()
        return ms
    }

    private func termine(frames: Int, generation gen: Int) {
        verrou.lock()
        guard gen == generation else {
            verrou.unlock()
            return
        }
        enAttente = max(enAttente - 1, 0)
        framesJouees += AVAudioFramePosition(frames)
        let vide = enAttente == 0
        let rappel = surVide
        verrou.unlock()
        if vide { rappel?() }
    }

    private func convertir(_ tampon: AVAudioPCMBuffer) -> Data? {
        guard let convertisseur, let format = formatReseau else { return nil }
        let ratio = format.sampleRate / tampon.format.sampleRate
        let capacite = AVAudioFrameCount(Double(tampon.frameLength) * ratio) + 64
        guard let sortie = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacite) else { return nil }
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
        guard erreur == nil, sortie.frameLength > 0, let canal = sortie.int16ChannelData else { return nil }
        return Data(bytes: canal[0], count: Int(sortie.frameLength) * MemoryLayout<Int16>.size)
    }

    /// Niveau RMS normalisé 0…1.
    static func niveau(de tampon: AVAudioPCMBuffer) -> Float {
        guard let canal = tampon.floatChannelData?[0] else { return 0 }
        let n = Int(tampon.frameLength)
        guard n > 0 else { return 0 }
        var somme: Float = 0
        for i in 0..<n { somme += canal[i] * canal[i] }
        let rms = sqrt(somme / Float(n))
        return min(max((20 * log10(max(rms, 0.000_01)) + 50) / 45, 0), 1)
    }
}

/// Petit drapeau partagé avec le bloc du convertisseur audio.
nonisolated final class Drapeau: @unchecked Sendable {
    var leve = false
}
