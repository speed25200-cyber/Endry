import Foundation

/// Documents produits sur le terrain (contrat v1.3) : bon de régie signé, bon de livraison scanné,
/// relevé 3D, journée d'un ouvrier. Tous partent par `POST /terrain` ; un PC plus ancien les reçoit
/// comme une saisie ordinaire (texte + images), orientée vers le bon domaine de l'assistant.
public enum TypeTerrain: String, Codable, Sendable, CaseIterable {
    case regie
    case bonLivraison = "bon_livraison"
    case releve
    case journee
    /// v1.5 : le patron demande une offre ou une facture ; l'assistant la prépare dans Bexio (brouillon + décision).
    case demandeOffre = "demande_offre"
    case demandeFacture = "demande_facture"

    public var libelle: String {
        switch self {
        case .regie: "Bon de régie"
        case .bonLivraison: "Bon de livraison"
        case .releve: "Relevé 3D"
        case .journee: "Journée d’équipe"
        case .demandeOffre: "Nouvelle offre"
        case .demandeFacture: "Nouvelle facture"
        }
    }

    /// Domaine de l'assistant qui s'en occupe (repli par saisie).
    public var agent: AgentBureau {
        switch self {
        case .regie: .comptabilite
        case .bonLivraison: .achats
        case .releve: .offres
        case .journee: .chantiers
        case .demandeOffre: .offres
        case .demandeFacture: .comptabilite
        }
    }
}

/// Un envoi terrain prêt à partir : données structurées (JSON), résumé lisible et pièces jointes.
public struct EnvoiTerrain: Sendable, Hashable {
    public var type: TypeTerrain
    public var chantierId: String?
    /// Résumé en français, lisible par l'assistant et par le patron (repli : texte de la saisie).
    public var resume: String
    /// Données structurées (JSON UTF-8), selon le type.
    public var donnees: Data
    public var fichiers: [FormulaireMultipart.Fichier]
    /// Clé d'idempotence : un renvoi de la file hors ligne n'est jamais traité deux fois.
    public var cle: String

    public init(type: TypeTerrain, chantierId: String?, resume: String, donnees: Data,
                fichiers: [FormulaireMultipart.Fichier] = [], cle: String = UUID().uuidString) {
        self.type = type
        self.chantierId = chantierId
        self.resume = resume
        self.donnees = donnees
        self.fichiers = fichiers
        self.cle = cle
    }

    /// Corps `multipart/form-data` de `POST /terrain`.
    public var formulaire: FormulaireMultipart {
        var champs = [Parametre("type", type.rawValue), Parametre("cle", cle), Parametre("resume", resume),
                      Parametre("donnees", String(decoding: donnees, as: UTF8.self))]
        if let chantierId { champs.append(Parametre("chantier_id", chantierId)) }
        let pieces = fichiers.map { FormulaireMultipart.Fichier(champ: "pieces", nomFichier: $0.nomFichier, typeMIME: $0.typeMIME, donnees: $0.donnees) }
        return FormulaireMultipart(champs: champs, fichiers: pieces)
    }

    /// Repli (PC sans `/terrain`) : texte de saisie orienté vers le bon domaine.
    public var texteSaisie: String {
        "[Pour l’agent \(type.agent.nom)] \(type.libelle) depuis l’iPhone. \(resume)"
    }

    /// Repli : seules les images passent par `/saisie` (le PC n'y lit pas les autres formats).
    public var photosSaisie: [FormulaireMultipart.Fichier] {
        fichiers
            .filter { $0.typeMIME.hasPrefix("image/") }
            .map { FormulaireMultipart.Fichier(champ: "photos", nomFichier: $0.nomFichier, typeMIME: $0.typeMIME, donnees: $0.donnees) }
    }

    /// Encode des données structurées (clés triées : un renvoi produit exactement le même corps).
    public static func json<T: Encodable>(_ valeur: T) -> Data {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.sortedKeys]
        encodeur.keyEncodingStrategy = .convertToSnakeCase
        encodeur.dateEncodingStrategy = .custom { date, e in
            var c = e.singleValueContainer()
            try c.encode(DateEndry.horodatage(date))
        }
        return (try? encodeur.encode(valeur)) ?? Data("{}".utf8)
    }
}

/// Réponse de `POST /terrain` : `{ok, message, id, decision_reference?}`.
public struct ReponseTerrain: Decodable, Sendable, Equatable {
    public var ok: Bool
    public var message: String?
    public var id: String?
    /// Décision préparée par l'assistant (ex. facture de régie à valider).
    public var decisionReference: String?
    /// Vrai si le PC n'a pas encore `/terrain` et que l'envoi est passé par la saisie.
    public var parSaisie: Bool

    public init(ok: Bool, message: String? = nil, id: String? = nil, decisionReference: String? = nil, parSaisie: Bool = false) {
        self.ok = ok
        self.message = message
        self.id = id
        self.decisionReference = decisionReference
        self.parSaisie = parSaisie
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        ok = c.booleen("ok") ?? false
        message = c.texte("message")
        id = c.texte("id") ?? c.texte("saisie_id")
        decisionReference = c.texte("decision_reference")
        parSaisie = false
    }
}

extension Requete {
    public static func terrain(_ envoi: EnvoiTerrain) -> Requete {
        .init(.post, "\(prefixe)/terrain", corps: .multipart(envoi.formulaire), delai: 180)
    }
}

extension EndryAPI {
    /// `POST /terrain` ; si le PC ne connaît pas encore la route (404 / 405), l'envoi part en saisie.
    public func envoyerTerrain(_ envoi: EnvoiTerrain) async throws(ErreurAPI) -> ReponseTerrain {
        do throws(ErreurAPI) {
            let reponse = try await charger(ReponseTerrain.self, .terrain(envoi))
            guard reponse.ok else { throw ErreurAPI.refus(reponse.message ?? "Le bureau n’a pas accepté cet envoi.") }
            return reponse
        } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
            let simple = try await saisie(texte: envoi.texteSaisie, fichiers: envoi.photosSaisie)
            return ReponseTerrain(ok: true, message: simple.message, id: simple.saisieId, parSaisie: true)
        }
    }
}
