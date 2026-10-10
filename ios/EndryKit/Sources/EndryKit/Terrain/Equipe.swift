import Foundation

/// Rôle donné par le lien d'accès (v1.3).
public enum RoleAcces: String, Codable, Sendable {
    case patron
    case ouvrier
    /// v1.12 : les montants et « Poser une question » (lecture seule). Ni décisions, ni courrier, ni documents.
    case directeur
}

/// Chantier confié à un ouvrier pour la journée : ni montants, ni décisions.
public struct ChantierEquipe: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var titre: String
    public var client: String?
    public var lieu: String?
    public var adresse: String?
    public var consignes: String?
    public var contact: String?
    public var telephone: String?
    public var debut: String?

    public init(id: String, titre: String, client: String? = nil, lieu: String? = nil, adresse: String? = nil,
                consignes: String? = nil, contact: String? = nil, telephone: String? = nil, debut: String? = nil) {
        self.id = id
        self.titre = titre
        self.client = client
        self.lieu = lieu
        self.adresse = adresse
        self.consignes = consignes
        self.contact = contact
        self.telephone = telephone
        self.debut = debut
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        guard let id = c.texte("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "id manquant"))
        }
        self.id = id
        titre = c.texte("titre", defaut: "Chantier")
        client = c.texte("client")
        lieu = c.texte("lieu")
        adresse = c.texte("adresse")
        consignes = c.texte("consignes") ?? c.texte("note")
        contact = c.texte("contact")
        telephone = c.texte("telephone")
        debut = c.texte("debut") ?? c.texte("heure")
    }
}

/// `GET /equipe/jour` (jeton d'ouvrier) : `{nom, date, chantiers, message?}`.
public struct JourneeEquipe: Decodable, Sendable, Hashable {
    public var nom: String?
    public var date: String?
    public var chantiers: [ChantierEquipe]
    public var message: String?

    public init(nom: String? = nil, date: String? = nil, chantiers: [ChantierEquipe] = [], message: String? = nil) {
        self.nom = nom
        self.date = date
        self.chantiers = chantiers
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        nom = c.texte("nom")
        date = c.texte("date")
        chantiers = c.liste("chantiers")
        message = c.texte("message")
    }
}

/// Temps passé sur un chantier (début → fin ; fin absente : en cours).
public struct Pointage: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var chantierId: String
    public var chantier: String
    public var debut: Date
    public var fin: Date?

    public init(id: String = UUID().uuidString, chantierId: String, chantier: String, debut: Date, fin: Date? = nil) {
        self.id = id
        self.chantierId = chantierId
        self.chantier = chantier
        self.debut = debut
        self.fin = fin
    }

    public func duree(jusqua maintenant: Date = Date()) -> TimeInterval {
        max(0, (fin ?? maintenant).timeIntervalSince(debut))
    }
}

/// Journée d'un ouvrier : pointages, pauses déduites, remarques. Heures arrondies au quart d'heure.
public struct FeuilleJournee: Codable, Sendable, Hashable {
    public var date: String
    public var ouvrier: String
    public var pointages: [Pointage]
    public var remarques: String

    public init(date: String, ouvrier: String, pointages: [Pointage] = [], remarques: String = "") {
        self.date = date
        self.ouvrier = ouvrier
        self.pointages = pointages
        self.remarques = remarques
    }

    public var enCours: Pointage? { pointages.last { $0.fin == nil } }

    /// Commence sur un chantier (arrête le pointage en cours s'il y en a un).
    public mutating func commencer(_ chantier: ChantierEquipe, le date: Date = Date()) {
        arreter(le: date)
        pointages.append(Pointage(chantierId: chantier.id, chantier: chantier.titre, debut: date))
    }

    public mutating func arreter(le date: Date = Date()) {
        guard let i = pointages.lastIndex(where: { $0.fin == nil }) else { return }
        pointages[i].fin = max(date, pointages[i].debut)
    }

    /// Heures par chantier, arrondies au quart d'heure, dans l'ordre du premier pointage.
    public func heuresParChantier(jusqua maintenant: Date = Date()) -> [(chantierId: String, chantier: String, heures: Double)] {
        var ordre: [String] = []
        var noms: [String: String] = [:]
        var secondes: [String: TimeInterval] = [:]
        for p in pointages {
            if secondes[p.chantierId] == nil { ordre.append(p.chantierId) }
            noms[p.chantierId] = p.chantier
            secondes[p.chantierId, default: 0] += p.duree(jusqua: maintenant)
        }
        return ordre.map { id in (id, noms[id] ?? id, Self.auQuart((secondes[id] ?? 0) / 3600)) }
    }

    public func total(jusqua maintenant: Date = Date()) -> Double {
        heuresParChantier(jusqua: maintenant).reduce(0) { $0 + $1.heures }
    }

    public static func auQuart(_ heures: Double) -> Double {
        (heures * 4).rounded() / 4
    }

    public var resume: String {
        let lignes = heuresParChantier().map { "\($0.chantier) : \(FormatSuisse.heures($0.heures))" }.joined(separator: " ; ")
        var p = ["Journée de \(ouvrier) du \(DateEndry.courte(date)) — total \(FormatSuisse.heures(total())).", lignes.isEmpty ? "" : lignes + "."]
        if !remarques.isEmpty { p.append("Remarques : \(remarques)") }
        p.append("Reporter les heures sur les chantiers (régie ou suivi) ; rien à envoyer à un client.")
        return p.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private struct Donnees: Encodable {
        struct Ligne: Encodable {
            var chantierId: String
            var chantier: String
            var heures: Double
        }
        var date: String
        var ouvrier: String
        var lignes: [Ligne]
        var pointages: [Pointage]
        var remarques: String
    }

    public func envoi(photos: [FormulaireMultipart.Fichier] = []) -> EnvoiTerrain {
        let lignes = heuresParChantier().map { Donnees.Ligne(chantierId: $0.chantierId, chantier: $0.chantier, heures: $0.heures) }
        let donnees = Donnees(date: date, ouvrier: ouvrier, lignes: lignes, pointages: pointages, remarques: remarques)
        return EnvoiTerrain(type: .journee, chantierId: lignes.count == 1 ? lignes[0].chantierId : nil, resume: resume,
                            donnees: EnvoiTerrain.json(donnees), fichiers: photos, cle: "J-\(date)-\(ouvrier)")
    }
}

/// `POST /equipe/invitations {nom}` → `{ok, lien, expire_le, message}` : lien d'équipe à transmettre à l'ouvrier.
public struct InvitationEquipe: Decodable, Sendable, Equatable {
    public var ok: Bool
    public var lien: String?
    public var expireLe: String?
    public var message: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        ok = c.booleen("ok") ?? (c.texte("lien") != nil)
        lien = c.texte("lien")
        expireLe = c.texte("expire_le")
        message = c.texte("message")
    }
}

extension Requete {
    public static let journeeEquipe = Requete(.get, "\(prefixe)/equipe/jour")

    /// `role` : `"directeur"` pour un accès directeur (v1.12) ; absent : ouvrier.
    public static func invitationEquipe(nom: String, role: String? = nil) -> Requete {
        var corps = ["nom": nom]
        if let role { corps["role"] = role }
        return .init(.post, "\(prefixe)/equipe/invitations", corps: .json(json(corps)))
    }
}

extension EndryAPI {
    public func journeeEquipe() async throws(ErreurAPI) -> JourneeEquipe { try await charger(JourneeEquipe.self, .journeeEquipe) }

    public func inviterOuvrier(nom: String, role: String? = nil) async throws(ErreurAPI) -> InvitationEquipe {
        let reponse = try await charger(InvitationEquipe.self, .invitationEquipe(nom: nom, role: role))
        guard reponse.ok, reponse.lien != nil else { throw .refus(reponse.message ?? "Le bureau n’a pas pu créer le lien.") }
        return reponse
    }
}

// MARK: - Accès directeur (v1.12) : note vocale

extension Requete {
    /// `POST /direction/note {texte}` → `{ok, message}` : la note est consignée, le secrétariat prépare les décisions.
    public static func noteDirecteur(_ texte: String) -> Requete {
        .init(.post, "\(prefixe)/direction/note", corps: .json(json(["texte": texte])), delai: 30)
    }
}

extension EndryAPI {
    public func consignerNoteDirecteur(_ texte: String) async throws(ErreurAPI) -> ReponseSimple {
        let reponse = try await charger(ReponseSimple.self, .noteDirecteur(texte))
        guard reponse.ok else { throw .refus(reponse.message ?? "La note n’a pas pu être consignée.") }
        return reponse
    }
}

/// Note vocale consignée (`GET /direction/notes`).
public struct NoteDirecteur: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var date: String?
    public var texte: String
    public var auteur: String?
}

struct ListeNotesDirecteur: Decodable, Sendable {
    var notes: [NoteDirecteur]
}

extension Requete {
    public static let notesDirecteur = Requete(.get, "\(prefixe)/direction/notes")
}

extension EndryAPI {
    public func notesDirecteur() async throws(ErreurAPI) -> [NoteDirecteur] {
        try await charger(ListeNotesDirecteur.self, .notesDirecteur).notes
    }
}
