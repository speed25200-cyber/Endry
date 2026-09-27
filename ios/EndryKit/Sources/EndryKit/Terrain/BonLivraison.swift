import Foundation

/// Article lu sur un bon de livraison (sans prix : seuls la référence, la désignation et la quantité comptent).
public struct ArticleLivre: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var reference: String?
    public var designation: String
    public var quantite: Double?
    public var unite: String?

    public init(id: String = UUID().uuidString, reference: String? = nil, designation: String, quantite: Double? = nil, unite: String? = nil) {
        self.id = id
        self.reference = reference
        self.designation = designation
        self.quantite = quantite
        self.unite = unite
    }

    public var libelle: String {
        let q = quantite.map { "\(FormatQuantite.texte($0)) \(unite ?? "pce") " } ?? ""
        let r = reference.map { " (\($0))" } ?? ""
        return q + designation + r
    }
}

/// Bon de livraison fournisseur, photographié et lu sur l'iPhone.
public struct BonLivraison: Codable, Sendable, Hashable {
    public var fournisseur: String?
    public var numero: String?
    /// `AAAA-MM-JJ`
    public var date: String?
    public var commande: String?
    /// Référence de chantier écrite sur le bon (« Commission : Morel Epalinges »).
    public var commission: String?
    public var chantierId: String?
    public var chantier: String?
    public var articles: [ArticleLivre]
    /// Texte complet lu (le PC peut relire ce que l'iPhone a mal compris).
    public var texteLu: String

    public init(fournisseur: String? = nil, numero: String? = nil, date: String? = nil, commande: String? = nil, commission: String? = nil,
                chantierId: String? = nil, chantier: String? = nil, articles: [ArticleLivre] = [], texteLu: String = "") {
        self.fournisseur = fournisseur
        self.numero = numero
        self.date = date
        self.commande = commande
        self.commission = commission
        self.chantierId = chantierId
        self.chantier = chantier
        self.articles = articles
        self.texteLu = texteLu
    }

    public var manques: [String] {
        var m: [String] = []
        if chantierId == nil && (chantier ?? "").isEmpty { m.append("Choisissez le chantier.") }
        if (fournisseur ?? "").isEmpty { m.append("Indiquez le fournisseur.") }
        return m
    }

    public var resume: String {
        var p: [String] = []
        let de = fournisseur.map { " de \($0)" } ?? ""
        let num = numero.map { " n° \($0)" } ?? ""
        let le = date.map { " du \(DateEndry.courte($0))" } ?? ""
        p.append("Bon de livraison\(de)\(num)\(le).")
        if let chantier, !chantier.isEmpty { p.append("Chantier : \(chantier).") }
        if let commission, !commission.isEmpty { p.append("Commission écrite sur le bon : \(commission).") }
        if let commande, !commande.isEmpty { p.append("Commande : \(commande).") }
        if !articles.isEmpty {
            p.append("\(articles.count) article\(articles.count > 1 ? "s" : "") : " + articles.map(\.libelle).joined(separator: " ; ") + ".")
        }
        p.append("Rattacher au chantier et ajouter le matériel à refacturer ; rapprocher de la facture fournisseur quand elle arrive.")
        return p.joined(separator: " ")
    }

    public func envoi(pages: [FormulaireMultipart.Fichier], cle: String = UUID().uuidString) -> EnvoiTerrain {
        EnvoiTerrain(type: .bonLivraison, chantierId: chantierId, resume: resume, donnees: EnvoiTerrain.json(self), fichiers: pages, cle: cle)
    }
}

/// Lecture d'un bon de livraison à partir des lignes reconnues (Vision) : fournisseur, numéros, date, articles.
/// Les montants sont ignorés ; les lignes de totaux, de TVA et d'adresse ne deviennent jamais des articles.
public enum LecteurBonLivraison {
    /// Grossistes et fabricants courants du sanitaire-chauffage en Suisse romande.
    public static let fournisseursConnus = [
        "Meier Tobler", "Sanitas Troesch", "Debrunner Acifer", "Sanipex", "R. Nussbaum", "Nussbaum", "Richner", "Hoval",
        "Viessmann", "Buderus", "Geberit", "Tobler", "Walter Meier", "Gétaz Miauton", "Getaz Miauton", "Würth", "Wurth", "Hilti",
        "Ferroflex", "Elco", "Grundfos", "Stiebel Eltron", "Oertli", "Hansgrohe", "Laufen", "Similor", "KWC", "Jumbo", "Hornbach",
        "Bauhaus", "Coop Bau+Hobby", "Sabag", "Kiwa", "Condair",
    ]

    public static func analyser(lignes brutes: [String]) -> BonLivraison {
        let lignes = brutes.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let texte = lignes.joined(separator: "\n")
        var bon = BonLivraison(texteLu: texte)
        bon.fournisseur = fournisseur(dans: lignes)
        bon.numero = valeur(apres: ["bulletin de livraison", "bon de livraison", "lieferschein", "livraison n", "bl n", "bl", "n° bl"],
                            dans: lignes, motifValeur: "[A-Z0-9][A-Z0-9\\-/.]{3,}")
        bon.commande = valeur(apres: ["votre commande", "n° de commande", "commande n", "commande", "cde", "bestellung", "auftrag"],
                              dans: lignes, motifValeur: "[A-Z0-9][A-Z0-9\\-/.]{2,}")
        bon.commission = texteApres(["commission", "kommission", "chantier", "objet", "baustelle", "réf. client", "ref. client",
                                     "votre référence", "votre reference"], dans: lignes)
        bon.date = date(dans: lignes)
        bon.articles = articles(dans: lignes)
        return bon
    }

    static func fournisseur(dans lignes: [String]) -> String? {
        let tete = lignes.prefix(12).joined(separator: " ").lowercased()
        let tout = lignes.joined(separator: " ").lowercased()
        for zone in [tete, tout] {
            if let f = fournisseursConnus.first(where: { zone.contains($0.lowercased()) }) {
                return f == "Tobler" ? "Meier Tobler" : f
            }
        }
        // Repli : première ligne d'en-tête qui ressemble à une raison sociale.
        return lignes.prefix(8).first { l in
            let b = l.lowercased()
            return [" sa", " ag", " sàrl", " sarl", " gmbh"].contains { b.hasSuffix($0) || b.contains($0 + " ") }
        }
    }

    /// Valeur qui suit une étiquette, sur la même ligne ou la suivante.
    static func valeur(apres etiquettes: [String], dans lignes: [String], motifValeur: String) -> String? {
        for (i, ligne) in lignes.enumerated() {
            let bas = ligne.lowercased()
            for etiquette in etiquettes {
                guard let r = bas.range(of: etiquette) else { continue }
                let debut = ligne.index(ligne.startIndex, offsetBy: bas.distance(from: bas.startIndex, to: r.upperBound))
                let reste = String(ligne[debut...])
                let motif = "^[\\s°ºo.:#-]*(?:no|nr|n°)?[\\s.:#]*(\(motifValeur))"
                if let m = AnalyseurRegie.premier(motif, dans: reste), chiffreDans(m[1]) { return m[1] }
                if i + 1 < lignes.count, let m = AnalyseurRegie.premier("^(\(motifValeur))", dans: lignes[i + 1]), chiffreDans(m[1]) {
                    return m[1]
                }
            }
        }
        return nil
    }

    static func texteApres(_ etiquettes: [String], dans lignes: [String]) -> String? {
        for ligne in lignes {
            let bas = ligne.lowercased()
            for etiquette in etiquettes where bas.hasPrefix(etiquette) {
                let reste = ligne.dropFirst(etiquette.count).trimmingCharacters(in: CharacterSet(charactersIn: " :.-\t"))
                if reste.count >= 3 { return reste }
            }
        }
        return nil
    }

    static func date(dans lignes: [String]) -> String? {
        for ligne in lignes {
            if let m = AnalyseurRegie.premier("\\b(\\d{1,2})[./](\\d{1,2})[./](\\d{2,4})\\b", dans: ligne),
               let j = Int(m[1]), let mo = Int(m[2]), var a = Int(m[3]), (1...31).contains(j), (1...12).contains(mo) {
                if a < 100 { a += 2000 }
                return String(format: "%04d-%02d-%02d", a, mo, j)
            }
        }
        return nil
    }

    private static let unites = "pce|pces|pc|pcs|pièces?|st|stk|stück|m|ml|kg|l|rouleaux?|rlx|sacs?|boîtes?|bte|paquets?|pq|pa|ens|set|jeu|x"
    private static let lignesExclues = ["total", "tva", "mwst", "chf", "montant", "sous-total", "prix", "rabais", "net", "iban",
                                        "téléphone", "tel.", "tél", "e-mail", "www.", "@", "page", "signature", "livré par",
                                        "reçu par", "adresse", "case postale", "commission", "commande", "bulletin", "lieferschein"]

    /// Lignes d'articles : « 12 pce Raccord Mapress 22 mm 35012 » ou « 35012 Raccord Mapress 22 mm 12 pce ».
    static func articles(dans lignes: [String]) -> [ArticleLivre] {
        var resultat: [ArticleLivre] = []
        for ligne in lignes {
            let bas = ligne.lowercased()
            guard !lignesExclues.contains(where: { bas.contains($0) }) else { continue }
            guard ligne.contains(where: \.isLetter), ligne.count >= 6 else { continue }
            if let a = quantiteDevant(ligne) ?? quantiteDerriere(ligne) { resultat.append(a) }
        }
        return resultat
    }

    /// « 12 pce Raccord Mapress 22 mm » (référence éventuelle en tête : « 35012 12 pce … »).
    static func quantiteDevant(_ ligne: String) -> ArticleLivre? {
        let motif = "^(?:([0-9]{4,}[0-9A-Z.-]*)\\s+)?(\\d+(?:[.,]\\d+)?)\\s*(\(unites))\\.?\\s+(.{3,})$"
        guard let m = AnalyseurRegie.premier(motif, dans: ligne) else { return nil }
        return article(reference: m[1], quantite: m[2], unite: m[3], designation: m[4])
    }

    /// « 35012 Raccord Mapress 22 mm 12 pce [prix…] ».
    static func quantiteDerriere(_ ligne: String) -> ArticleLivre? {
        let motif = "^(?:([0-9]{4,}[0-9A-Z.-]*)\\s+)?(.{3,}?)\\s+(\\d+(?:[.,]\\d+)?)\\s*(\(unites))\\.?(?:\\s|$)"
        guard let m = AnalyseurRegie.premier(motif, dans: ligne) else { return nil }
        return article(reference: m[1], quantite: m[3], unite: m[4], designation: m[2])
    }

    private static func article(reference: String, quantite: String, unite: String, designation: String) -> ArticleLivre? {
        // Désignation sans montants (« 12.50 », « 1'250.00 ») ni blancs superflus.
        var d = designation.replacingOccurrences(of: "\\s+\\d+['’]?\\d*[.,]\\d{2}\\b.*$", with: "", options: .regularExpression)
        d = d.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard d.count >= 3, d.contains(where: \.isLetter) else { return nil }
        guard let q = Double(quantite.replacingOccurrences(of: ",", with: ".")), q > 0, q < 100_000 else { return nil }
        let u = normaliserUnite(unite)
        return ArticleLivre(reference: reference.isEmpty ? nil : reference, designation: d, quantite: q, unite: u)
    }

    static func normaliserUnite(_ u: String) -> String {
        switch u.lowercased() {
        case "m", "ml": "m"
        case "kg": "kg"
        case "l": "l"
        case "rouleau", "rouleaux", "rlx": "rouleau"
        case "sac", "sacs": "sac"
        case "boîte", "boîtes", "bte": "boîte"
        case "paquet", "paquets", "pq", "pa": "paquet"
        case "ens", "set", "jeu": "jeu"
        default: "pce"
        }
    }

    private static func chiffreDans(_ s: String) -> Bool { s.contains(where: \.isNumber) }
}

/// Retrouve le chantier d'un document à partir du texte lu (client, lieu, titre, numéro de dossier).
public enum SuggestionChantier {
    public struct Proposition: Sendable, Equatable {
        public var dossier: Dossier
        public var score: Int
    }

    /// Chantiers classés du plus probable au moins probable (score > 0 seulement).
    public static func classer(texte: String, chantiers: [Dossier]) -> [Proposition] {
        let t = " " + RepondeurLocal.normaliser(texte) + " "
        return chantiers.compactMap { d -> Proposition? in
            var score = 0
            for mot in motsUtiles(d.client) where t.contains(" \(mot) ") { score += 3 }
            for mot in motsUtiles(d.lieu ?? "") where t.contains(" \(mot) ") { score += 2 }
            for mot in motsUtiles(d.titre) where t.contains(" \(mot) ") { score += 1 }
            if t.contains(" \(d.id) ") && d.id.count >= 2 { score += 1 }
            // Chantier en cours : plus probable qu'un chantier terminé.
            if score > 0, ["planifie", "en_cours", "realise"].contains(d.etape) { score += 1 }
            return score > 0 ? Proposition(dossier: d, score: score) : nil
        }
        .sorted { $0.score > $1.score }
    }

    private static let vides: Set<String> = ["les", "des", "sur", "pour", "avec", "sans", "salle", "bains", "rue", "route", "chemin",
                                             "villa", "residence", "famille", "commune", "regie", "gerance", "ppe"]

    static func motsUtiles(_ s: String) -> [String] {
        RepondeurLocal.normaliser(s).split(separator: " ").map(String.init).filter { $0.count >= 4 && !vides.contains($0) }
    }
}
