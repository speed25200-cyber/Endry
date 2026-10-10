import Foundation
import Observation

/// Tout ce que le patron a décidé ou transmis, et ce que le bureau en a fait (« Fait récemment »).
/// Rien ne disparaît sans trace : un Oui devient une ligne suivie jusqu'au résultat (fichier, envoi, erreur).
@MainActor
@Observable
public final class ModeleSuiviActions {
    public private(set) var actions: [ActionSuivie] = []
    public private(set) var chargement = false
    public private(set) var majLe: Date?
    /// Vrai quand le PC donne son compte rendu structuré (`GET /suivi`, v1.4) ; sinon rapprochement du journal.
    public private(set) var comptesRendusPC = false
    /// Dernière action passée à « Fait » ou « Erreur » (toast, retour haptique).
    public private(set) var derniereIssue: ActionSuivie?
    /// Chaque action qui aboutit (fait ou erreur), une fois : son compte rendu entre dans la conversation.
    @ObservationIgnored public var surIssue: (@MainActor (ActionSuivie) -> Void)?

    @ObservationIgnored private let api: any EndryAPI
    @ObservationIgnored private let fichier: URL?
    /// `GET /suivi` a répondu 404/405 à ce moment : retentée après 5 min, ou au retour au premier plan.
    @ObservationIgnored private var routePCAbsenteLe: Date?
    /// Écritures enchaînées : la dernière version reste sur le disque.
    @ObservationIgnored private var sauvegarde: Task<Void, Never>?

    static let conservation: TimeInterval = 30 * 24 * 3600
    static let maximum = 200

    public init(api: any EndryAPI, fichier: URL? = nil) {
        self.api = api
        self.fichier = fichier
        if let fichier, let data = try? Data(contentsOf: fichier),
           let liste = try? Self.decodeur.decode([ActionSuivie].self, from: data) {
            actions = liste
            elaguer()
        }
    }

    // MARK: Lecture

    /// Les 48 dernières heures, la plus récente d'abord.
    public func recents(heures: Double = 48, maintenant: Date = Date()) -> [ActionSuivie] {
        actions.filter { $0.le >= maintenant.addingTimeInterval(-heures * 3600) }
    }

    public func pour(chantier id: String) -> [ActionSuivie] { actions.filter { $0.chantierId == id } }
    public func action(_ id: String) -> ActionSuivie? { actions.first { $0.id == id } }
    public func pour(reference: String) -> ActionSuivie? { actions.first { $0.reference == reference } }

    /// Actions encore attendues du bureau (transmises ou en cours, depuis moins de 3 jours).
    public var enAttente: [ActionSuivie] {
        actions.filter { !$0.etat.termine && $0.etat != .corrige && $0.le > Date().addingTimeInterval(-3 * 24 * 3600) }
    }

    /// Tout ce qui est parti chez un tiers, du plus récent au plus ancien.
    public var envois: [(action: ActionSuivie, envoi: EnvoiEffectue)] {
        actions.flatMap { a in a.envois.map { (a, $0) } }
    }

    // MARK: Gestes

    /// Oui / Non / Corriger / Répondre : la décision ne disparaît plus sans laisser de trace.
    public func enregistrer(_ geste: ActionDecision, carte: Carte, reponse: String?, consignes: String? = nil, le: Date = Date()) {
        let id = "D:" + carte.reference
        let etat: EtatSuivi = switch geste {
        case .non: .ecarte
        case .corriger: .corrige
        case .oui, .repondre: .transmis
        }
        var a = ActionSuivie(id: id, nature: carte.estQuestion ? .question : .decision, reference: carte.reference,
                             titre: carte.titre, genre: carte.genre, outil: carte.outil, geste: geste.rawValue, le: le,
                             chantierId: carte.chantierId, envoiTiersPrevu: carte.partChezUnTiers,
                             destinatairesPrevus: carte.destinataires, consignes: consignes, reponse: reponse, etat: etat)
        var etapes = [EtapeSuivi(id: "geste", le: le, qui: "vous", type: "geste", titre: Self.titreGeste(geste, question: carte.estQuestion),
                                 detail: consignes)]
        if let reponse, !reponse.isEmpty {
            etapes.append(EtapeSuivi(id: "reponse", le: le.addingTimeInterval(1), qui: "bureau", type: "reponse",
                                     titre: "Réponse du bureau", detail: reponse))
        }
        a.etapes = etapes
        inserer(a)
    }

    /// Saisie, question ou envoi terrain transmis (l'identifiant vient du PC quand il le donne).
    public func enregistrer(saisie id: String?, texte: String, nature: NatureSuivi = .saisie, chantierId: String? = nil,
                            reponse: String? = nil, decisionPreparee: String? = nil, le: Date = Date()) {
        let cle = id.map { "S:" + $0 } ?? "S:" + UUID().uuidString
        var a = ActionSuivie(id: cle, nature: nature, saisieId: id, titre: Self.titreSaisie(texte), geste: "transmis", le: le,
                             chantierId: chantierId, reponse: reponse, decisionPreparee: decisionPreparee)
        // Le bureau a déjà préparé la suite (facture de régie, offre demandée) : elle attend le Oui du patron.
        if decisionPreparee != nil { a.etat = .fait }
        a.etapes = [EtapeSuivi(id: "geste", le: le, qui: "vous", type: "geste",
                               titre: nature == .question ? "Question posée" : "Transmis au bureau", detail: texte)]
        if let reponse, !reponse.isEmpty {
            a.etapes.append(EtapeSuivi(id: "reponse", le: le.addingTimeInterval(1), qui: "bureau", type: "reponse",
                                       titre: "Réponse du bureau", detail: reponse))
        }
        inserer(a)
    }

    // MARK: Rafraîchissement

    /// Relit le compte rendu du PC (v1.4), sinon le journal ; complète avec l'historique des saisies.
    public func rafraichir(saisies: [SaisieHistorique] = []) async {
        guard !chargement else { return }
        chargement = true
        defer { chargement = false }
        let avant = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0.etat) })

        var misAJour = actions
        if routePCAbsenteLe.map({ Date().timeIntervalSince($0) >= CapacitesServeur.delaiRetour }) ?? true {
            do throws(ErreurAPI) {
                let suivis = try await api.suivis(limite: 60)
                comptesRendusPC = true
                routePCAbsenteLe = nil
                for s in suivis { fusionner(s, dans: &misAJour) }
            } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
                routePCAbsenteLe = Date()
                comptesRendusPC = false
            } catch {
                // Réseau : on garde l'état connu.
            }
        }
        // Le journal complète toute action sans compte rendu du PC (réponses aux questions et aux saisies :
        // `type: "reponse"`, `saisie_id`), même quand `GET /suivi` existe.
        if misAJour.contains(where: { $0.source != .pc && !$0.etat.termine }), let journal = try? await api.journal(limite: 80) {
            misAJour = misAJour.map { RapprochementSuivi.appliquer(journal: journal, a: $0) }
        }
        // Toujours la liste fraîche des saisies : l'historique passé par l'écran peut être vide ou ancien.
        let fraiches = (try? await api.saisies()) ?? saisies
        importer(fraiches.isEmpty ? saisies : fraiches, dans: &misAJour)

        actions = misAJour.sorted { $0.le > $1.le }
        majLe = Date()
        elaguer()
        // Ce qui vient d'aboutir : un signe pour le patron.
        let issues = actions.filter { a in
            guard let e = avant[a.id] else { return false }
            return !e.termine && (a.etat == .fait || a.etat == .erreur)
        }
        if let issue = issues.first { derniereIssue = issue }
        for issue in issues.reversed() { surIssue?(issue) }
        sauvegarder()
    }

    public func oublierIssue() { derniereIssue = nil }

    /// Retour au premier plan : les routes du PC marquées absentes sont retentées tout de suite.
    public func reessayerRoutes() {
        routePCAbsenteLe = nil
    }

    private func fusionner(_ s: SuiviPC, dans liste: inout [ActionSuivie]) {
        let index = liste.firstIndex { a in
            (s.reference != nil && a.reference == s.reference) || (s.saisieId != nil && a.saisieId == s.saisieId)
        }
        if let index {
            liste[index] = RapprochementSuivi.appliquer(pc: s, a: liste[index])
            liste[index].majLe = Date()
        } else {
            // Geste fait ailleurs (notification, montre, PC) : il apparaît aussi.
            liste.append(RapprochementSuivi.action(depuis: s))
        }
    }

    /// Saisies des 48 dernières heures : suivies aussi (les questions et envois terrain passent par là).
    private func importer(_ saisies: [SaisieHistorique], dans liste: inout [ActionSuivie]) {
        let limite = Date().addingTimeInterval(-48 * 3600)
        for s in saisies {
            if let i = liste.firstIndex(where: { $0.saisieId == s.id }) {
                liste[i] = RapprochementSuivi.appliquer(saisie: s, a: liste[i])
                continue
            }
            guard let cree = s.cree.flatMap(DateEndry.lire), cree >= limite else { continue }
            // Une saisie enregistrée sans identifiant (ancien PC) : même texte, même minute.
            if let i = liste.firstIndex(where: { $0.saisieId == nil && $0.nature != .decision
                                                 && $0.etapes.first?.detail == s.texte && abs($0.le.timeIntervalSince(cree)) < 600 }) {
                liste[i].saisieId = s.id
                liste[i] = RapprochementSuivi.appliquer(saisie: s, a: liste[i])
                continue
            }
            var a = ActionSuivie(id: "S:" + s.id, nature: s.question ? .question : Self.nature(s.texte), saisieId: s.id,
                                 titre: Self.titreSaisie(s.texte), geste: "transmis", le: cree, agent: s.agent)
            a.etapes = [EtapeSuivi(id: "geste", le: cree, qui: "vous", type: "geste",
                                   titre: s.question ? "Question posée" : "Transmis au bureau", detail: s.texte)]
            liste.append(RapprochementSuivi.appliquer(saisie: s, a: a))
        }
    }

    // MARK: Interne

    private func inserer(_ a: ActionSuivie) {
        actions.removeAll { $0.id == a.id }
        actions.insert(a, at: 0)
        elaguer()
        sauvegarder()
    }

    private func elaguer() {
        let limite = Date().addingTimeInterval(-Self.conservation)
        actions = Array(actions.filter { $0.le >= limite }.prefix(Self.maximum))
    }

    private func sauvegarder() {
        guard let fichier else { return }
        let actions = actions
        let precedente = sauvegarde
        sauvegarde = Task.detached(priority: .utility) {
            await precedente?.value
            guard let data = try? Self.encodeur.encode(actions) else { return }
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

    nonisolated static func titreGeste(_ geste: ActionDecision, question: Bool) -> String {
        switch geste {
        case .oui: "Vous avez validé"
        case .non: "Vous avez écarté"
        case .corriger: "Vous avez demandé une correction"
        case .repondre: question ? "Vous avez répondu" : "Vous avez répondu"
        }
    }

    /// Titre lisible d'une saisie : sans l'en-tête technique « [Pour l'agent X] ».
    nonisolated static func titreSaisie(_ texte: String) -> String {
        var t = texte
        if t.hasPrefix("["), let fin = t.firstIndex(of: "]") { t = String(t[t.index(after: fin)...]) }
        for prefixe in ["Question du patron :", "Question du patron"] where t.trimmingCharacters(in: .whitespaces).hasPrefix(prefixe) {
            t = String(t.trimmingCharacters(in: .whitespaces).dropFirst(prefixe.count))
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if let point = t.firstIndex(where: { ".\n".contains($0) }), t.distance(from: t.startIndex, to: point) > 12 {
            t = String(t[..<point])
        }
        return t.count > 90 ? String(t.prefix(88)) + "…" : (t.isEmpty ? "Saisie" : t)
    }

    nonisolated static func nature(_ texte: String) -> NatureSuivi {
        let t = texte.lowercased()
        if ["régie", "bon de livraison", "relevé 3d", "journée"].contains(where: { t.contains($0) }) && t.contains("depuis l’iphone") {
            return .terrain
        }
        return BureauClaude.estQuestion(texte) ? .question : .saisie
    }
}
