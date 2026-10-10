import Foundation

// Modèles de base du Kit (issus du skill app-pilotage-entreprise). Décodage tolérant : voir DecodageTolerant.swift.

/// Étapes du pipeline des dossiers (à adapter au métier : 7 étapes au plus, lisibles sur un iPhone SE).
public enum EtapeDossier: String, CaseIterable, Identifiable, Sendable, Codable {
    case demande, offre, acceptee, planifiee, realisee, facturee, payee

    public var id: String { rawValue }
    public var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public var libelle: String {
        switch self {
        case .demande: "Demande"
        case .offre: "Offre"
        case .acceptee: "Acceptée"
        case .planifiee: "Planifiée"
        case .realisee: "Réalisée"
        case .facturee: "Facturée"
        case .payee: "Payée"
        }
    }

    /// Libellé court pour l'entonnoir (une colonne par étape).
    public var abrege: String {
        switch self {
        case .demande: "Dem."
        case .offre: "Offre"
        case .acceptee: "Acc."
        case .planifiee: "Plan."
        case .realisee: "Réal."
        case .facturee: "Fact."
        case .payee: "Payé"
        }
    }

    /// Lecture tolérante (« Planifié », « planifiee », « PLANIFIEE »…).
    public init?(texte: String) {
        let t = texte.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
        guard let etape = Self.allCases.first(where: { t.hasPrefix(String($0.rawValue.dropLast(1))) }) else { return nil }
        self = etape
    }
}

/// Décision préparée par l'agent du bureau. `envoiTiers` : le « Oui » fait partir quelque chose chez un tiers
/// → glissement obligatoire, jamais depuis une notification.
public struct Carte: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var type: String
    public var titre: String
    public var resume: String
    public var envoiTiers: Bool
    public var modifiable: String?
    public var pieces: [Piece]

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        id = c.texte("id") ?? c.texte("reference") ?? UUID().uuidString
        type = c.texte("type", defaut: "validation")
        titre = c.texte("titre", defaut: "Décision")
        resume = c.texte("resume", defaut: "")
        envoiTiers = c.booleen("envoi_tiers") ?? false
        modifiable = c.texte("modifiable")
        pieces = c.liste("pieces", Piece.self)
    }
}

/// Réponse d'un agent à une question (`GET /questions/{id}` ou `event: reponse`).
public struct ReponseAgent: Decodable, Sendable, Hashable {
    public enum Statut: String, Sendable { case enCours = "en_cours", repondu, erreur }

    public var statut: Statut
    public var questionId: String
    public var agent: String?
    /// Texte affiché (liens vers des documents remplacés par leur seul libellé).
    public var reponse: String?
    public var message: String?
    /// Documents joints : champs `documents` / `pieces` / `fichiers`, plus les liens trouvés dans le texte.
    public var documents: [Piece]

    public init(statut: Statut, questionId: String, agent: String? = nil, reponse: String? = nil, documents: [Piece] = []) {
        self.statut = statut
        self.questionId = questionId
        self.agent = agent
        self.reponse = reponse
        self.documents = documents
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        statut = Statut(rawValue: c.texte("statut", defaut: "en_cours")) ?? .enCours
        questionId = c.texte("question_id", defaut: "")
        agent = c.texte("agent")
        message = c.texte("message")
        var joints = c.liste("documents", Piece.self) + c.liste("pieces", Piece.self) + c.liste("fichiers", Piece.self)
        if let brut = c.texte("reponse") {
            let (texte, liens) = Piece.extraire(du: brut)
            reponse = texte
            joints += liens
        }
        var vus = Set<String>()
        documents = joints.filter { !$0.url.isEmpty && vus.insert($0.url).inserted }
    }
}

public struct Piece: Codable, Sendable, Hashable, Identifiable {
    public var nom: String
    public var url: String

    public var id: String { url }

    public init(nom: String, url: String) {
        self.nom = nom
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        url = c.texte("url") ?? c.texte("pdf") ?? ""
        nom = c.texte("nom") ?? URL(string: url)?.lastPathComponent ?? "Document"
    }

    public var estPDF: Bool {
        nom.lowercased().hasSuffix(".pdf") || url.contains("/app/doc/") || url.lowercased().hasSuffix(".pdf")
    }

    private enum Cles: String, CodingKey { case nom, url }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Cles.self)
        try c.encode(nom, forKey: .nom)
        try c.encode(url, forKey: .url)
    }

    /// Extension du fichier (« pdf », « xlsx »), d'après le nom puis l'adresse ; `pdf` pour un document du bureau.
    public var extensionFichier: String {
        let n = (nom as NSString).pathExtension.lowercased()
        if !n.isEmpty { return n }
        let u = ((URL(string: url)?.path ?? url) as NSString).pathExtension.lowercased()
        if !u.isEmpty { return u }
        return url.contains("/app/doc/") ? "pdf" : ""
    }

    /// Libellé du type (« PDF », « Excel », « Word »).
    public var libelleType: String {
        switch extensionFichier {
        case "pdf": "PDF"
        case "xlsx", "xls", "csv": "Excel"
        case "docx", "doc": "Word"
        case "png", "jpg", "jpeg", "heic": "Image"
        case "": "Document"
        default: extensionFichier.uppercased()
        }
    }

    static let extensionsDocument: Set<String> = ["pdf", "xlsx", "xls", "csv", "docx", "doc", "pptx", "png", "jpg", "jpeg", "heic", "txt", "zip"]

    /// Liens vers des documents dans une réponse en Markdown (`[Offre OF-00037.pdf](/app/doc/offre/OF-00037)`) :
    /// les documents trouvés, et le texte où chaque lien est remplacé par son seul libellé.
    public static func extraire(du texte: String) -> (texte: String, pieces: [Piece]) {
        guard texte.contains("](") else { return (texte, []) }
        var pieces: [Piece] = []
        var sortie = ""
        var reste = Substring(texte)
        while let ouvrant = reste.firstIndex(of: "[") {
            sortie += reste[..<ouvrant]
            let apres = reste[reste.index(after: ouvrant)...]
            guard let fermant = apres.firstIndex(of: "]"),
                  apres[fermant...].hasPrefix("]("),
                  let finLien = apres[apres.index(fermant, offsetBy: 2)...].firstIndex(of: ")") else {
                sortie += "["
                reste = apres
                continue
            }
            let libelle = String(apres[..<fermant])
            let adresse = String(apres[apres.index(fermant, offsetBy: 2)..<finLien]).trimmingCharacters(in: .whitespaces)
            let piece = Piece(nom: libelle.isEmpty ? (URL(string: adresse)?.lastPathComponent ?? "Document") : libelle, url: adresse)
            let estDocument = adresse.contains("/app/doc/") || adresse.contains("/documents/")
                || extensionsDocument.contains(piece.extensionFichier) && !adresse.lowercased().hasPrefix("mailto:")
            if estDocument {
                if !pieces.contains(where: { $0.url == adresse }) { pieces.append(piece) }
                sortie += libelle
            } else {
                sortie += reste[ouvrant...finLien]
            }
            reste = apres[apres.index(after: finLien)...]
        }
        sortie += reste
        return (sortie, pieces)
    }
}
