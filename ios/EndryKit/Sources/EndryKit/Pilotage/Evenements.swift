import Foundation

/// Sujet d'une mise à jour poussée par le PC (`GET /evenements`, v1.1).
public enum SujetMaj: String, Sendable, CaseIterable {
    case decisions, chantiers, argent, saisies
}

/// Événement Server-Sent Events complet.
public struct EvenementSSE: Equatable, Sendable {
    public var nom: String
    public var donnees: String

    public init(nom: String, donnees: String) {
        self.nom = nom
        self.donnees = donnees
    }

    /// `event: maj` + `data: {"quoi": "decisions"}` ; tout autre événement est ignoré.
    public var sujet: SujetMaj? {
        guard nom == "maj",
              let objet = (try? JSONSerialization.jsonObject(with: Data(donnees.utf8))) as? [String: Any],
              let quoi = objet["quoi"] as? String else { return nil }
        return SujetMaj(rawValue: quoi)
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
    /// Décision sans envoi à un tiers : actions « Voir » et « Oui ».
    case decision = "DECISION"
    /// Décision qui envoie quelque chose à un tiers : « Voir » seulement (le geste se fait dans l'app).
    case decisionEnvoi = "DECISION_ENVOI"
    case saisieTraitee = "SAISIE_TRAITEE"
    case info = "INFO"

    /// « Oui » depuis la notification : seulement si rien ne part chez un tiers.
    public var permetOui: Bool { self == .decision }
}

/// Charge utile APNs lue de façon tolérante.
public struct ChargeNotification: Equatable, Sendable {
    public var categorie: CategorieNotification
    public var reference: String?
    public var fil: String?

    public init(categorie: CategorieNotification, reference: String?, fil: String?) {
        self.categorie = categorie
        self.reference = reference
        self.fil = fil
    }

    public init(userInfo: [AnyHashable: Any]) {
        let aps = userInfo["aps"] as? [String: Any] ?? [:]
        let brute = (aps["category"] as? String) ?? (userInfo["category"] as? String) ?? ""
        categorie = CategorieNotification(rawValue: brute) ?? .info
        let ref = (userInfo["reference"] as? String)?.trimmingCharacters(in: .whitespaces)
        reference = (ref?.isEmpty ?? true) ? nil : ref
        fil = aps["thread-id"] as? String
    }

    /// Action « Oui » autorisée pour cette notification : catégorie DECISION et référence de validation (V-…).
    public var ouiAutorise: Bool {
        categorie.permetOui && (reference?.hasPrefix("V-") ?? false)
    }
}
