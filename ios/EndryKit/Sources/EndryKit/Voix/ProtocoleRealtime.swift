import Foundation

/// Événements serveur utiles de l'API Realtime (parole-à-parole), décodés de façon tolérante.
public enum EvenementRealtime: Equatable, Sendable {
    case sessionPrete
    /// Le patron commence à parler : on coupe la voix de l'assistant (barge-in).
    case paroleDebut
    case paroleFin
    /// Transcription de la voix du patron (provisoire puis finale).
    case transcriptionPatron(texte: String, finale: Bool)
    /// Audio PCM 16 bits 24 kHz de l'assistant.
    case audio(Data, itemId: String?)
    /// Texte de ce que dit l'assistant.
    case transcriptionAssistant(texte: String, finale: Bool)
    /// L'assistant veut appeler un outil.
    case appelOutil(callId: String, nom: String, arguments: String)
    case reponseTerminee
    case erreur(String)
    case autre(String)

    public static func lire(_ data: Data) -> EvenementRealtime {
        guard let objet = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = objet["type"] as? String else { return .autre("illisible") }
        switch type {
        case "session.created", "session.updated":
            return .sessionPrete
        case "input_audio_buffer.speech_started":
            return .paroleDebut
        case "input_audio_buffer.speech_stopped":
            return .paroleFin
        case "conversation.item.input_audio_transcription.delta":
            return .transcriptionPatron(texte: objet["delta"] as? String ?? "", finale: false)
        case "conversation.item.input_audio_transcription.completed":
            return .transcriptionPatron(texte: objet["transcript"] as? String ?? "", finale: true)
        case "response.output_audio.delta", "response.audio.delta":
            guard let b64 = objet["delta"] as? String, let pcm = Data(base64Encoded: b64) else { return .autre(type) }
            return .audio(pcm, itemId: objet["item_id"] as? String)
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            return .transcriptionAssistant(texte: objet["delta"] as? String ?? "", finale: false)
        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            return .transcriptionAssistant(texte: objet["transcript"] as? String ?? "", finale: true)
        case "response.function_call_arguments.done":
            return .appelOutil(callId: objet["call_id"] as? String ?? "", nom: objet["name"] as? String ?? "",
                               arguments: objet["arguments"] as? String ?? "{}")
        case "response.done":
            return .reponseTerminee
        case "error":
            let detail = (objet["error"] as? [String: Any])?["message"] as? String
            return .erreur(detail ?? "Erreur de la session vocale.")
        default:
            return .autre(type)
        }
    }
}

/// Messages envoyés à l'API Realtime.
public enum CommandeRealtime {
    public static let url = "wss://api.openai.com/v1/realtime"

    /// Configuration de session : instructions, voix, outils du PC et vocabulaire métier.
    public static func configuration(session: SessionVoix, vocabulaire: [String]) -> Data {
        var outils: [[String: Any]] = []
        for outil in session.outils {
            var o: [String: Any] = ["type": "function", "name": outil.nom, "description": outil.description]
            if let p = outil.parametres, let d = p.data(using: .utf8), let schema = try? JSONSerialization.jsonObject(with: d) {
                o["parameters"] = schema
            } else {
                o["parameters"] = ["type": "object", "properties": [String: Any]()]
            }
            outils.append(o)
        }
        let consignes = [session.instructions ?? "", "Vocabulaire métier (orthographe exacte) : \(vocabulaire.joined(separator: ", ")).",
                         "Ne valide jamais seul un envoi à un tiers : utilise proposer_decision et attends le geste du patron."]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        var audio: [String: Any] = [
            "input": [
                "format": ["type": "audio/pcm", "rate": 24_000],
                "turn_detection": ["type": "semantic_vad", "create_response": true, "interrupt_response": true],
                "transcription": ["model": "gpt-4o-mini-transcribe", "language": "fr", "prompt": vocabulaire.joined(separator: ", ")],
            ],
            "output": ["format": ["type": "audio/pcm", "rate": 24_000]],
        ]
        if let voix = session.voix, var sortie = audio["output"] as? [String: Any] {
            sortie["voice"] = voix
            audio["output"] = sortie
        }
        var s: [String: Any] = ["type": "realtime", "instructions": consignes, "audio": audio, "tools": outils, "tool_choice": "auto"]
        if let modele = session.modele { s["model"] = modele }
        return json(["type": "session.update", "session": s])
    }

    public static func audio(_ pcm: Data) -> Data {
        json(["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()])
    }

    public static func resultatOutil(callId: String, sortie: String) -> Data {
        json(["type": "conversation.item.create", "item": ["type": "function_call_output", "call_id": callId, "output": sortie]])
    }

    public static let creerReponse = json(["type": "response.create"])
    public static let annulerReponse = json(["type": "response.cancel"])

    /// Coupe la fin non jouée de la réponse interrompue (barge-in).
    public static func tronquer(itemId: String, jouéMs: Int) -> Data {
        json(["type": "conversation.item.truncate", "item_id": itemId, "content_index": 0, "audio_end_ms": max(0, jouéMs)])
    }

    static func json(_ objet: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: objet, options: [.sortedKeys])) ?? Data()
    }
}

/// Vocabulaire métier injecté dans la reconnaissance (temps réel et locale).
public enum VocabulaireMetier {
    public static let termes: [String] = [
        "SN 592000", "Mapress", "Sanipex", "Geberit", "Buderus", "Meier Tobler", "Debrunner Acifer", "Hoval", "Viessmann",
        "boiler", "nourrice", "vase d’expansion", "chauffage au sol", "régie", "débouchage", "TVA", "Bexio", "Zoho",
        "Bussy", "Estavayer", "Epalinges", "Neuchâtel", "Moudon", "Payerne", "Romont", "Le Mont-sur-Lausanne",
    ]
}
