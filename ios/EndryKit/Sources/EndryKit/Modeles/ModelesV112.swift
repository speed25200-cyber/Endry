import Foundation

/// Un e-mail reçu au bureau (`GET /mails` pour la liste, `GET /mails/{id}` pour le texte — contrat v1.12).
public struct MailRecu: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    /// Adresse de l'expéditeur.
    public var de: String
    public var deNom: String?
    public var objet: String
    /// Horodatage suisse `AAAA-MM-JJTHH:MM:SS`.
    public var recu: String?
    /// Catégorie donnée par l'assistant (`soumission`, `rendez_vous`…).
    public var categorie: String?
    /// Résumé de ce que l'assistant en a fait.
    public var resume: String?
    public var a: [String]
    public var cc: [String]
    /// Texte de l'e-mail : seulement dans le détail.
    public var contenu: String?
    /// Pièces jointes. `nil` : pas encore connues (elles arrivent avec le détail) ; vide : aucune.
    public var pieces: [Piece]?

    public init(id: String, de: String, deNom: String? = nil, objet: String, recu: String? = nil, categorie: String? = nil,
                resume: String? = nil, a: [String] = [], cc: [String] = [], contenu: String? = nil, pieces: [Piece]? = nil) {
        self.id = id
        self.de = de
        self.deNom = deNom
        self.objet = objet
        self.recu = recu
        self.categorie = categorie
        self.resume = resume
        self.a = a
        self.cc = cc
        self.contenu = contenu
        self.pieces = pieces
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        guard let id = c.texte("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "id manquant"))
        }
        self.id = id
        de = c.texte("de", defaut: "")
        deNom = c.texte("de_nom").flatMap { $0.isEmpty ? nil : $0 }
        objet = c.texte("objet", defaut: "(sans objet)")
        recu = c.texte("recu")
        categorie = c.texte("categorie").flatMap { $0.isEmpty ? nil : $0 }
        resume = c.texte("resume").flatMap { $0.isEmpty ? nil : $0 }
        a = c.textes("a")
        cc = c.textes("cc")
        contenu = c.texte("contenu")
        pieces = c.objet("pieces", [Piece].self)
    }

    /// Nom à afficher : celui de l'expéditeur, sinon son adresse.
    public var expediteur: String { deNom ?? de }

    /// « 13 h 30 » aujourd'hui, « 5 oct. · 18 h 45 » sinon.
    public var dateLisible: String {
        guard let recu, let date = DateEndry.lire(recu) else { return "" }
        let heure = DateEndry.heure(date)
        if DateEndry.courte(date) == DateEndry.courte(Date()) { return heure }
        return "\(DateEndry.jourMois(String(recu.prefix(10)))) · \(heure)"
    }

    /// Catégorie lisible (« rendez_vous » → « Rendez-vous »).
    public var categorieLisible: String? {
        guard let categorie else { return nil }
        switch categorie {
        case "rendez_vous": return "Rendez-vous"
        case "notification_automatique": return "Notification"
        case "range_auto": return "Rangé"
        default:
            let texte = categorie.replacingOccurrences(of: "_", with: " ")
            return texte.prefix(1).uppercased() + texte.dropFirst()
        }
    }

    /// Recherche simple : expéditeur, objet, résumé, nom d'une pièce.
    public func correspond(_ recherche: String) -> Bool {
        let r = recherche.trimmingCharacters(in: .whitespaces).lowercased()
        guard !r.isEmpty else { return true }
        let champs = [de, deNom ?? "", objet, resume ?? ""] + (pieces ?? []).map(\.nom)
        return champs.contains { $0.lowercased().contains(r) }
    }
}

public struct ListeMails: Decodable, Sendable, Equatable {
    public var mails: [MailRecu]

    public init(from decoder: Decoder) throws {
        mails = try decoder.champs().liste("mails")
    }
}

extension Requete {
    /// v1.12 : derniers e-mails reçus au bureau.
    public static func mails(limite: Int = 40) -> Requete {
        .init(.get, "\(prefixe)/mails", parametres: [Parametre("limite", String(limite))], delai: 30)
    }

    /// v1.12 : un e-mail en entier (texte, destinataires, pièces jointes).
    public static func mail(_ id: String) -> Requete {
        .init(.get, "\(prefixe)/mails/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)", delai: 30)
    }
}

extension EndryAPI {
    public func mails(limite: Int = 40) async throws(ErreurAPI) -> [MailRecu] {
        try await charger(ListeMails.self, .mails(limite: limite)).mails
    }

    public func mail(_ id: String) async throws(ErreurAPI) -> MailRecu { try await charger(MailRecu.self, .mail(id)) }
}
