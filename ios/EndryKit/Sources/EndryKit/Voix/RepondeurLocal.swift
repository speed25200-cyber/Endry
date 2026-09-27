import Foundation

/// Moteur de repli : répond localement aux questions simples à partir des données (cache ou API),
/// et transmet tout le reste à l'assistant du PC sous forme de saisie.
public enum RepondeurLocal {
    public enum Reponse: Equatable, Sendable {
        /// Réponse à dire à voix haute, avec éventuellement une carte à afficher.
        case dire(String, carte: ExecuteurOutils.Effet)
        /// Demande de travail : à transmettre à l'assistant du PC (`POST /saisie`).
        case transmettre(String)
    }

    public struct Donnees: Sendable {
        public var accueil: Accueil?
        public var argent: Argent?
        public var chantiers: [Dossier]

        public init(accueil: Accueil?, argent: Argent?, chantiers: [Dossier]) {
            self.accueil = accueil
            self.argent = argent
            self.chantiers = chantiers
        }
    }

    public static func repondre(_ question: String, avec d: Donnees) -> Reponse {
        let q = normaliser(question)
        let mots = Set(q.split(separator: " ").map(String.init))

        // Actions (préparer, mettre, envoyer, créer…) : toujours pour l'assistant du PC.
        let verbesAction = ["prepare", "preparer", "mets", "mettre", "deplace", "deplacer", "cree", "creer", "envoie", "envoyer",
                            "ajoute", "ajouter", "note", "noter", "facture", "commande", "commander", "planifie", "planifier"]
        if let premier = q.split(separator: " ").first.map(String.init), verbesAction.contains(premier) {
            return .transmettre(question)
        }

        if q.contains("doit") || q.contains("doivent") || q.contains("nous devons") == false && q.contains("dette") {
            if let groupe = meilleurClient(q, groupes: d.argent?.encaisser.parClient ?? d.accueil?.encaisser.parClient ?? []) {
                let n = groupe.factures.count
                let retard = groupe.retardMax > 0 ? ", la plus ancienne a \(groupe.retardMax) jours de retard" : ", rien n’est encore échu"
                return .dire("\(groupe.client) vous doit \(FormatSuisse.parle(groupe.montant)), \(n) facture\(n > 1 ? "s" : "")\(retard). Suivi seulement, aucune relance sans votre demande.",
                             carte: groupe.factures.first.map { .afficherFacture($0.factureId) } ?? .aucun)
            }
        }

        if q.contains("ou en est") || q.contains("ou on en est") || (mots.contains("chantier") && (q.contains("etat") || q.contains("avance"))) {
            if let chantier = meilleurChantier(q, dans: d.chantiers) {
                var phrase = "\(chantier.titre) : étape \(chantier.etapeLibelle.lowercased())"
                if let dates = Planning.libelleDates(chantier) { phrase += ", travaux le \(dates)" }
                if chantier.decisionEnAttente { phrase += ". Une décision vous attend" }
                return .dire(phrase + ".", carte: .afficherChantier(chantier.id))
            }
        }

        if q.contains("m attend") || q.contains("aujourd hui") || q.contains("programme") || q.contains("ma journee") || q.contains("quoi de neuf") {
            guard let a = d.accueil else { return .dire("Je n’ai pas encore les données du jour.", carte: .aucun) }
            var morceaux: [String] = []
            let envois = a.decisions.filter(\.exigeGlisser).count
            morceaux.append(a.decisions.isEmpty ? "Rien à décider, tout roule"
                            : "\(a.decisions.count) décision\(a.decisions.count > 1 ? "s" : "") à prendre\(envois > 0 ? ", dont \(envois) envoi\(envois > 1 ? "s" : "") à un client" : "")")
            if !a.chantiers7Jours.isEmpty {
                morceaux.append("\(a.chantiers7Jours.count) chantier\(a.chantiers7Jours.count > 1 ? "s" : "") cette semaine : " +
                                a.chantiers7Jours.prefix(3).map { $0.client ?? $0.titre }.joined(separator: ", "))
            }
            morceaux.append("\(FormatSuisse.parle(a.encaisser.total)) à encaisser")
            if a.payer.totalSemaine > 0 { morceaux.append("\(FormatSuisse.parle(a.payer.totalSemaine)) à payer dans les 7 jours") }
            return .dire(morceaux.joined(separator: ". ") + ".", carte: a.decisions.first.map { .afficherDecision($0.reference) } ?? .aucun)
        }

        if q.contains("payer") || q.contains("paiement") {
            guard let p = d.argent?.payer ?? d.accueil?.payer else { return .transmettre(question) }
            return .dire("\(FormatSuisse.parle(p.totalSemaine)) à payer cette semaine, \(FormatSuisse.parle(p.total)) au total. Les paiements se signent dans l’e-banking.", carte: .aucun)
        }

        if q.contains("decision") || q.contains("a decider") || q.contains("valider") {
            guard let a = d.accueil else { return .transmettre(question) }
            if a.decisions.isEmpty { return .dire("Rien à décider. Tout roule.", carte: .aucun) }
            let titres = a.decisions.prefix(3).map(\.titre).joined(separator: " ; ")
            return .dire("\(a.decisions.count) décisions : \(titres).", carte: .afficherDecision(a.decisions[0].reference))
        }

        return .transmettre(question)
    }

    // MARK: - Correspondances

    static func normaliser(_ s: String) -> String {
        let sansAccents = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_CH"))
        let lettres = sansAccents.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(lettres).split(separator: " ").joined(separator: " ")
    }

    private static let motsVides: Set<String> = ["le", "la", "les", "de", "du", "des", "et", "a", "au", "aux", "m", "l", "d", "sa", "ag",
                                                 "combien", "nous", "doit", "doivent", "ou", "en", "est", "on", "chantier", "chantiers",
                                                 "gerance", "regie", "famille", "mme", "mr", "m", "monsieur", "madame", "commune", "ppe"]

    private static func jetons(_ s: String) -> Set<String> {
        Set(normaliser(s).split(separator: " ").map(String.init).filter { $0.count > 1 && !motsVides.contains($0) })
    }

    static func meilleurClient(_ question: String, groupes: [GroupeClient]) -> GroupeClient? {
        let q = jetons(question)
        let notes = groupes.map { g in (g, jetons(g.client).intersection(q).count) }
        guard let meilleur = notes.max(by: { $0.1 < $1.1 }), meilleur.1 > 0 else { return nil }
        return meilleur.0
    }

    static func meilleurChantier(_ question: String, dans dossiers: [Dossier]) -> Dossier? {
        let q = jetons(question)
        let notes = dossiers.map { d -> (Dossier, Int) in
            let cible = jetons([d.titre, d.client, d.lieu ?? ""].joined(separator: " "))
            // « du Mont » doit trouver « Le Mont-sur-Lausanne » : correspondance par préfixe.
            let n = q.filter { mot in cible.contains { $0 == mot || ($0.hasPrefix(mot) && mot.count >= 4) } }.count
            return (d, n)
        }
        guard let meilleur = notes.max(by: { ($0.1, $0.0.etapeIndex < 6 ? 1 : 0) < ($1.1, $1.0.etapeIndex < 6 ? 1 : 0) }), meilleur.1 > 0 else { return nil }
        return meilleur.0
    }
}

extension FormatSuisse {
    /// Montant à dire à voix haute : « 10’028 francs », « 642 francs 35 ».
    public static func parle(_ montant: Double) -> String {
        let p = parties(montant)
        let francs = p.francs.replacingOccurrences(of: separateurMilliers, with: " ")
        return p.centimes == "00" || montant >= 1_000 ? "\(francs) francs" : "\(francs) francs \(p.centimes)"
    }
}
