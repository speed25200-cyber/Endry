import Foundation

// v1.2 : les agents du bureau (Secrétariat, Comptabilité…). Tout est facultatif à la lecture.

public enum EtatAgent: String, Sendable, Hashable {
    case libre, occupe, pause, erreur

    public var libelle: String {
        switch self {
        case .libre: "Disponible"
        case .occupe: "Au travail"
        case .pause: "En pause"
        case .erreur: "Bloqué"
        }
    }
}

/// Un agent de Claude sur le PC (`GET /agents`).
public struct AgentPC: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var nom: String
    public var role: String?
    public var icone: String?
    public var etat: EtatAgent
    public var tache: String?
    public var depuis: String?
    public var file: Int
    public var traiteesJour: Int
    public var derniereActivite: String?
    public var resumeJour: String?

    public init(id: String, nom: String, role: String? = nil, icone: String? = nil, etat: EtatAgent = .libre, tache: String? = nil,
                depuis: String? = nil, file: Int = 0, traiteesJour: Int = 0, derniereActivite: String? = nil, resumeJour: String? = nil) {
        self.id = id
        self.nom = nom
        self.role = role
        self.icone = icone
        self.etat = etat
        self.tache = tache
        self.depuis = depuis
        self.file = file
        self.traiteesJour = traiteesJour
        self.derniereActivite = derniereActivite
        self.resumeJour = resumeJour
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        guard let id = c.texte("id") ?? c.texte("nom") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "id manquant"))
        }
        self.id = id
        nom = c.texte("nom") ?? id.capitalized
        role = c.texte("role")
        icone = c.texte("icone")
        etat = c.texte("etat").flatMap { EtatAgent(rawValue: $0.lowercased()) } ?? ((c.texte("tache") ?? "").isEmpty ? .libre : .occupe)
        tache = c.texte("tache").flatMap { $0.isEmpty ? nil : $0 }
        depuis = c.texte("depuis")
        file = c.entier("file") ?? 0
        traiteesJour = c.entier("traitees_jour") ?? 0
        derniereActivite = c.texte("derniere_activite")
        resumeJour = c.texte("resume_jour").flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Agent connu de l'app (détection dans les questions, icône, domaine), s'il correspond.
    public var connu: AgentBureau? { AgentBureau(nom: id) ?? AgentBureau(nom: nom) }

    /// Symbole : celui du PC, sinon celui de l'agent connu.
    public var symbole: String { icone ?? connu?.icone ?? "person.crop.circle.fill" }

    /// Agents de base, affichés tant que le PC ne publie pas `GET /agents` (v1.0 / v1.1).
    public static var parDefaut: [AgentPC] {
        AgentBureau.allCases.map { AgentPC(id: $0.rawValue, nom: $0.nom, role: $0.domaine.prefix(1).uppercased() + $0.domaine.dropFirst()) }
    }
}

struct ListeAgentsPC: Decodable {
    var agents: [AgentPC]

    init(from decoder: Decoder) throws {
        if let liste = try? [ElementTolerantPublic<AgentPC>](from: decoder) {
            agents = liste.compactMap(\.valeur)
        } else {
            agents = try decoder.champs().liste("agents")
        }
    }
}

public enum TypeEntree: String, Sendable, Hashable {
    case action, emailRecu = "email_recu", emailPrepare = "email_prepare", decision, question, reponse, erreur, info

    public var icone: String {
        switch self {
        case .action: "bolt.fill"
        case .emailRecu: "tray.and.arrow.down.fill"
        case .emailPrepare: "envelope.badge.fill"
        case .decision: "checkmark.seal.fill"
        case .question: "questionmark.bubble.fill"
        case .reponse: "text.bubble.fill"
        case .erreur: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }
}

/// Une ligne du journal d'un agent (`GET /agents/{id}/journal`, `GET /journal`).
public struct EntreeJournal: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var horodatage: String?
    public var agent: String?
    public var type: TypeEntree
    public var titre: String
    public var detail: String?
    public var decisionReference: String?
    public var saisieId: String?
    public var chantierId: String?

    public init(id: String, horodatage: String?, agent: String?, type: TypeEntree, titre: String, detail: String? = nil,
                decisionReference: String? = nil, saisieId: String? = nil, chantierId: String? = nil) {
        self.id = id
        self.horodatage = horodatage
        self.agent = agent
        self.type = type
        self.titre = titre
        self.detail = detail
        self.decisionReference = decisionReference
        self.saisieId = saisieId
        self.chantierId = chantierId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        titre = c.texte("titre", defaut: "")
        horodatage = c.texte("horodatage") ?? c.texte("cree")
        guard !titre.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "titre manquant"))
        }
        id = c.texte("id") ?? "\(horodatage ?? "")-\(titre)"
        agent = c.texte("agent")
        type = c.texte("type").flatMap(TypeEntree.init(rawValue:)) ?? .info
        detail = c.texte("detail").flatMap { $0.isEmpty ? nil : $0 }
        decisionReference = c.texte("decision_reference").flatMap { $0.isEmpty ? nil : $0 }
        saisieId = c.texte("saisie_id")
        chantierId = c.texte("chantier_id")
    }

    public var date: Date? { horodatage.flatMap(DateEndry.lire) }
}

struct JournalPC: Decodable {
    var entrees: [EntreeJournal]

    init(from decoder: Decoder) throws {
        if let liste = try? [ElementTolerantPublic<EntreeJournal>](from: decoder) {
            entrees = liste.compactMap(\.valeur)
        } else {
            entrees = try decoder.champs().liste("entrees")
        }
    }
}

/// Source citée par un agent dans sa réponse (e-mail, facture…).
public struct SourceReponse: Decodable, Sendable, Hashable {
    public var type: String
    public var libelle: String
    public var reference: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        type = c.texte("type", defaut: "document")
        libelle = c.texte("libelle", defaut: "")
        reference = c.texte("reference")
    }

    public init(type: String, libelle: String, reference: String? = nil) {
        self.type = type
        self.libelle = libelle
        self.reference = reference
    }
}

public enum StatutReponse: String, Sendable, Hashable {
    case repondu, enCours = "en_cours", erreur
}

/// Réponse d'un agent à une question (`POST /agents/{id}/question`, `POST /assistant/question`, `GET /questions/{id}`).
public struct ReponseAgent: Decodable, Sendable, Hashable {
    public var statut: StatutReponse
    public var questionId: String?
    public var agent: String?
    public var reponse: String?
    public var sources: [SourceReponse]
    public var decisionReference: String?
    public var message: String?

    public init(statut: StatutReponse, questionId: String? = nil, agent: String? = nil, reponse: String? = nil,
                sources: [SourceReponse] = [], decisionReference: String? = nil, message: String? = nil) {
        self.statut = statut
        self.questionId = questionId
        self.agent = agent
        self.reponse = reponse
        self.sources = sources
        self.decisionReference = decisionReference
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        reponse = c.texte("reponse").flatMap { $0.isEmpty ? nil : $0 }
        message = c.texte("message")
        questionId = c.texte("question_id")
        statut = c.texte("statut").flatMap(StatutReponse.init(rawValue:))
            ?? (reponse != nil ? .repondu : (questionId != nil ? .enCours : .erreur))
        agent = c.texte("agent")
        sources = c.liste("sources")
        decisionReference = c.texte("decision_reference").flatMap { $0.isEmpty ? nil : $0 }
    }
}

extension Requete {
    public static let agents = Requete(.get, "\(prefixe)/agents")

    public static func journal(agent: String? = nil, limite: Int = 30) -> Requete {
        let chemin = agent.map { "\(prefixe)/agents/\($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0)/journal" }
            ?? "\(prefixe)/journal"
        return .init(.get, chemin, parametres: [Parametre("limite", String(limite))])
    }

    public static func questionAgent(_ agent: String, question: String) -> Requete {
        let id = agent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? agent
        return .init(.post, "\(prefixe)/agents/\(id)/question", corps: .json(json(["question": question])), delai: 90)
    }

    public static func suiviQuestion(_ id: String) -> Requete {
        .init(.get, "\(prefixe)/questions/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)", delai: 20)
    }
}

extension EndryAPI {
    public func agentsPC() async throws(ErreurAPI) -> [AgentPC] { try await charger(ListeAgentsPC.self, .agents).agents }

    public func journal(agent: String? = nil, limite: Int = 30) async throws(ErreurAPI) -> [EntreeJournal] {
        try await charger(JournalPC.self, .journal(agent: agent, limite: limite)).entrees
    }
}
