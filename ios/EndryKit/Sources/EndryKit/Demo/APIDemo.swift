import Foundation

/// Serveur factice en mémoire (contrat v1.1) : sert les fixtures et simule décisions, saisies, pause et appareils.
/// Utilisé par le mode démo, les aperçus SwiftUI et les tests. Aucune donnée ne sort de l'appareil.
public actor APIDemo: EndryAPI {
    public static let base = URL(string: "https://demo.endry.invalid")!

    private var restantes: [[String: Any]]
    private var saisies: [[String: Any]]
    private var appareils: [[String: Any]]
    private var pause = false
    /// Questions posées à Claude : instant de dépôt (la réponse « arrive » après `delaiClaude`).
    private var questions: [String: ContinuousClock.Instant] = [:]
    /// v1.2 : agents, journal et questions directes aux agents.
    private var agentsDemo: [[String: Any]]
    private var journalDemo: [[String: Any]]
    private var questionsAgents: [String: (agent: String, question: String, depot: ContinuousClock.Instant)] = [:]
    private let delaiClaude: Duration
    private let latence: Duration
    /// Tests : fait échouer `POST /actualiser` comme un Bexio indisponible.
    private let bexioIndisponible: Bool
    public private(set) var journal: [String] = []

    public init(latence: Duration = .milliseconds(450), bexioIndisponible: Bool = false, delaiClaude: Duration = .seconds(3)) {
        self.latence = latence
        self.delaiClaude = delaiClaude
        self.bexioIndisponible = bexioIndisponible
        restantes = Self.objet(.decisions)?["decisions"] as? [[String: Any]] ?? []
        saisies = Self.liste(.saisies)
        appareils = Self.liste(.appareils)
        agentsDemo = Self.objet(.agents)?["agents"] as? [[String: Any]] ?? []
        journalDemo = Self.objet(.journal)?["entrees"] as? [[String: Any]] ?? []
    }

    public nonisolated func urlAbsolue(_ chemin: String) -> URL? {
        URL(string: Self.base.absoluteString + (chemin.hasPrefix("/") ? chemin : "/" + chemin))
    }

    public func envoyer(_ requete: Requete) async throws(ErreurAPI) -> Data {
        if latence > .zero {
            try? await Task.sleep(for: latence)
        }
        journal.append("\(requete.methode.rawValue) \(requete.chemin)")
        let chemin = requete.chemin.split(separator: "?").first.map(String.init) ?? requete.chemin
        let morceaux = chemin.split(separator: "/").map(String.init)

        func route(_ methode: Requete.Methode, _ motif: String) -> [String]? {
            guard requete.methode == methode else { return nil }
            let attendu = motif.split(separator: "/").map(String.init)
            guard attendu.count == morceaux.count else { return nil }
            var captures: [String] = []
            for (a, m) in zip(attendu, morceaux) {
                if a == "*" { captures.append(m.removingPercentEncoding ?? m) } else if a != m { return nil }
            }
            return captures
        }

        if route(.post, "app/api/v1/session") != nil { return Fixtures.donnees(.session) }
        if route(.get, "app/api/v1/accueil") != nil { return accueil() }
        if route(.get, "app/api/v1/decisions") != nil {
            return json(["decisions": restantes, "decisions_autorisees": true])
        }
        if let c = route(.post, "app/api/v1/decisions/*/*") {
            return try agir(reference: c[0], action: c[1], corps: requete.corps)
        }
        if route(.get, "app/api/v1/chantiers") != nil {
            let etape = requete.parametres.first { $0.nom == "etape" }?.valeur ?? "tous"
            return filtrerChantiers(etape: etape)
        }
        if let c = route(.get, "app/api/v1/chantiers/*") { return try detailChantier(id: c[0]) }
        if route(.get, "app/api/v1/argent") != nil { return Fixtures.donnees(.argent) }
        if route(.post, "app/api/v1/saisie") != nil { return enregistrerSaisie(requete.corps) }
        if route(.get, "app/api/v1/saisies") != nil {
            avancerQuestions()
            return json(saisies)
        }
        if route(.post, "app/api/v1/actualiser") != nil {
            if bexioIndisponible { throw .bexioIndisponible }
            return json(["ok": true])
        }
        if route(.post, "app/api/v1/appareils") != nil { return json(["ok": true]) }
        if route(.get, "app/api/v1/appareils") != nil { return json(appareils) }
        if let c = route(.delete, "app/api/v1/appareils/*") {
            appareils.removeAll { ($0["id"] as? String) == c[0] }
            return json(["ok": true])
        }
        if route(.get, "app/api/v1/assistant/etat") != nil {
            return json(["pause": pause, "file": 2, "derniere_activite": "2026-09-27T12:40:00"])
        }
        if route(.post, "app/api/v1/assistant/pause") != nil { pause = true; return json(["ok": true, "pause": true]) }
        if route(.post, "app/api/v1/assistant/reprise") != nil { pause = false; return json(["ok": true, "pause": false]) }
        if route(.post, "app/api/v1/voix/session") != nil { return Fixtures.donnees(.sessionVoix) }
        // v1.2 : agents du bureau
        if route(.get, "app/api/v1/agents") != nil { avancerQuestionsAgents(); return json(["agents": agentsDemo]) }
        if let c = route(.get, "app/api/v1/agents/*/journal") { return json(["entrees": journalDemo.filter { ($0["agent"] as? String) == c[0] }]) }
        if route(.get, "app/api/v1/journal") != nil { avancerQuestionsAgents(); return json(["entrees": journalDemo]) }
        if let c = route(.post, "app/api/v1/agents/*/question") {
            guard agentsDemo.contains(where: { ($0["id"] as? String) == c[0] }) else { throw .serveur(statut: 404, message: "Agent inconnu.") }
            return deposerQuestion(agent: c[0], corps: requete.corps)
        }
        if route(.post, "app/api/v1/assistant/question") != nil {
            let question = Self.champ("question", dans: requete.corps) ?? ""
            let agent = Self.champ("agent", dans: requete.corps) ?? AgentBureau.detecter(question)?.rawValue ?? "secretariat"
            return deposerQuestion(agent: agent, corps: requete.corps)
        }
        if let c = route(.get, "app/api/v1/questions/*") { return suivreQuestion(c[0]) }
        if let c = route(.get, "app/doc/*/*") {
            return PDFDemo.document(
                titre: "\(c[0].capitalized) \(c[1])",
                lignes: ["Endry SA - 1541 Bussy FR", "Mode démonstration", "Montant et détails : voir l’app."]
            )
        }
        throw .serveur(statut: 404, message: "Route inconnue en mode démo : \(requete.chemin)")
    }

    /// Remet la démo dans son état initial (« Recommencer la démo »).
    public func reinitialiser() {
        restantes = Self.objet(.decisions)?["decisions"] as? [[String: Any]] ?? []
        saisies = Self.liste(.saisies)
        appareils = Self.liste(.appareils)
        pause = false
        questions.removeAll()
        questionsAgents.removeAll()
        agentsDemo = Self.objet(.agents)?["agents"] as? [[String: Any]] ?? []
        journalDemo = Self.objet(.journal)?["entrees"] as? [[String: Any]] ?? []
        journal.removeAll()
    }

    // MARK: - Simulation

    private func accueil() -> Data {
        guard var objet = Self.objet(.accueil) else { return Fixtures.donnees(.accueil) }
        objet["decisions"] = restantes
        objet["pause"] = pause
        return json(objet)
    }

    private func agir(reference: String, action: String, corps: Requete.Corps?) throws(ErreurAPI) -> Data {
        guard let actionDecision = ActionDecision(rawValue: action) else {
            throw .serveur(statut: 404, message: "Action inconnue.")
        }
        if pause { throw .refus("L’assistant est en pause.") }
        guard let index = restantes.firstIndex(where: { ($0["reference"] as? String) == reference }) else {
            throw .refus("Cette décision a déjà été traitée.")
        }
        var consignes: String?
        if case .json(let data) = corps, let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            consignes = (objet["consignes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let estQuestion = reference.uppercased().hasPrefix("Q-")
        if estQuestion, actionDecision != .repondre {
            throw .refus("Cette question attend une réponse écrite.")
        }
        if [.corriger, .repondre].contains(actionDecision), (consignes ?? "").isEmpty {
            throw .refus("Indiquez vos consignes.")
        }
        restantes.remove(at: index)
        let message = switch actionDecision {
        case .repondre: "Réponse transmise à l’assistant."
        case .oui: "Validé. L’assistant s’en occupe."
        case .non: "Écarté. Rien ne sera envoyé."
        case .corriger: "Consignes transmises : une nouvelle version sera proposée."
        }
        return json(["ok": true, "message": message, "decisions_restantes": restantes.count])
    }

    private func enregistrerSaisie(_ corps: Requete.Corps?) -> Data {
        var texte = ""
        var photos = 0
        if case .multipart(let formulaire) = corps {
            texte = formulaire.champs.first { $0.nom == "texte" }?.valeur ?? ""
            photos = formulaire.fichiers.count
        }
        let id = "S-\(143 + saisies.count)"
        saisies.insert(["id": id, "cree": "2026-09-27T12:45:00", "texte": texte, "photos": photos, "statut": "transmis"], at: 0)
        if BureauClaude.estQuestion(texte) { questions[id] = .now }
        return json(["ok": true, "message": "Transmis au bureau. L’assistant préparera la suite.", "saisie_id": id])
    }

    /// Claude « réfléchit » puis répond dans le résumé de la saisie.
    private func avancerQuestions() {
        for (id, depot) in questions {
            guard let index = saisies.firstIndex(where: { ($0["id"] as? String) == id }) else { continue }
            let ecoule = ContinuousClock.now - depot
            if ecoule >= delaiClaude {
                let texte = saisies[index]["texte"] as? String ?? ""
                let question = BureauClaude.questionSeule(texte)
                let signature = BureauClaude.agent(texte).map { "\($0.nom) : " } ?? ""
                saisies[index]["statut"] = "traite"
                saisies[index]["resume"] = signature + Self.reponseClaude(question)
                questions[id] = nil
            } else if ecoule >= delaiClaude / 2 {
                saisies[index]["statut"] = "en_cours"
            }
        }
    }

    // MARK: v1.2

    private func deposerQuestion(agent: String, corps: Requete.Corps?) -> Data {
        let question = Self.champ("question", dans: corps) ?? ""
        let id = "Q-\(900 + questionsAgents.count)"
        questionsAgents[id] = (agent, question, .now)
        mettreAgent(agent, etat: "occupe", tache: "Cherche : « \(question) »")
        journalDemo.insert(["id": "J-\(3000 + journalDemo.count)", "horodatage": "2026-09-27T12:46:00", "agent": agent,
                            "type": "question", "titre": "Question du patron", "detail": question], at: 0)
        return json(["statut": "en_cours", "question_id": id, "agent": agent])
    }

    private func suivreQuestion(_ id: String) -> Data {
        avancerQuestionsAgents()
        guard let q = questionsAgents[id] else {
            if let repondue = journalDemo.first(where: { ($0["question_id"] as? String) == id }) {
                return json(["statut": "repondu", "question_id": id, "agent": repondue["agent"] ?? "",
                             "reponse": repondue["detail"] ?? "", "sources": [["type": "email", "libelle": "Boîte info@"]]])
            }
            return json(["statut": "erreur", "question_id": id, "message": "Question inconnue."])
        }
        return json(["statut": "en_cours", "question_id": id, "agent": q.agent])
    }

    /// Les agents « répondent » après `delaiClaude` : réponse au journal, agent de nouveau libre.
    private func avancerQuestionsAgents() {
        for (id, q) in questionsAgents where ContinuousClock.now - q.depot >= delaiClaude {
            questionsAgents[id] = nil
            journalDemo.insert(["id": "J-\(3000 + journalDemo.count)", "horodatage": "2026-09-27T12:47:00", "agent": q.agent,
                                "type": "reponse", "titre": "Réponse au patron", "detail": Self.reponseClaude(q.question),
                                "question_id": id], at: 0)
            mettreAgent(q.agent, etat: "libre", tache: nil)
        }
    }

    private func mettreAgent(_ id: String, etat: String, tache: String?) {
        guard let index = agentsDemo.firstIndex(where: { ($0["id"] as? String) == id }) else { return }
        agentsDemo[index]["etat"] = etat
        agentsDemo[index]["tache"] = tache ?? NSNull()
    }

    static func champ(_ nom: String, dans corps: Requete.Corps?) -> String? {
        guard case .json(let data) = corps, let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (objet[nom] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Réponses fictives de Claude, cohérentes avec les données de démonstration.
    static func reponseClaude(_ question: String) -> String {
        let q = question.lowercased()
        if q.contains("gander") || q.contains("adoucisseur") {
            return "Mme Gander attend toujours la visite pour l’adoucisseur. Je propose jeudi à 8 h ; rien n’est parti, la proposition est dans vos décisions si vous voulez l’envoyer."
        }
        if q.contains("morel") || q.contains("citerne") {
            return "Villa Morel : la citerne est dégazée, le démontage est prévu lundi. Aucun blocage, l’équipe est prévenue."
        }
        if q.contains("dubois") || q.contains("facture") {
            return "La facture RE-00416 de la régie Dubois est prête : 6 h 30 et un déplacement. Elle attend votre validation dans les décisions."
        }
        if q.contains("mail") || q.contains("courriel") {
            return "Trois e-mails ce matin : Mme Rey sur la variante WC, la régie Dubois pour un débouchage et un fournisseur pour une livraison. Rien d’urgent."
        }
        return "Mode démonstration : sur le PC, Claude répondrait ici à partir des dossiers, de Bexio et des e-mails."
    }

    private func filtrerChantiers(etape: String) -> Data {
        guard var objet = Self.objet(.chantiers) else { return Fixtures.donnees(.chantiers) }
        if etape != "tous", let liste = objet["chantiers"] as? [[String: Any]] {
            objet["chantiers"] = liste.filter { ($0["etape"] as? String) == etape }
        }
        return json(objet)
    }

    private func detailChantier(id: String) throws(ErreurAPI) -> Data {
        guard let details = Self.objet(.chantiersDetails), let dossier = details[id] else {
            throw .serveur(statut: 404, message: "Chantier introuvable.")
        }
        return json(dossier)
    }

    private static func objet(_ nom: Fixtures.Nom) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Fixtures.donnees(nom))) as? [String: Any]
    }

    private static func liste(_ nom: Fixtures.Nom) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: Fixtures.donnees(nom))) as? [[String: Any]] ?? []
    }

    private func json(_ objet: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: objet)) ?? Data("{}".utf8)
    }
}
