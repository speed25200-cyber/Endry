import Foundation

/// Tout ce qui se passe au bureau : agents (v1.2), leur journal, file et pause de Claude, saisies récentes.
public struct EtatBureau: Sendable, Equatable {
    public var etat: EtatAssistant?
    /// Saisies les plus récentes (la plus récente d'abord).
    public var saisies: [SaisieHistorique]
    /// Agents publiés par le PC (`GET /agents`) ; vide avant v1.2.
    public var agents: [AgentPC]
    /// Journal de tous les agents, le plus récent d'abord ; vide avant v1.2.
    public var journal: [EntreeJournal]

    public init(etat: EtatAssistant?, saisies: [SaisieHistorique], agents: [AgentPC] = [], journal: [EntreeJournal] = []) {
        self.etat = etat
        self.saisies = saisies
        self.agents = agents
        self.journal = journal
    }

    public var enPause: Bool { etat?.pause ?? false }
    public var enCours: [SaisieHistorique] { saisies.filter { $0.statut == .enCours || $0.statut == .transmis } }
    public var traitees: [SaisieHistorique] { saisies.filter { $0.statut == .traite } }
    public var agentsAuTravail: [AgentPC] { agents.filter { $0.etat == .occupe } }

    /// Libellé court pour les pastilles (assistant vocal, Aujourd'hui).
    public var libelleCourt: String {
        if enPause { return "Claude en pause" }
        if !agents.isEmpty {
            let n = agentsAuTravail.count
            return n == 0 ? "Bureau disponible" : "\(n) agent\(n > 1 ? "s" : "") au travail"
        }
        let n = max(etat?.file ?? 0, enCours.count)
        if n > 0 { return "Claude travaille · \(n) en cours" }
        return "Claude disponible"
    }

    /// Phrase à dire : tout ce qui se passe sur le PC.
    public var phrase: String {
        var morceaux: [String] = []
        if enPause {
            morceaux.append("Claude est en pause sur le PC : rien ne part tant que vous ne le relancez pas")
        }
        if !agents.isEmpty {
            let lignes = agents.map { a -> String in
                switch a.etat {
                case .occupe: a.tache.map { "\(a.nom) : \(Self.minuscule($0))" } ?? "\(a.nom) au travail"
                case .libre: "\(a.nom) disponible"
                case .pause: "\(a.nom) en pause"
                case .erreur: "\(a.nom) bloqué"
                }
            }
            morceaux.append("Au bureau : " + lignes.joined(separator: " ; "))
            let recentes = journal.prefix(3).map { e in
                (agents.first { $0.id == e.agent }?.nom).map { "\($0), \(Self.minuscule(Self.sansPoint(e.titre)))" } ?? Self.sansPoint(e.titre)
            }
            if !recentes.isEmpty { morceaux.append("Dernières actions : " + recentes.joined(separator: " ; ")) }
        } else {
            if !enPause {
                let n = max(etat?.file ?? 0, enCours.count)
                morceaux.append(n == 0 ? "Claude est disponible, rien en attente"
                                       : "Claude travaille sur le PC, \(n) demande\(n > 1 ? "s" : "") en cours")
            }
            if let courante = enCours.first {
                morceaux.append("En ce moment : « \(Self.abreger(BureauClaude.questionSeule(courante.texte))) »")
            }
            let faits = traitees.prefix(3).compactMap { s -> String? in
                guard let resume = s.resume, !resume.isEmpty else { return nil }
                return s.decisionReference == nil ? Self.sansPoint(resume) : "\(Self.sansPoint(resume)), à valider"
            }
            if !faits.isEmpty { morceaux.append("Derniers travaux : " + faits.joined(separator: " ; ")) }
            if let date = etat?.derniereActivite.flatMap(DateEndry.lire) {
                morceaux.append("Dernière activité \(DateEndry.ilYa(date))")
            }
        }
        return morceaux.joined(separator: ". ") + "."
    }

    /// Ce que fait un agent précis : état, tâche, journée, dernières actions.
    public func phrase(agent: AgentPC) -> String {
        var morceaux: [String] = []
        switch agent.etat {
        case .occupe: morceaux.append(agent.tache.map { "\(agent.nom) est au travail : \(Self.minuscule($0))" } ?? "\(agent.nom) est au travail")
        case .libre: morceaux.append("\(agent.nom) est disponible")
        case .pause: morceaux.append("\(agent.nom) est en pause")
        case .erreur: morceaux.append("\(agent.nom) est bloqué et attend une intervention")
        }
        if agent.file > 0 { morceaux.append("\(agent.file) demande\(agent.file > 1 ? "s" : "") en attente") }
        if let jour = agent.resumeJour { morceaux.append("Aujourd’hui : \(Self.minuscule(Self.sansPoint(jour)))") }
        let actions = journal.filter { $0.agent == agent.id }.prefix(3).map { Self.sansPoint($0.titre) }
        if !actions.isEmpty { morceaux.append("Dernières actions : " + actions.joined(separator: " ; ")) }
        return morceaux.joined(separator: ". ") + "."
    }

    /// Agent cité dans une question (« que fait le secrétariat ? »).
    public func agent(cite question: String) -> AgentPC? {
        let q = " " + RepondeurLocal.normaliser(question) + " "
        if let nomme = agents.first(where: { q.contains(" \(RepondeurLocal.normaliser($0.nom)) ") || q.contains(" \($0.id) ") }) {
            return nomme
        }
        guard let connu = AgentBureau.allCases.first(where: { a in a.appellations.contains { q.contains(" \($0) ") } }) else { return nil }
        return agents.first { $0.connu == connu }
    }

    static func abreger(_ texte: String, max: Int = 90) -> String {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > max else { return t }
        return String(t.prefix(max)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func sansPoint(_ texte: String) -> String {
        var t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        while let d = t.last, ".;".contains(d) { t.removeLast() }
        return t
    }

    static func minuscule(_ texte: String) -> String {
        guard let premier = texte.first else { return texte }
        // « Répond à Mme Rey » → « répond à Mme Rey » ; les sigles (« RE-00416 ») restent intacts.
        if texte.count > 1, texte[texte.index(after: texte.startIndex)].isUppercase { return texte }
        return premier.lowercased() + texte.dropFirst()
    }
}

/// Comment suivre une question en attente de réponse.
public enum SuiviQuestion: Sendable, Hashable {
    /// v1.2 : `GET /questions/{id}`.
    case question(id: String, agent: String?)
    /// v1.1 : question déposée comme saisie, réponse dans son résumé.
    case saisie(id: String?, texte: String)
}

/// Question posée à l'assistant (tous domaines ou un domaine précis).
public enum QuestionPosee: Sendable, Equatable {
    case reponse(ReponseAgent)
    /// La réponse viendra plus tard ; `message` : hors horaires, « l'assistant répondra à son prochain passage… ».
    case enAttente(SuiviQuestion, message: String?)
}

/// Dialogue avec Claude et ses agents, sur le PC.
/// v1.2 : `POST /agents/{id}/question` ou `POST /assistant/question`, suivi par `GET /questions/{id}`.
/// Repli v1.1 : la question part comme une saisie, la réponse revient dans son résumé (`GET /saisies`).
public struct BureauClaude: Sendable {
    public let api: any EndryAPI

    public init(api: any EndryAPI) {
        self.api = api
    }

    /// Préfixe qui dit à Claude ce qu'on attend : une réponse, pas une action.
    public static let prefixeQuestion = "Question du patron (depuis l’assistant vocal de l’iPhone). Réponds-lui dans le résumé, en deux ou trois phrases à dire à voix haute ; ne prépare et n’envoie rien : "

    public static func texteQuestion(_ question: String, agent: AgentBureau? = nil) -> String {
        texteQuestion(question, nomAgent: agent?.nom)
    }

    public static func texteQuestion(_ question: String, nomAgent: String?) -> String {
        let pour = nomAgent.map { "[Pour l’agent \($0)] " } ?? ""
        return prefixeQuestion + pour + "« \(question.trimmingCharacters(in: .whitespacesAndNewlines)) »"
    }

    public static func estQuestion(_ texte: String) -> Bool { texte.hasPrefix(prefixeQuestion) }

    /// Nom de l'agent visé par une question déposée (lu dans son texte).
    public static func nomAgent(_ texte: String) -> String? {
        guard estQuestion(texte) else { return nil }
        let reste = texte.dropFirst(prefixeQuestion.count)
        let marque = "[Pour l’agent "
        guard reste.hasPrefix(marque), let fin = reste.firstIndex(of: "]") else { return nil }
        return String(reste[reste.index(reste.startIndex, offsetBy: marque.count)..<fin])
    }

    public static func agent(_ texte: String) -> AgentBureau? { nomAgent(texte).flatMap(AgentBureau.init(nom:)) }

    /// La question telle que le patron l'a posée (sans le préfixe), pour l'historique.
    public static func questionSeule(_ texte: String) -> String {
        guard estQuestion(texte) else { return texte }
        var q = String(texte.dropFirst(prefixeQuestion.count))
        if q.hasPrefix("[Pour l’agent "), let fin = q.firstIndex(of: "]") {
            q = String(q[q.index(after: fin)...]).trimmingCharacters(in: .whitespaces)
        }
        if q.hasPrefix("« ") { q.removeFirst(2) }
        if q.hasSuffix(" »") { q.removeLast(2) }
        return q
    }

    /// Libellé d'historique : « Question à Claude · Secrétariat : … » plutôt que le texte technique envoyé au PC.
    public static func libelle(_ texte: String) -> String {
        guard estQuestion(texte) else { return texte }
        let destinataire = nomAgent(texte).map { "Claude · \($0)" } ?? "Claude"
        return "Question à \(destinataire) : " + questionSeule(texte)
    }

    /// Agents, journal, pause, file, saisies. `nil` si le PC ne publie rien de tout cela (v1.0).
    public func etat() async -> EtatBureau? {
        async let etat = try? api.etatAssistant()
        async let saisies = try? api.saisies()
        async let agents = try? api.agentsPC()
        async let journal = try? api.journal(limite: 12)
        let (e, s, a, j) = await (etat, saisies, agents, journal)
        guard e != nil || s != nil || a != nil else { return nil }
        return EtatBureau(etat: e, saisies: s ?? [], agents: a ?? [], journal: j ?? [])
    }

    /// Agent du PC visé : nommé par le modèle vocal, cité dans la question, ou déduit du sujet.
    public func resoudreAgent(question: String, demande: String?) async -> (id: String?, nom: String?) {
        let agents = (try? await api.agentsPC()) ?? []
        if let demande, !demande.isEmpty {
            let n = RepondeurLocal.normaliser(demande)
            if let a = agents.first(where: { $0.id == n || RepondeurLocal.normaliser($0.nom) == n }) { return (a.id, a.nom) }
            if let connu = AgentBureau(nom: demande) {
                if let a = agents.first(where: { $0.connu == connu }) { return (a.id, a.nom) }
                return (agents.isEmpty ? nil : connu.rawValue, connu.nom)
            }
        }
        if let cite = EtatBureau(etat: nil, saisies: [], agents: agents).agent(cite: question) { return (cite.id, cite.nom) }
        if let connu = AgentBureau.detecter(question) {
            if let a = agents.first(where: { $0.connu == connu }) { return (a.id, a.nom) }
            return (nil, connu.nom)
        }
        return (nil, nil)
    }

    /// Pose la question au domaine (`agentId`), sinon à l'assistant qui choisit, sinon (serveur v1.1) par la saisie.
    /// Le PC l'exécute en lecture seule et répond à son prochain passage.
    public func poser(_ question: String, agentId: String? = nil, nomAgent: String? = nil) async throws(ErreurAPI) -> QuestionPosee {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw .refus("La question est vide.") }
        var requetes: [Requete] = []
        if let agentId { requetes.append(.questionAgent(agentId, question: q)) }
        requetes.append(.questionClaude(q, agent: agentId))
        for requete in requetes {
            guard let data = try? await api.envoyer(requete),
                  var reponse = try? JSONDecoder().decode(ReponseAgent.self, from: data) else { continue }
            if reponse.agent == nil { reponse.agent = agentId }
            switch reponse.statut {
            case .repondu where reponse.reponse != nil:
                return .reponse(reponse)
            case .enCours:
                if let id = reponse.questionId {
                    return .enAttente(.question(id: id, agent: reponse.agent), message: reponse.message.flatMap { $0.isEmpty ? nil : $0 })
                }
            case .erreur:
                throw .refus(reponse.message ?? "L’agent n’a pas pu répondre.")
            default:
                continue
            }
        }
        let texte = Self.texteQuestion(q, nomAgent: nomAgent)
        let formulaire = FormulaireMultipart(champs: [Parametre("texte", texte)] + (agentId.map { [Parametre("agent", $0)] } ?? []))
        let reponse = try await api.charger(ReponseSimple.self, .saisie(formulaire))
        guard reponse.ok else { throw .refus(reponse.message ?? "Le PC n’a pas accepté la question.") }
        return .enAttente(.saisie(id: reponse.saisieId, texte: texte), message: nil)
    }

    /// Attend la réponse d'une question v1.2 : `GET /questions/{id}` toutes les 2 s pendant 60 s.
    /// Au-delà (ou pour une question déposée en saisie), on ne sonde plus : `verifier` est rappelé
    /// à chaque événement `maj saisies` du PC. `nil` : pas encore de réponse.
    public func attendre(_ suivi: SuiviQuestion, delai: Duration = .seconds(60), intervalle: Duration = .seconds(2)) async -> ReponseAgent? {
        guard case .question = suivi else { return await verifier(suivi) }
        let limite = ContinuousClock.now + delai
        while ContinuousClock.now < limite, !Task.isCancelled {
            if let r = await verifier(suivi) { return r }
            try? await Task.sleep(for: intervalle)
        }
        return nil
    }

    /// Une seule vérification : la réponse est-elle arrivée ?
    public func verifier(_ suivi: SuiviQuestion) async -> ReponseAgent? {
        switch suivi {
        case .question(let id, let agent):
            guard let data = try? await api.envoyer(.suiviQuestion(id)),
                  var r = try? JSONDecoder().decode(ReponseAgent.self, from: data), r.statut != .enCours else { return nil }
            if r.agent == nil { r.agent = agent }
            return r
        case .saisie(let saisieId, let texte):
            guard let saisies = try? await api.saisies(),
                  let s = saisies.first(where: { saisie in saisieId.map { $0 == saisie.id } ?? (saisie.texte == texte) }),
                  s.statut == .traite || s.statut == .erreur else { return nil }
            return ReponseAgent(statut: s.statut == .traite ? .repondu : .erreur, agent: Self.nomAgent(texte),
                                reponse: s.resume, decisionReference: s.decisionReference)
        }
    }
}

/// Réponse de `POST /assistant/question` (ancienne forme lue par les tests) : `{reponse}` ou `{message}`.
struct ReponseQuestion: Decodable {
    var texte: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        texte = c.texte("reponse") ?? c.texte("message")
    }
}

extension Requete {
    /// Question à Claude, qui choisit l'agent si `agent` est absent.
    public static func questionClaude(_ question: String, agent: String? = nil) -> Requete {
        var corps = ["question": question]
        if let agent { corps["agent"] = agent }
        return .init(.post, "\(prefixe)/assistant/question", corps: .json(json(corps)), delai: 90)
    }
}
