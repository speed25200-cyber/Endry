import Foundation

/// Point du briefing : une ligne affichée, une phrase dite.
public struct PointBriefing: Sendable, Hashable, Identifiable {
    public var icone: String
    public var titre: String
    public var detail: String
    public var phrase: String

    public var id: String { titre + detail }
}

/// Briefing du matin : chantiers du jour, décisions, argent, offres, entretiens. En lecture seule :
/// il se lit (écran, notification) ou s'écoute (Siri, CarPlay, assistant), sans jamais rien valider.
public struct Briefing: Sendable, Hashable {
    public var titre: String
    public var points: [PointBriefing]
    public var ouverture: String
    public var cloture: String

    /// Texte à dire, d'un seul tenant.
    public var texteParle: String {
        ([ouverture] + points.map(\.phrase) + [cloture]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Corps court pour la notification du matin (3 lignes au plus).
    public var resumeNotification: String {
        points.prefix(3).map { "\($0.titre) \($0.detail)".trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }

    /// `masquerMontants` : mode devant le client, ou lecture sur un iPhone verrouillé.
    /// Les montants d'achat fournisseurs ne sont jamais dits.
    public static func composer(
        accueil: Accueil?, semaine: [Semaine], argent: Argent?, entretiens: [Entretien] = [], offresASuivre: [OffreASuivre] = [],
        pause: Bool? = nil, prenom: String? = nil, masquerMontants: Bool = false, le date: Date = Date()
    ) -> Briefing {
        var points: [PointBriefing] = []
        let p = prenom?.trimmingCharacters(in: .whitespaces).nonVide
        let heure = Calendar(identifier: .gregorian).component(.hour, from: date)
        let salut = heure >= 17 ? "Bonsoir" : "Bonjour"
        let ouverture = "\(salut)\(p.map { ", \($0)" } ?? ""). Nous sommes \(DateEndry.longue(date))."

        // Chantiers du jour
        let chantiers = semaine.isEmpty ? (accueil?.chantiers7Jours ?? []) : semaine
        let duJour = chantiers.filter { s in
            guard let d = s.dateDebut else { return false }
            let f = s.dateFin ?? d
            return DateEndry.jours(de: d, a: date) >= 0 && DateEndry.jours(de: date, a: f) >= 0
        }
        if duJour.isEmpty {
            points.append(.init(icone: "hammer", titre: "Chantiers", detail: "aucun prévu aujourd’hui",
                                phrase: "Aucun chantier n’est prévu aujourd’hui au planning."))
        } else {
            let noms = duJour.prefix(4).map { s in [s.client ?? s.titre, s.lieu].compactMap { $0 }.joined(separator: " à ") }
            let debutent = duJour.filter { s in s.dateDebut.map { DateEndry.memeJour($0, date) } ?? false }
            let suffixe = debutent.isEmpty ? "" : " \(debutent.count == 1 ? "L’un commence" : "\(debutent.count) commencent") aujourd’hui."
            points.append(.init(icone: "hammer.fill", titre: "Chantiers", detail: noms.joined(separator: " · "),
                                phrase: "\(duJour.count == 1 ? "Un chantier" : "\(duJour.count) chantiers") aujourd’hui : "
                                    + Self.liste(noms) + "." + suffixe))
        }

        // Décisions
        if let decisions = accueil?.decisions, !decisions.isEmpty {
            let envois = decisions.filter(\.partChezUnTiers).count
            let questions = decisions.filter(\.estQuestion).count
            var detail = "\(decisions.count) en attente"
            var phrase = "\(decisions.count == 1 ? "Une décision vous attend" : "\(decisions.count) décisions vous attendent")"
            var precisions: [String] = []
            if envois > 0 { precisions.append(envois == 1 ? "un envoi à un tiers" : "\(envois) envois à des tiers") }
            if questions > 0 { precisions.append(questions == 1 ? "une question de l’assistant" : "\(questions) questions de l’assistant") }
            if !precisions.isEmpty {
                detail += " · " + precisions.joined(separator: ", ")
                phrase += ", dont " + Self.liste(precisions)
            }
            points.append(.init(icone: "checkmark.seal.fill", titre: "Décisions", detail: detail, phrase: phrase + "."))
        } else if accueil != nil {
            points.append(.init(icone: "checkmark.seal", titre: "Décisions", detail: "rien en attente", phrase: "Aucune décision en attente."))
        }

        // Argent (encaissements clients ; jamais de montants fournisseurs)
        if let encaisser = argent?.encaisser ?? accueil?.encaisser, encaisser.total > 0 {
            let retard = encaisser.anciennete.plus30
            if masquerMontants {
                let n = encaisser.factures.count
                points.append(.init(icone: "banknote", titre: "À encaisser", detail: "\(n) facture\(n > 1 ? "s" : "") ouverte\(n > 1 ? "s" : "")",
                                    phrase: "\(n) facture\(n > 1 ? "s" : "") client\(n > 1 ? "s sont ouvertes" : " est ouverte")."))
            } else {
                var phrase = "À encaisser : \(FormatSuisse.montantParle(encaisser.total))"
                var detail = FormatSuisse.chfArrondi(encaisser.total)
                if retard > 0 {
                    phrase += ", dont \(FormatSuisse.montantParle(retard)) à plus de 30 jours"
                    detail += " · \(FormatSuisse.chfArrondi(retard)) > 30 j"
                }
                points.append(.init(icone: "banknote.fill", titre: "À encaisser", detail: detail, phrase: phrase + ". Suivi seulement, aucune relance."))
            }
        }
        let payer = argent?.payer ?? accueil?.payer
        if let n = payer?.cetteSemaine.count, n > 0 {
            points.append(.init(icone: "calendar.badge.clock", titre: "À payer", detail: "\(n) échéance\(n > 1 ? "s" : "") cette semaine",
                                phrase: "\(n == 1 ? "Une facture fournisseur arrive" : "\(n) factures fournisseurs arrivent") à échéance cette semaine."))
        }

        // Offres à suivre
        if !offresASuivre.isEmpty {
            let noms = offresASuivre.prefix(3).map(\.offre.client)
            let n = offresASuivre.count
            points.append(.init(icone: "doc.text.magnifyingglass", titre: "Offres sans réponse", detail: noms.joined(separator: " · "),
                                phrase: "\(n == 1 ? "Une offre attend" : "\(n) offres attendent") une réponse depuis plus de deux semaines : "
                                    + Self.liste(Array(noms)) + "."))
        }

        // Entretiens
        let aPlanifier = entretiens.filter { e in
            guard e.peutProposer, let d = e.dateEcheance else { return false }
            return DateEndry.jours(de: date, a: d) <= 31
        }
        if !aPlanifier.isEmpty {
            let n = aPlanifier.count
            points.append(.init(icone: "wrench.and.screwdriver.fill", titre: "Entretiens", detail: "\(n) à planifier d’ici un mois",
                                phrase: "\(n == 1 ? "Un entretien est" : "\(n) entretiens sont") à planifier d’ici un mois."))
        }

        if pause ?? accueil?.pause ?? false {
            points.append(.init(icone: "pause.circle.fill", titre: "Assistant", detail: "en pause",
                                phrase: "L’assistant du bureau est en pause : vos décisions s’exécutent, il ne prépare rien de nouveau."))
        }

        return Briefing(titre: "Briefing du \(DateEndry.longue(date))", points: points, ouverture: ouverture, cloture: "Bonne journée.")
    }

    /// « A, B et C ».
    public static func enPhrase(_ elements: [String]) -> String { liste(elements) }

    static func liste(_ elements: [String]) -> String {
        switch elements.count {
        case 0: ""
        case 1: elements[0]
        default: elements.dropLast().joined(separator: ", ") + " et " + elements[elements.count - 1]
        }
    }
}

extension String {
    var nonVide: String? { isEmpty ? nil : self }
}

extension FormatSuisse {
    /// Montant à dire à voix haute : « 42 300 francs » (sans apostrophes, que la synthèse lit mal).
    public static func montantParle(_ montant: Double) -> String {
        let arrondi = Int64(montant.rounded())
        let texte = grouper(abs(arrondi)).replacingOccurrences(of: "’", with: " ").replacingOccurrences(of: "'", with: " ")
        return "\(arrondi < 0 ? "moins " : "")\(texte) franc\(abs(arrondi) > 1 ? "s" : "")"
    }
}
