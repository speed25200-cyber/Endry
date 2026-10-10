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

    /// Horaires de passage de l'assistant (texte du PC).
    public var horaires: String? { etat?.horaires ?? agents.first(where: { $0.horaires != nil })?.horaires }

    /// Faux hors des horaires de passage (donné par le PC, sinon calculé à partir des horaires).
    public func enService(_ date: Date = Date()) -> Bool {
        if let enService = etat?.enService { return enService }
        if let texte = horaires, let h = HorairesAssistant(texte: texte) { return h.enService(date) }
        return true
    }

    /// « lundi à 7 h » quand l'assistant est hors horaires.
    public func repasse(_ date: Date = Date()) -> String? {
        guard !enService(date) else { return nil }
        guard let texte = horaires, let h = HorairesAssistant(texte: texte) else { return "à son prochain passage" }
        return h.prochainPassage(apres: date)
    }

    /// État affiché d'un domaine : jamais « Disponible » hors des horaires.
    public func etatAffiche(_ agent: AgentPC, date: Date = Date()) -> EtatAgent {
        if agent.etat == .libre, !enService(date) { return .horsHoraires }
        return agent.etat
    }

    public var agentsAuTravail: [AgentPC] { agents.filter { $0.etat == .occupe } }

    /// Libellé court pour les pastilles (assistant vocal, Aujourd'hui).
    public var libelleCourt: String {
        if enPause { return "Assistant en pause" }
        if let quand = repasse() { return "Hors horaires · repasse \(quand)" }
        if !agents.isEmpty {
            let actifs = agentsAuTravail.map(\.nom)
            if actifs.isEmpty { return "Assistant disponible" }
            return "Assistant au travail · " + actifs.prefix(2).joined(separator: ", ") + (actifs.count > 2 ? "…" : "")
        }
        let n = max(etat?.file ?? 0, enCours.count)
        if n > 0 { return "Assistant au travail · \(n) en cours" }
        return "Assistant disponible"
    }

    /// Phrase à dire : tout ce qui se passe sur le PC. Un seul assistant, présenté par domaines.
    public var phrase: String {
        var morceaux: [String] = []
        if enPause {
            morceaux.append("L’assistant est en pause : vos décisions s’exécutent, il ne prépare rien de nouveau")
        } else if let quand = repasse() {
            morceaux.append("L’assistant est hors horaires\(horaires.map { " (\($0))" } ?? ""), il repasse \(quand)")
        }
        if !agents.isEmpty {
            let actifs = agentsAuTravail
            if !actifs.isEmpty {
                morceaux.append("L’assistant travaille " + actifs.map { a in
                    "côté \(a.nom)" + (a.tache.map { " : \(Self.minuscule(Self.sansPoint($0)))" } ?? "")
                }.joined(separator: " ; "))
            } else if !enPause, enService() {
                morceaux.append("L’assistant est disponible, rien en cours")
            }
            let enPauseDomaines = agents.filter { $0.etat == .pause }.map(\.nom)
            if !enPauseDomaines.isEmpty { morceaux.append("En pause : " + enPauseDomaines.joined(separator: ", ")) }
            let recentes = journal.prefix(3).map { e in
                (agents.first { $0.id == e.agent }?.nom).map { "côté \($0), \(Self.minuscule(Self.sansPoint(e.titre)))" } ?? Self.sansPoint(e.titre)
            }
            if !recentes.isEmpty { morceaux.append("Dernières actions : " + recentes.joined(separator: " ; ")) }
        } else {
            if !enPause, enService() {
                let n = max(etat?.file ?? 0, enCours.count)
                morceaux.append(n == 0 ? "L’assistant est disponible, rien en attente"
                                       : "L’assistant travaille sur le PC, \(n) demande\(n > 1 ? "s" : "") en cours")
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

    /// Ce que fait l'assistant dans un domaine : état, tâche, journée, dernières actions.
    public func phrase(agent: AgentPC) -> String {
        var morceaux: [String] = []
        let cote = "L’assistant, côté \(agent.nom),"
        switch etatAffiche(agent) {
        case .occupe: morceaux.append(agent.tache.map { "\(cote) est au travail : \(Self.minuscule($0))" } ?? "\(cote) est au travail")
        case .libre: morceaux.append("\(cote) est disponible")
        case .pause: morceaux.append("\(cote) est en pause")
        case .erreur: morceaux.append("\(cote) est bloqué et attend une intervention")
        case .horsHoraires: morceaux.append("\(cote) est hors horaires ; il repasse \(repasse() ?? "à son prochain passage")")
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

    /// Préfixe d'une question déposée en saisie (repli v1.1). Mode direct (v4) : le bureau traite tout de suite
    /// ce qui est demandé ; les envois restent des décisions à glisser dans l'app.
    public static let prefixeQuestion = "Question du patron (depuis l’app). Traite-la tout de suite et réponds-lui dans le résumé, en deux ou trois phrases à dire à voix haute ; tout envoi à un tiers reste une décision à valider dans l’app : "
    /// Ancien préfixe (lecture seule), encore présent dans l'historique des saisies.
    static let anciensPrefixes = ["Question du patron (depuis l’assistant vocal de l’iPhone). Réponds-lui dans le résumé, en deux ou trois phrases à dire à voix haute ; ne prépare et n’envoie rien : "]

    /// Texte affiché pendant que le bureau traite (mode direct : pas de « lecture seule », pas de « prochain passage »).
    public static let enTraitement = "Le bureau s’en occupe…"
    /// Réponse pas encore arrivée : elle viendra ici (événement du PC ou notification).
    public static let reponseAVenir = "Le bureau s’en occupe ; la réponse s’affichera ici."

    /// Préfixe de question trouvé en tête du texte (actuel ou ancien).
    static func prefixe(de texte: String) -> String? {
        ([prefixeQuestion] + anciensPrefixes).first { texte.hasPrefix($0) }
    }

    public static func texteQuestion(_ question: String, agent: AgentBureau? = nil) -> String {
        texteQuestion(question, nomAgent: agent?.nom)
    }

    public static func texteQuestion(_ question: String, nomAgent: String?) -> String {
        let pour = nomAgent.map { "[Pour l’agent \($0)] " } ?? ""
        return prefixeQuestion + pour + "« \(question.trimmingCharacters(in: .whitespacesAndNewlines)) »"
    }

    public static func estQuestion(_ texte: String) -> Bool { prefixe(de: texte) != nil }

    /// Nom de l'agent visé par une question déposée (lu dans son texte).
    public static func nomAgent(_ texte: String) -> String? {
        guard let prefixe = prefixe(de: texte) else { return nil }
        let reste = texte.dropFirst(prefixe.count)
        let marque = "[Pour l’agent "
        guard reste.hasPrefix(marque), let fin = reste.firstIndex(of: "]") else { return nil }
        return String(reste[reste.index(reste.startIndex, offsetBy: marque.count)..<fin])
    }

    public static func agent(_ texte: String) -> AgentBureau? { nomAgent(texte).flatMap(AgentBureau.init(nom:)) }

    /// La question telle que le patron l'a posée (sans le préfixe), pour l'historique.
    public static func questionSeule(_ texte: String) -> String {
        guard let prefixe = prefixe(de: texte) else { return texte }
        var q = String(texte.dropFirst(prefixe.count))
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
        async let agents = try? api.agentsEtAssistant()
        async let journal = try? api.journal(limite: 12)
        let (e, s, a, j) = await (etat, saisies, agents, journal)
        guard e != nil || s != nil || a != nil else { return nil }
        if let a, !a.agents.isEmpty, let cle = cleMemoire { MemoireAgents.partage.garder(a.agents, pour: cle) }
        return EtatBureau(etat: e ?? a?.assistant, saisies: s ?? [], agents: a?.agents ?? [], journal: j ?? [])
    }

    /// Connexion chaude avant une question (écran de conversation ouvert, première lettre tapée) : la requête
    /// qui suit ne paie ni la résolution du nom ni la poignée de main TLS.
    public func prechauffer() async {
        _ = try? await api.etatAssistant()
    }

    /// Clé de la mémoire des agents : l'adresse du PC (les API de démonstration et de test ne sont pas gardées).
    private var cleMemoire: String? { (api as? ClientAPI)?.base.absoluteString }

    /// Agents du PC, gardés une minute : la voix ne paie pas un aller-retour avant chaque question.
    private func agentsConnus() async -> [AgentPC] {
        if let cle = cleMemoire, let connus = MemoireAgents.partage.agents(pour: cle) { return connus }
        let agents = (try? await api.agentsPC()) ?? []
        if !agents.isEmpty, let cle = cleMemoire { MemoireAgents.partage.garder(agents, pour: cle) }
        return agents
    }

    /// Agent du PC visé : nommé par le modèle vocal, cité dans la question, ou déduit du sujet.
    public func resoudreAgent(question: String, demande: String?) async -> (id: String?, nom: String?) {
        let agents = await agentsConnus()
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
    /// Mode direct (v4) : le PC la traite tout de suite ; les envois deviennent des décisions à glisser.
    /// `conversation` : même fil pour les questions qui se suivent (« et pour la Villa Morel ? »), comme un chat ;
    /// `contexte` : derniers échanges, pour un PC qui ne garde pas le fil lui-même.
    /// `fichiers` : photos ou PDF joints au message (v1.10) ; la question peut alors être vide.
    public func poser(_ question: String, agentId: String? = nil, nomAgent: String? = nil,
                      conversation: String? = nil, contexte: String? = nil,
                      fichiers: [FormulaireMultipart.Fichier] = []) async throws(ErreurAPI) -> QuestionPosee {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty || !fichiers.isEmpty else { throw .refus("La question est vide.") }
        var requetes: [Requete] = []
        if let agentId {
            requetes.append(.questionAgent(agentId, question: q, conversation: conversation, contexte: contexte, fichiers: fichiers))
        }
        requetes.append(.questionClaude(q, agent: agentId, conversation: conversation, contexte: contexte, fichiers: fichiers))
        // Une route qui a reçu la question ne doit jamais être doublée par la suivante : on ne passe à la route
        // suivante (puis au repli /saisie) que si la précédente n'existe pas (404 / 405).
        for requete in requetes {
            let data: Data
            do throws(ErreurAPI) {
                data = try await api.envoyer(requete)
            } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
                continue
            }
            guard var reponse = try? JSONDecoder().decode(ReponseAgent.self, from: data) else {
                // Reçue par le PC, réponse illisible : la question est partie, on ne la repose pas.
                return .enAttente(.saisie(id: nil, texte: q), message: nil)
            }
            if reponse.agent == nil { reponse.agent = agentId }
            switch reponse.statut {
            case .repondu where reponse.reponse != nil:
                return .reponse(reponse)
            case .erreur:
                throw .refus(reponse.message ?? "L’agent n’a pas pu répondre.")
            default:
                let message = reponse.message.flatMap { $0.isEmpty ? nil : $0 }
                if let id = reponse.questionId {
                    return .enAttente(.question(id: id, agent: reponse.agent), message: message)
                }
                return .enAttente(.saisie(id: nil, texte: q), message: message)
            }
        }
        let texte = Self.texteQuestion(q, nomAgent: nomAgent)
        let formulaire = FormulaireMultipart(champs: [Parametre("texte", texte)] + (agentId.map { [Parametre("agent", $0)] } ?? []),
                                             fichiers: fichiers)
        let reponse = try await api.charger(ReponseSimple.self, .saisie(formulaire))
        guard reponse.ok else { throw .refus(reponse.message ?? "Le PC n’a pas accepté la question.") }
        return .enAttente(.saisie(id: reponse.saisieId, texte: texte), message: nil)
    }

    /// Cadence de sondage : serrée au début (en mode direct, le PC répond souvent en quelques secondes), puis plus
    /// lâche. L'événement `reponse` du PC, quand il arrive, court-circuite l'attente (réponse affichée aussitôt).
    public static func intervalle(apres ecoule: Duration) -> Duration {
        if ecoule < .seconds(10) { return .milliseconds(400) }
        if ecoule < .seconds(30) { return .milliseconds(800) }
        return .milliseconds(1_500)
    }

    /// Attente longue proposée au PC (v1.8) : il peut garder `GET /questions/{id}` ouvert jusqu'à 20 s et répondre
    /// à l'instant où la réponse est prête.
    public static let attenteLongue = 20

    /// Attend la réponse d'une question v1.2 jusqu'à 3 min : `GET /questions/{id}?attendre=20` (relancé aussitôt
    /// si le PC a gardé la requête), sinon toutes les 0,4 s, puis 0,8 s, puis 1,5 s. Ensuite, l'événement `reponse`
    /// du PC ou la notification prennent le relais. Une question déposée en saisie n'est pas sondée : `verifier` est
    /// rappelé à chaque événement `maj saisies` du PC. `nil` : pas encore de réponse.
    /// `intervalle` : cadence fixe (tests).
    public func attendre(_ suivi: SuiviQuestion, delai: Duration = .seconds(180), intervalle: Duration? = nil) async -> ReponseAgent? {
        guard case .question = suivi else { return await verifier(suivi) }
        let debut = ContinuousClock.now
        let limite = debut + delai
        while ContinuousClock.now < limite, !Task.isCancelled {
            let avant = ContinuousClock.now
            if let r = await verifier(suivi, attente: Self.attenteLongue) { return r }
            // Le PC a gardé la requête ouverte (attente longue) : on la relance tout de suite, sans pause.
            if intervalle == nil, ContinuousClock.now - avant >= .milliseconds(1_500) { continue }
            try? await Task.sleep(for: intervalle ?? Self.intervalle(apres: ContinuousClock.now - debut))
        }
        return nil
    }

    /// Une seule vérification : la réponse est-elle arrivée ? `attente` : attente longue proposée au PC (secondes).
    public func verifier(_ suivi: SuiviQuestion, attente: Int? = nil) async -> ReponseAgent? {
        switch suivi {
        case .question(let id, let agent):
            let requete: Requete = attente.map { .suiviQuestion(id, attente: $0) } ?? .suiviQuestion(id)
            guard let data = try? await api.envoyer(requete),
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
    /// v1.6 : `mode: "direct"` (traiter tout de suite, comme une session ouverte), `conversation_id`, `contexte`.
    public static func questionClaude(_ question: String, agent: String? = nil, conversation: String? = nil,
                                      contexte: String? = nil, fichiers: [FormulaireMultipart.Fichier] = []) -> Requete {
        var corps = ["question": question, "mode": "direct"]
        if let agent { corps["agent"] = agent }
        if let conversation { corps["conversation_id"] = conversation }
        if let contexte, !contexte.isEmpty { corps["contexte"] = contexte }
        return Requete.corpsQuestion("\(prefixe)/assistant/question", corps: corps, fichiers: fichiers)
    }
}

/// Agents du PC déjà lus (par adresse du PC), valables une minute.
final class MemoireAgents: @unchecked Sendable {
    static let partage = MemoireAgents()
    private let verrou = NSLock()
    private var entrees: [String: (le: Date, agents: [AgentPC])] = [:]

    func agents(pour cle: String, age: TimeInterval = 60) -> [AgentPC]? {
        verrou.lock()
        defer { verrou.unlock() }
        guard let entree = entrees[cle], Date().timeIntervalSince(entree.le) < age else { return nil }
        return entree.agents
    }

    func garder(_ agents: [AgentPC], pour cle: String) {
        verrou.lock()
        defer { verrou.unlock() }
        entrees[cle] = (Date(), agents)
    }
}
