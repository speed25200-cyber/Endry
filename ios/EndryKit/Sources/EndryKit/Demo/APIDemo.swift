import Foundation

/// Serveur factice en mémoire : sert les fixtures et simule les décisions.
/// Utilisé par le mode démo, les aperçus SwiftUI et les tests. Aucune donnée ne sort de l'appareil.
public actor APIDemo: EndryAPI {
    public static let base = URL(string: "https://demo.endry.invalid")!

    private var restantes: [[String: Any]]
    private let latence: Duration
    public private(set) var journal: [String] = []

    public init(latence: Duration = .milliseconds(450)) {
        self.latence = latence
        let objet = (try? JSONSerialization.jsonObject(with: Fixtures.donnees(.decisions))) as? [String: Any]
        restantes = objet?["decisions"] as? [[String: Any]] ?? []
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

        if route(.post, "app/api/v1/session") != nil {
            return Fixtures.donnees(.session)
        }
        if route(.get, "app/api/v1/accueil") != nil {
            return remplacerDecisions(dans: .accueil)
        }
        if route(.get, "app/api/v1/decisions") != nil {
            return remplacerDecisions(dans: .decisions)
        }
        if let c = route(.post, "app/api/v1/decisions/*/*") {
            return try agir(reference: c[0], action: c[1], corps: requete.corps)
        }
        if route(.get, "app/api/v1/chantiers") != nil {
            let etape = requete.parametres.first { $0.nom == "etape" }?.valeur ?? "tous"
            return filtrerChantiers(etape: etape)
        }
        if let c = route(.get, "app/api/v1/chantiers/*") {
            return try detailChantier(id: c[0])
        }
        if route(.get, "app/api/v1/argent") != nil {
            return Fixtures.donnees(.argent)
        }
        if route(.post, "app/api/v1/saisie") != nil {
            return json(["ok": true, "message": "Transmis au bureau. L’assistant préparera la suite."])
        }
        if route(.post, "app/api/v1/actualiser") != nil {
            return json(["ok": true, "resultat": "Données à jour (démo)."])
        }
        if route(.post, "app/api/v1/appareils") != nil {
            return json(["ok": true])
        }
        if let c = route(.get, "app/doc/*/*") {
            return PDFDemo.document(
                titre: "\(c[0].capitalized) \(c[1])",
                lignes: ["Endry SA - 1541 Bussy FR", "Mode démonstration", "Montant et détails : voir l’app."]
            )
        }
        throw .serveur(statut: 404, message: "Route inconnue en mode démo : \(requete.chemin)")
    }

    /// Remet les décisions dans l'état initial (bouton « Recommencer la démo »).
    public func reinitialiser() {
        let objet = (try? JSONSerialization.jsonObject(with: Fixtures.donnees(.decisions))) as? [String: Any]
        restantes = objet?["decisions"] as? [[String: Any]] ?? []
        journal.removeAll()
    }

    // MARK: - Simulation

    private func agir(reference: String, action: String, corps: Requete.Corps?) throws(ErreurAPI) -> Data {
        guard let actionDecision = ActionDecision(rawValue: action) else {
            throw .serveur(statut: 404, message: "Action inconnue.")
        }
        guard let index = restantes.firstIndex(where: { ($0["reference"] as? String) == reference }) else {
            throw .refus("Cette décision a déjà été traitée.")
        }
        var consignes: String?
        if case .json(let data) = corps, let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            consignes = (objet["consignes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let estQuestion = reference.uppercased().hasPrefix("Q-")
        if (actionDecision == .corriger || (estQuestion && actionDecision == .oui)), (consignes ?? "").isEmpty {
            throw .refus("Indiquez vos consignes.")
        }
        restantes.remove(at: index)
        let message: String
        switch (actionDecision, estQuestion) {
        case (_, true): message = "Réponse transmise à l’assistant."
        case (.oui, _): message = "Validé. L’assistant s’en occupe."
        case (.non, _): message = "Écarté. Rien ne sera envoyé."
        case (.corriger, _): message = "Consignes transmises : une nouvelle version sera proposée."
        }
        return json(["ok": true, "message": message, "decisions_restantes": restantes.count])
    }

    private func remplacerDecisions(dans nom: Fixtures.Nom) -> Data {
        guard var objet = (try? JSONSerialization.jsonObject(with: Fixtures.donnees(nom))) as? [String: Any] else {
            return Fixtures.donnees(nom)
        }
        objet["decisions"] = restantes
        return json(objet)
    }

    private func filtrerChantiers(etape: String) -> Data {
        guard var objet = (try? JSONSerialization.jsonObject(with: Fixtures.donnees(.chantiers))) as? [String: Any] else {
            return Fixtures.donnees(.chantiers)
        }
        if etape != "tous", let liste = objet["chantiers"] as? [[String: Any]] {
            objet["chantiers"] = liste.filter { ($0["etape"] as? String) == etape }
        }
        return json(objet)
    }

    private func detailChantier(id: String) throws(ErreurAPI) -> Data {
        guard let details = (try? JSONSerialization.jsonObject(with: Fixtures.donnees(.chantiersDetails))) as? [String: Any],
              let dossier = details[id] else {
            throw .serveur(statut: 404, message: "Chantier introuvable.")
        }
        return json(dossier)
    }

    private func json(_ objet: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: objet)) ?? Data("{}".utf8)
    }
}
