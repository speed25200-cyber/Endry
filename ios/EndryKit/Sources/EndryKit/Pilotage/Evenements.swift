import Foundation

/// Sujet d'une mise à jour poussée par le PC (`GET /evenements`, v1.1).
public enum SujetMaj: String, Sendable, CaseIterable {
    case decisions, chantiers, argent, saisies
    /// v1.2 : état et journal des agents du bureau.
    case agents
    /// v1.4 : compte rendu d'un geste (`GET /suivi`).
    case suivi
}

/// Événement Server-Sent Events complet.
public struct EvenementSSE: Equatable, Sendable {
    public var nom: String
    public var donnees: String

    public init(nom: String, donnees: String) {
        self.nom = nom
        self.donnees = donnees
    }

    /// `event: maj` + `data: {"quoi": "decisions"}` ; v1.2 : `agent`, `journal`, `reponse` → agents.
    /// Tout autre événement est ignoré.
    public var sujet: SujetMaj? {
        if ["agent", "journal", "reponse"].contains(nom) { return .agents }
        guard nom == "maj",
              let objet = (try? JSONSerialization.jsonObject(with: Data(donnees.utf8))) as? [String: Any],
              let quoi = objet["quoi"] as? String else { return nil }
        return SujetMaj(rawValue: quoi)
    }

    /// `event: reponse` (v1.6) : la réponse à une question est prête. `data` porte au moins `question_id`,
    /// et parfois la réponse entière (v1.2 / v1.8) : l'app l'affiche alors sans même relire `GET /questions/{id}`.
    public var reponsePrete: (questionId: String, reponse: ReponseAgent?)? {
        guard nom == "reponse", let data = donnees.data(using: .utf8),
              let lue = try? JSONDecoder().decode(ReponseAgent.self, from: data),
              let id = lue.questionId, !id.isEmpty else { return nil }
        // Réponse complète seulement si le texte (ou l'erreur) est là ; sinon, simple signal.
        let complete = (lue.statut == .repondu && lue.reponse != nil) || (lue.statut == .erreur && lue.message != nil)
        return (id, complete ? lue : nil)
    }

    /// `event: reponse_partielle` (v1.8, proposé) : `{question_id, texte}`, texte cumulé de la réponse en train
    /// de s'écrire sur le PC. L'app l'affiche mot à mot, comme une session Claude ouverte.
    public var reponsePartielle: (questionId: String, texte: String)? {
        guard nom == "reponse_partielle",
              let objet = (try? JSONSerialization.jsonObject(with: Data(donnees.utf8))) as? [String: Any],
              let id = (objet["question_id"] as? String) ?? (objet["question_id"] as? Int).map(String.init),
              let texte = objet["texte"] as? String, !id.isEmpty else { return nil }
        return (id, texte)
    }
}

/// Lecture ligne à ligne d'un flux SSE (format du W3C : `event:`, `data:`, commentaires `:`, ligne vide = fin).
public struct AnalyseurSSE: Sendable {
    private var nom = ""
    private var donnees: [String] = []

    public init() {}

    public mutating func lire(_ ligneBrute: String) -> EvenementSSE? {
        let ligne = ligneBrute.hasSuffix("\r") ? String(ligneBrute.dropLast()) : ligneBrute
        if ligne.isEmpty {
            defer {
                nom = ""
                donnees = []
            }
            guard !donnees.isEmpty else { return nil }
            return EvenementSSE(nom: nom.isEmpty ? "message" : nom, donnees: donnees.joined(separator: "\n"))
        }
        if ligne.hasPrefix(":") { return nil }
        let champ: Substring
        var valeur: Substring
        if let deuxPoints = ligne.firstIndex(of: ":") {
            champ = ligne[..<deuxPoints]
            valeur = ligne[ligne.index(after: deuxPoints)...]
            if valeur.hasPrefix(" ") { valeur = valeur.dropFirst() }
        } else {
            champ = Substring(ligne)
            valeur = ""
        }
        switch champ {
        case "event": nom = String(valeur)
        case "data": donnees.append(String(valeur))
        default: break
        }
        return nil
    }
}

/// Catégories de notifications envoyées par le PC (v1.1).
public enum CategorieNotification: String, Sendable, CaseIterable {
    /// Décision : action « Voir » seulement (le « Oui » se fait en glissant, dans l'app).
    case decision = "DECISION"
    /// Décision qui envoie quelque chose à un tiers : « Voir » seulement (le geste se fait dans l'app).
    case decisionEnvoi = "DECISION_ENVOI"
    case saisieTraitee = "SAISIE_TRAITEE"
    case info = "INFO"

    /// « Oui » depuis une notification : jamais (règle du 28.09.2026 : tout « Oui » se fait en glissant).
    public var permetOui: Bool { false }
}

/// Charge utile APNs lue de façon tolérante.
public struct ChargeNotification: Equatable, Sendable {
    public var categorie: CategorieNotification
    public var reference: String?
    public var fil: String?
    /// Saisie traitée (v4) : identifiant envoyé par le PC.
    public var saisieId: String?

    public init(categorie: CategorieNotification, reference: String?, fil: String?, saisieId: String? = nil) {
        self.categorie = categorie
        self.reference = reference
        self.fil = fil
        self.saisieId = saisieId
    }

    public init(userInfo: [AnyHashable: Any]) {
        let aps = userInfo["aps"] as? [String: Any] ?? [:]
        let brute = (aps["category"] as? String) ?? (userInfo["category"] as? String) ?? ""
        categorie = CategorieNotification(rawValue: brute) ?? .info
        let ref = (userInfo["reference"] as? String)?.trimmingCharacters(in: .whitespaces)
        reference = (ref?.isEmpty ?? true) ? nil : ref
        fil = aps["thread-id"] as? String
        let saisie = (userInfo["saisie_id"] as? String) ?? (userInfo["saisie_id"] as? Int).map(String.init)
        saisieId = saisie.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }

    /// Saisie traitée sans décision liée : ouvrir l'historique des saisies (pas une carte).
    public var ouvreHistoriqueSaisies: Bool {
        guard categorie == .saisieTraitee else { return false }
        guard let reference else { return true }
        return !(reference.hasPrefix("V-") || reference.hasPrefix("Q-"))
    }

    /// Action « Oui » autorisée pour cette notification : catégorie DECISION et référence de validation (V-…).
    public var ouiAutorise: Bool {
        categorie.permetOui && (reference?.hasPrefix("V-") ?? false)
    }
}
