import Foundation
import Observation

/// Un message du fil « Conversation » avec l'assistant du bureau (écrit ou dicté, ou venu de l'assistant vocal).
public struct MessageConversation: Codable, Identifiable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case patron
        case assistant
        /// Information de l'app (demande transmise, hors horaires…), discrète.
        case note
    }

    public enum Etat: String, Codable, Sendable {
        case envoye
        /// L'assistant travaille : la réponse est attendue.
        case attente
        /// Plus sondé : la réponse viendra au prochain passage (événement du PC, notification).
        case differe
        case recu
        case erreur
    }

    public enum Nature: String, Codable, Sendable {
        /// Question : le bureau répond (et fait ce qui est demandé ; les envois restent à glisser).
        case question
        /// Travail à préparer (offre, courrier…) : rien ne part chez un tiers sans le geste du patron.
        case demande
    }

    public enum Source: String, Codable, Sendable {
        case ecrit
        case dictee
        case voix
    }

    public var id: String
    public var role: Role
    public var texte: String
    public var le: Date
    public var conversation: String
    public var nature: Nature
    public var source: Source
    public var etat: Etat
    /// Domaine qui répond (« Secrétariat »), quand il est connu.
    public var agent: String?
    /// Suivi de la réponse : question v1.2 (`GET /questions/{id}`) ou saisie v1.1.
    public var questionId: String?
    public var saisieId: String?
    public var texteEnvoye: String?
    /// Décision préparée par l'assistant, à valider à l'écran.
    public var decisionReference: String?
    /// Message du PC pendant l'attente (hors horaires…).
    public var message: String?
    /// Question partie sans réseau : renvoyée d'elle-même au retour du réseau.
    public var aRenvoyer: Bool?

    public init(id: String = UUID().uuidString, role: Role, texte: String, le: Date = Date(), conversation: String,
                nature: Nature = .question, source: Source = .ecrit, etat: Etat = .recu, agent: String? = nil) {
        self.id = id
        self.role = role
        self.texte = texte
        self.le = le
        self.conversation = conversation
        self.nature = nature
        self.source = source
        self.etat = etat
        self.agent = agent
    }

    /// Identifiant de la réponse à un message du patron.
    public static func idReponse(_ id: String) -> String { "R:" + id }

    var suivi: SuiviQuestion? {
        if let questionId { return .question(id: questionId, agent: agent) }
        if let texteEnvoye { return .saisie(id: saisieId, texte: texteEnvoye) }
        return nil
    }
}

/// Le fil de conversation avec l'assistant du bureau, partagé par l'écran « Conversation » et l'assistant vocal :
/// même fil (`conversation_id`), même historique, comme une session Claude ouverte sur le PC.
///
/// Les questions partent en mode direct (lecture seule) ; les demandes partent en saisie et se suivent dans
/// « Fait récemment ». Rien ne part chez un tiers depuis ici : les envois restent des décisions validées à l'écran.
@MainActor
@Observable
public final class ModeleConversation {
    public private(set) var messages: [MessageConversation] = []
    public private(set) var identifiant: String
    /// Dernière réponse arrivée du bureau (l'app le signale si la conversation n'est pas ouverte).
    public private(set) var derniereArrivee: MessageConversation?
    /// Domaine choisi pour les questions écrites (`nil` : l'assistant choisit).
    public var agentId: String?
    public var agentNom: String?

    @ObservationIgnored private let bureau: BureauClaude?
    @ObservationIgnored private let transmettre: (@MainActor (String) async -> ModeleSaisie.ResultatDemande)?
    @ObservationIgnored private let fichier: URL?
    @ObservationIgnored private var suivis: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var derniereActivite: Date
    @ObservationIgnored private var sauvegarde: Task<Void, Never>?

    /// Nouveau fil après 30 min de silence (le PC repart d'une page blanche).
    public static let silence: TimeInterval = 30 * 60
    static let maximum = 300

    public init(bureau: BureauClaude?, transmettre: (@MainActor (String) async -> ModeleSaisie.ResultatDemande)? = nil,
                fichier: URL? = nil) {
        self.bureau = bureau
        self.transmettre = transmettre
        self.fichier = fichier
        identifiant = UUID().uuidString
        derniereActivite = .distantPast
        if let fichier, let data = try? Data(contentsOf: fichier),
           let enregistre = try? Self.decodeur.decode(Enregistrement.self, from: data) {
            messages = enregistre.messages
            identifiant = enregistre.identifiant
            derniereActivite = messages.last?.le ?? .distantPast
            agentId = enregistre.agentId
            agentNom = enregistre.agentNom
        }
    }

    // MARK: Lecture

    /// L'assistant travaille sur au moins une question.
    public var reflechit: Bool { messages.contains { $0.role == .assistant && $0.etat == .attente } }

    public func reponse(a id: String) -> MessageConversation? {
        messages.first { $0.id == MessageConversation.idReponse(id) }
    }

    /// Trois derniers échanges du fil en cours, pour un PC qui ne garde pas le fil lui-même.
    public var contexte: String? {
        let fil = messages.filter { $0.conversation == identifiant }
        var paires: [String] = []
        for m in fil where m.role == .patron && m.nature == .question {
            guard let r = fil.first(where: { $0.id == MessageConversation.idReponse(m.id) }), r.etat == .recu else { continue }
            paires.append("Q : \(m.texte)\nR : \(r.texte)")
        }
        return paires.isEmpty ? nil : paires.suffix(3).joined(separator: "\n")
    }

    /// Fil en cours ; nouveau fil après 30 min de silence.
    public func conversationCourante(maintenant: Date = Date()) -> String {
        if maintenant.timeIntervalSince(derniereActivite) > Self.silence, messages.contains(where: { $0.conversation == identifiant }) {
            identifiant = UUID().uuidString
        }
        derniereActivite = maintenant
        return identifiant
    }

    public func nouvelleConversation() {
        identifiant = UUID().uuidString
        derniereActivite = .distantPast
        sauvegarder()
    }

    // MARK: Fils

    /// Un fil de conversation passé : sa première question, quand il a commencé, combien de messages.
    public struct Fil: Identifiable, Hashable, Sendable {
        public let id: String
        public let debut: Date
        public let fin: Date
        public let titre: String
        public let nombre: Int
    }

    /// Le fil en cours, seul affiché à l'écran : les fils précédents ne s'accumulent plus dessous.
    public var filCourant: [MessageConversation] { messages.filter { $0.conversation == identifiant } }

    /// Fils précédents, du plus récent au plus ancien.
    public var filsPrecedents: [Fil] {
        var ordre: [String] = []
        var groupes: [String: [MessageConversation]] = [:]
        for m in messages where m.conversation != identifiant {
            if groupes[m.conversation] == nil { ordre.append(m.conversation) }
            groupes[m.conversation, default: []].append(m)
        }
        return ordre.compactMap { id -> Fil? in
            guard let fil = groupes[id], let premier = fil.first, let dernier = fil.last else { return nil }
            let titre = fil.first { $0.role == .patron }?.texte ?? premier.texte
            return Fil(id: id, debut: premier.le, fin: dernier.le, titre: titre, nombre: fil.count)
        }
        .sorted { $0.fin > $1.fin }
    }

    /// Rouvre un fil précédent : la suite de la conversation repart dans ce fil.
    public func reprendre(_ id: String) {
        guard messages.contains(where: { $0.conversation == id }) else { return }
        identifiant = id
        derniereActivite = Date()
        sauvegarder()
    }

    public func choisirAgent(id: String?, nom: String?) {
        agentId = id
        agentNom = nom
        sauvegarder()
    }

    // MARK: Envoi (écran « Conversation »)

    /// Question (lecture seule, mode direct) ou demande (saisie) écrite ou dictée.
    public func envoyer(_ texte: String, nature: MessageConversation.Nature = .question,
                        source: MessageConversation.Source = .ecrit) async {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return }
        switch nature {
        case .question:
            let id = consignerQuestion(propre, source: source, agent: agentNom)
            await poser(id, question: propre)
        case .demande:
            await demander(propre, source: source)
        }
    }

    /// Réessayer une question restée en erreur.
    public func relancer(_ id: String) async {
        guard let m = messages.first(where: { $0.id == id }), m.role == .patron, m.nature == .question else { return }
        await poser(id, question: m.texte)
    }

    private func poser(_ id: String, question: String) async {
        guard let bureau else {
            repondre(id, texte: "Connectez d’abord l’app au bureau.", etat: .erreur)
            return
        }
        attendre(id, suivi: nil, message: nil)
        let conversation = messages.first { $0.id == id }?.conversation ?? identifiant
        do {
            let posee = try await bureau.poser(question, agentId: agentId, nomAgent: agentNom,
                                               conversation: conversation, contexte: contexte)
            switch posee {
            case .reponse(let r):
                repondre(id, avec: r)
            case .enAttente(let suivi, let message):
                attendre(id, suivi: suivi, message: message)
                if message == nil { suivre(id) } else { differer(id, message: message) }
            }
        } catch where error.estProblemeReseau {
            // Rien n'est perdu : la question repart toute seule dès que le réseau revient.
            if let i = messages.firstIndex(where: { $0.id == id }) { messages[i].aRenvoyer = true }
            attendre(id, suivi: nil, message: nil)
            differer(id, message: "Pas de réseau : la question partira dès le retour du réseau.")
        } catch {
            repondre(id, texte: "La question n’est pas partie. \(error.message)", etat: .erreur)
        }
    }

    /// Questions gardées faute de réseau : elles partent maintenant (retour du réseau, retour au premier plan).
    public func renvoyerEnAttente() async {
        let ids = messages.filter { $0.role == .patron && $0.aRenvoyer == true }.map(\.id)
        for id in ids {
            guard let i = messages.firstIndex(where: { $0.id == id }) else { continue }
            messages[i].aRenvoyer = nil
            await poser(id, question: messages[i].texte)
        }
    }

    /// Questions encore gardées faute de réseau.
    public var enAttenteReseau: Int { messages.filter { $0.aRenvoyer == true }.count }

    private func demander(_ texte: String, source: MessageConversation.Source) async {
        let envoi = agentNom.map { "[Pour l’agent \($0)] " + texte } ?? texte
        guard let transmettre else {
            consignerDemande(texte, envoye: envoi, source: source, resultat: .refusee("Connectez d’abord l’app au bureau."))
            return
        }
        let id = consignerDemande(texte, envoye: envoi, source: source, resultat: nil)
        noter(id, resultat: await transmettre(envoi))
    }

    // MARK: Consignation (assistant vocal)

    /// Question posée (écrite, dictée ou dite à l'assistant vocal) : elle entre dans le fil.
    @discardableResult
    public func consignerQuestion(_ texte: String, source: MessageConversation.Source, agent: String? = nil,
                                  le: Date = Date()) -> String {
        var m = MessageConversation(role: .patron, texte: texte, le: le, conversation: conversationCourante(maintenant: le),
                                    nature: .question, source: source, etat: .envoye)
        m.agent = agent
        ajouter(m)
        return m.id
    }

    /// La réponse est attendue (`suivi` : comment la relire plus tard).
    public func attendre(_ id: String, suivi: SuiviQuestion?, message: String?) {
        var r = reponseOuNouvelle(id)
        r.etat = .attente
        r.message = message
        switch suivi {
        case .question(let questionId, let agent)?:
            r.questionId = questionId
            if let agent, r.agent == nil { r.agent = AgentBureau(rawValue: agent)?.nom ?? r.agent }
        case .saisie(let saisieId, let texte)?:
            r.saisieId = saisieId
            r.texteEnvoye = texte
        case nil:
            break
        }
        remplacer(r)
    }

    /// Plus de sondage : la réponse viendra avec un événement du PC (`verifierEnAttente`) ou une notification.
    public func differer(_ id: String, message: String?) {
        guard var r = messages.first(where: { $0.id == MessageConversation.idReponse(id) }), r.etat != .recu else { return }
        r.etat = .differe
        r.message = message ?? BureauClaude.reponseAVenir
        remplacer(r)
    }

    public func repondre(_ id: String, avec r: ReponseAgent) {
        let texte: String
        let etat: MessageConversation.Etat
        if r.statut == .repondu, let t = r.reponse, !t.isEmpty {
            texte = t
            etat = .recu
        } else {
            texte = r.message ?? "L’assistant n’a pas pu traiter la question sur le PC."
            etat = .erreur
        }
        repondre(id, texte: texte, etat: etat, agent: r.agent.map { AgentBureau(rawValue: $0)?.nom ?? $0 },
                 decision: r.decisionReference)
    }

    public func repondre(_ id: String, texte: String, etat: MessageConversation.Etat = .recu, agent: String? = nil,
                         decision: String? = nil) {
        var r = reponseOuNouvelle(id)
        r.texte = texte
        r.etat = etat
        r.le = Date()
        r.message = nil
        if let agent { r.agent = agent }
        if let decision { r.decisionReference = decision }
        remplacer(r)
        if etat == .recu, r.role == .assistant { derniereArrivee = r }
        suivis[id]?.cancel()
        suivis[id] = nil
    }

    /// Demande de travail (écrite, dictée ou dite à l'assistant vocal) : elle entre dans le fil avec son issue.
    @discardableResult
    public func consignerDemande(_ texte: String, envoye: String? = nil, source: MessageConversation.Source,
                                 resultat: ModeleSaisie.ResultatDemande?) -> String {
        var m = MessageConversation(role: .patron, texte: texte, conversation: conversationCourante(), nature: .demande,
                                    source: source, etat: .envoye)
        m.agent = agentNom
        m.texteEnvoye = envoye ?? texte
        ajouter(m)
        if let resultat { noter(m.id, resultat: resultat) }
        return m.id
    }

    private func noter(_ id: String, resultat: ModeleSaisie.ResultatDemande) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        let note: String
        let etat: MessageConversation.Etat
        switch resultat {
        case .transmise:
            note = "Transmis au bureau. L’assistant prépare ; vous suivez l’avancement ici et dans « Fait récemment ». Rien ne part chez un tiers sans votre Oui."
            etat = .recu
        case .gardee:
            note = "Pas de réseau : la demande est gardée sur l’iPhone et partira toute seule."
            etat = .differe
        case .refusee(let raison):
            note = "La demande n’est pas partie. \(raison)"
            etat = .erreur
        }
        messages[i].etat = etat == .erreur ? .erreur : .envoye
        remplacer(MessageConversation(id: MessageConversation.idReponse(id), role: .note, texte: note,
                                      conversation: messages[i].conversation, nature: .demande, etat: etat))
    }

    // MARK: Le bureau parle de lui-même

    /// Compte rendu d'une demande ou d'un geste, question du bureau : dans le fil, comme un message de
    /// l'assistant (une seule fois par `cle` ; mis à jour si le texte change). Comme une session ouverte avec Claude.
    public func recevoirDuBureau(cle: String, texte: String, agent: String? = nil, decision: String? = nil,
                                 erreur: Bool = false, le: Date = Date()) {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return }
        let id = "B:" + cle
        if var existant = messages.first(where: { $0.id == id }) {
            guard existant.texte != propre else { return }
            existant.texte = propre
            existant.etat = erreur ? .erreur : .recu
            remplacer(existant)
            return
        }
        var m = MessageConversation(id: id, role: .assistant, texte: propre, le: le,
                                    conversation: conversationCourante(maintenant: le), etat: erreur ? .erreur : .recu,
                                    agent: agent)
        m.decisionReference = decision
        ajouter(m)
    }

    /// Compte rendu d'une action suivie qui vient d'aboutir.
    public func recevoir(issue a: ActionSuivie) {
        recevoirDuBureau(cle: "S:" + a.id, texte: Self.compteRendu(a), agent: a.agent,
                         decision: a.decisionPreparee, erreur: a.etat == .erreur)
    }

    /// Question que le bureau pose au patron (carte `Q-…`) : elle entre dans le fil ; on y répond ici ou sur la carte.
    public func recevoir(questionDuBureau carte: Carte) {
        guard carte.estQuestion else { return }
        var texte = "**Question du bureau** (\(carte.reference))\n\n\(carte.titre)"
        if let detail = carte.texte?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty, detail != carte.titre {
            texte += "\n\n" + detail
        } else if !carte.motif.isEmpty, carte.motif != carte.titre {
            texte += "\n\n" + carte.motif
        }
        recevoirDuBureau(cle: "Q:" + carte.reference, texte: texte, decision: carte.reference)
    }

    nonisolated static func compteRendu(_ a: ActionSuivie) -> String {
        let tete = a.etat == .erreur ? "**Pas abouti** — \(a.titre)" : "**Fait** — \(a.titre)"
        var lignes = [tete]
        let resultat = a.ligneResultat.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resultat.isEmpty, resultat != a.titre { lignes.append(resultat) }
        let fichiers = a.fichiers.map(\.nom)
        if !fichiers.isEmpty { lignes.append("Documents : " + fichiers.joined(separator: ", ")) }
        return lignes.joined(separator: "\n\n")
    }

    // MARK: Réponses tardives

    /// Réponses arrivées depuis (événement `reponse` ou `maj saisies` du PC, retour au premier plan).
    public func verifierEnAttente() async {
        guard let bureau else { return }
        for r in messages where r.role == .assistant && (r.etat == .attente || r.etat == .differe) {
            let id = String(r.id.dropFirst(2))
            guard suivis[id] == nil, let suivi = r.suivi, let resultat = await bureau.verifier(suivi) else { continue }
            repondre(id, avec: resultat)
        }
    }

    /// Sonde la réponse (1 s pendant 20 s, puis 2 s jusqu'à 3 min), puis passe la main aux événements du PC.
    private func suivre(_ id: String) {
        guard let bureau, suivis[id] == nil,
              let suivi = messages.first(where: { $0.id == MessageConversation.idReponse(id) })?.suivi else { return }
        suivis[id] = Task { [weak self] in
            let resultat = await bureau.attendre(suivi)
            guard !Task.isCancelled, let self else { return }
            self.suivis[id] = nil
            if let resultat { self.repondre(id, avec: resultat) } else { self.differer(id, message: nil) }
        }
    }

    /// Efface tout le fil (déconnexion, « Effacer la conversation »).
    public func effacer() {
        suivis.values.forEach { $0.cancel() }
        suivis.removeAll()
        messages.removeAll()
        identifiant = UUID().uuidString
        derniereActivite = .distantPast
        guard let fichier else { return }
        try? FileManager.default.removeItem(at: fichier)
        // Une écriture encore en route ne doit pas faire revenir le fil effacé.
        let precedente = sauvegarde
        sauvegarde = Task.detached(priority: .utility) {
            await precedente?.value
            try? FileManager.default.removeItem(at: fichier)
        }
    }

    // MARK: Interne

    private func reponseOuNouvelle(_ id: String) -> MessageConversation {
        if let r = messages.first(where: { $0.id == MessageConversation.idReponse(id) }) { return r }
        let question = messages.first { $0.id == id }
        var r = MessageConversation(id: MessageConversation.idReponse(id), role: .assistant, texte: "",
                                    conversation: question?.conversation ?? identifiant,
                                    nature: question?.nature ?? .question, etat: .attente)
        r.agent = question?.agent
        return r
    }

    private func remplacer(_ m: MessageConversation) {
        if let i = messages.firstIndex(where: { $0.id == m.id }) {
            messages[i] = m
            sauvegarder()
        } else {
            ajouter(m)
        }
    }

    private func ajouter(_ m: MessageConversation) {
        messages.append(m)
        if messages.count > Self.maximum { messages.removeFirst(messages.count - Self.maximum) }
        sauvegarder()
    }

    private struct Enregistrement: Codable {
        var identifiant: String
        var messages: [MessageConversation]
        var agentId: String?
        var agentNom: String?
    }

    private func sauvegarder() {
        guard let fichier else { return }
        let enregistrement = Enregistrement(identifiant: identifiant, messages: messages, agentId: agentId, agentNom: agentNom)
        // Écritures enchaînées : la dernière version du fil est toujours celle qui reste sur le disque.
        let precedente = sauvegarde
        sauvegarde = Task.detached(priority: .utility) {
            await precedente?.value
            guard let data = try? Self.encodeur.encode(enregistrement) else { return }
            try? FileManager.default.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fichier, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    nonisolated static var encodeur: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    nonisolated static var decodeur: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// Texte d'une réponse découpé en blocs lisibles (le PC répond parfois en Markdown : titres, listes, gras).
public enum BlocTexte: Equatable, Sendable {
    case titre(String)
    case puce(String)
    case numero(String, String)
    case paragraphe(String)
    case code(String)

    public static func decouper(_ texte: String) -> [BlocTexte] {
        var blocs: [BlocTexte] = []
        var paragraphe: [String] = []
        var code: [String]?
        func finirParagraphe() {
            if !paragraphe.isEmpty { blocs.append(.paragraphe(paragraphe.joined(separator: "\n"))) }
            paragraphe.removeAll()
        }
        for brute in texte.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let ligne = brute.trimmingCharacters(in: .whitespaces)
            if ligne.hasPrefix("```") {
                if let lignes = code {
                    blocs.append(.code(lignes.joined(separator: "\n")))
                    code = nil
                } else {
                    finirParagraphe()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(brute)
                continue
            }
            if ligne.isEmpty {
                finirParagraphe()
            } else if ligne.hasPrefix("#") {
                finirParagraphe()
                blocs.append(.titre(ligne.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if let reste = ["- ", "* ", "• ", "– "].first(where: ligne.hasPrefix).map({ String(ligne.dropFirst($0.count)) }) {
                finirParagraphe()
                blocs.append(.puce(reste))
            } else if let point = ligne.firstIndex(where: { $0 == "." || $0 == ")" }),
                      ligne.distance(from: ligne.startIndex, to: point) <= 2,
                      ligne[..<point].allSatisfy(\.isNumber), !ligne[..<point].isEmpty,
                      ligne.index(after: point) < ligne.endIndex, ligne[ligne.index(after: point)] == " " {
                finirParagraphe()
                blocs.append(.numero(String(ligne[..<point]), ligne[ligne.index(point, offsetBy: 2)...].trimmingCharacters(in: .whitespaces)))
            } else {
                paragraphe.append(ligne)
            }
        }
        if let code { blocs.append(.code(code.joined(separator: "\n"))) }
        finirParagraphe()
        return blocs
    }

    /// Texte sans balises Markdown (pour l'écran vocal, qui s'allume au rythme de la voix).
    public static func sansBalises(_ texte: String) -> String {
        var t = texte
        for balise in ["**", "__", "`"] { t = t.replacingOccurrences(of: balise, with: "") }
        return t.components(separatedBy: "\n").map { ligne in
            guard ligne.hasPrefix("#") else { return ligne }
            return ligne.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }
}

extension ModeleConversation {
    /// Verbes d'une demande de travail (« Prépare l'offre… », « Peux-tu rédiger… »).
    nonisolated static let verbesDemande: Set<String> = [
        "prepare", "preparer", "prepares", "redige", "rediger", "ecris", "ecrire", "cree", "creer", "fais", "faire",
        "envoie", "envoyer", "commande", "commander", "planifie", "planifier", "ajoute", "ajouter", "reserve", "reserver",
        "organise", "organiser", "etablis", "etablir", "genere", "generer", "facture", "facturer", "transmets", "transmettre",
        "mets", "mettre", "programme", "programmer", "relance", "relancer", "note", "noter", "archive", "archiver",
    ]

    /// Question (lecture seule) ou demande de travail, d'après la tournure : le patron peut toujours changer.
    public nonisolated static func natureProbable(_ texte: String) -> MessageConversation.Nature {
        var mots = RepondeurLocal.normaliser(texte).split(separator: " ").map(String.init)
        // Formules de politesse et d'amorce : « peux-tu », « tu peux », « merci de », « il faut », « pourrais-tu ».
        let amorces: [[String]] = [["peux", "tu"], ["tu", "peux"], ["pourrais", "tu"], ["tu", "pourrais"], ["merci", "de"],
                                   ["il", "faut"], ["est", "ce", "que", "tu", "peux"], ["stp"], ["svp"], ["alors"], ["ok"]]
        var retire = true
        while retire {
            retire = false
            for a in amorces where mots.starts(with: a) {
                mots.removeFirst(a.count)
                retire = true
            }
        }
        guard let premier = mots.first else { return .question }
        return verbesDemande.contains(premier) ? .demande : .question
    }
}
