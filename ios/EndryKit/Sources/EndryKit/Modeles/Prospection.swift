import Foundation

/// Piste commerciale consignée par le bureau (`GET /pistes`, v1.13) : un projet ou un donneur d'ordre précis,
/// avec sa source publique. Rien n'est envoyé d'office : la direction choisit, le bureau prépare, la décision reste.
public struct Piste: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var titre: String
    public var type: String?
    public var typeLibelle: String?
    public var lieu: String?
    public var canton: String?
    public var maitreOuvrage: String?
    public var architecte: String?
    public var contact: String?
    public var email: String?
    public var source: String?
    public var sourceUrl: String?
    public var resume: String?
    public var pourquoi: String?
    public var echeance: String?
    public var score: Int?
    public var statut: String?
    public var semaine: String?

    enum CodingKeys: String, CodingKey {
        case id, titre, type, lieu, canton, architecte, contact, email, source, resume, pourquoi, echeance, score, statut, semaine
        case typeLibelle = "type_libelle"
        case maitreOuvrage = "maitre_ouvrage"
        case sourceUrl = "source_url"
    }

    public var estNouvelle: Bool { (statut ?? "nouvelle") == "nouvelle" }
    public var enPreparation: Bool { statut == "contact_en_preparation" }
    public var estEcartee: Bool { statut == "ecartee" }

    /// « Payerne · VD »
    public var endroit: String {
        [lieu ?? "", canton ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// `GET /pistes` : le carnet et l'état de la recherche hebdomadaire.
public struct CarnetPistes: Decodable, Sendable {
    public var pistes: [Piste]
    public var enCours: Bool?
    public var derniereRecherche: String?
    public var rythme: String?
    public var nouvelles: Int?

    enum CodingKeys: String, CodingKey {
        case pistes, rythme, nouvelles
        case enCours = "en_cours"
        case derniereRecherche = "derniere_recherche"
    }
}

extension Requete {
    public static let pistes = Requete(.get, "\(prefixe)/pistes")
    public static let recherchePistes = Requete(.post, "\(prefixe)/pistes/recherche", delai: 30)

    /// `action` : `contacter`, `ecarter`, `garder`, `gagnee`.
    public static func actionPiste(_ id: String, action: String) -> Requete {
        let p = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return .init(.post, "\(prefixe)/pistes/\(p)/\(action)", delai: 30)
    }
}

extension EndryAPI {
    public func carnetPistes() async throws(ErreurAPI) -> CarnetPistes { try await charger(CarnetPistes.self, .pistes) }

    public func lancerRecherchePistes() async throws(ErreurAPI) -> ReponseSimple {
        try await charger(ReponseSimple.self, .recherchePistes)
    }

    public func agirSurPiste(_ id: String, action: String) async throws(ErreurAPI) -> ReponseSimple {
        let reponse = try await charger(ReponseSimple.self, .actionPiste(id, action: action))
        guard reponse.ok else { throw .refus(reponse.message ?? "Le bureau n’a pas pu traiter cette piste.") }
        return reponse
    }
}
