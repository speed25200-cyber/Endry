import Foundation

/// Transforme une dictée de chantier en bon de régie : heures par intervenant, matériel, déplacement.
/// Analyse déterministe, sur l'iPhone, sans réseau ; Apple Intelligence (quand elle est là) fait mieux
/// et l'app garde ce repli. Le patron relit toujours avant de faire signer.
public enum AnalyseurRegie {
    public struct Resultat: Sendable, Equatable {
        public var travaux: String
        public var heures: [Paire]
        public var materiel: [Article]
        public var deplacement: Bool?

        public struct Paire: Sendable, Equatable {
            public var intervenant: String
            public var heures: Double
            public init(intervenant: String, heures: Double) {
                self.intervenant = intervenant
                self.heures = heures
            }
        }

        public struct Article: Sendable, Equatable {
            public var designation: String
            public var quantite: Double
            public var unite: String
            public init(designation: String, quantite: Double, unite: String) {
                self.designation = designation
                self.quantite = quantite
                self.unite = unite
            }
        }

        public init(travaux: String, heures: [Paire], materiel: [Article], deplacement: Bool?) {
            self.travaux = travaux
            self.heures = heures
            self.materiel = materiel
            self.deplacement = deplacement
        }

        public var lignesHeures: [LigneHeures] { heures.map { LigneHeures(intervenant: $0.intervenant, heures: $0.heures) } }
        public var lignesMateriel: [LigneMateriel] {
            materiel.map { LigneMateriel(designation: $0.designation, quantite: $0.quantite, unite: $0.unite) }
        }
    }

    /// `moi` : nom donné au patron quand il dit « j'ai travaillé 2 heures » ou « Marco et moi ».
    public static func analyser(_ dictee: String, moi: String = "Patron") -> Resultat {
        var travaux: [String] = []
        var heures: [Resultat.Paire] = []
        var materiel: [Resultat.Article] = []
        var deplacement: Bool?

        for clause in clauses(dictee) {
            let normale = nombresEnChiffres(clause)
            let bas = normale.lowercased()
            if bas.contains("sans déplacement") || bas.contains("pas de déplacement") {
                deplacement = false
                continue
            }
            if bas.contains("déplacement") || bas.contains("deplacement") {
                deplacement = true
                if bas.split(separator: " ").count <= 3 { continue }
            }
            if let duree = duree(dans: normale) {
                for nom in intervenants(dans: clause, moi: moi) {
                    heures.append(.init(intervenant: nom, heures: duree))
                }
                // « 2 heures pour changer le mitigeur » : le travail compte aussi.
                if let r = clause.range(of: " pour ", options: .caseInsensitive) {
                    let travail = clause[r.upperBound...].trimmingCharacters(in: .whitespaces)
                    if travail.split(separator: " ").count >= 2 { travaux.append(majuscule(travail)) }
                }
                continue
            }
            travaux.append(majuscule(clause))
            if let article = article(dans: normale) { materiel.append(article) }
        }
        let texte = travaux.map { $0.hasSuffix(".") ? $0 : $0 + "." }.joined(separator: " ")
        return Resultat(travaux: texte, heures: fusionner(heures), materiel: materiel, deplacement: deplacement)
    }

    // MARK: - Découpage

    static func clauses(_ texte: String) -> [String] {
        var s = texte.replacingOccurrences(of: "\n", with: ". ")
        // « … tube 16 et 2 raccords » : une énumération de matériel se coupe à chaque quantité.
        let quantites = "\\d|un |une |deux |trois |quatre |cinq |six |sept |huit |neuf |dix "
        s = s.replacingOccurrences(of: "(?i)\\s+et(?: puis)?\\s+(?=(?:\(quantites)))", with: ". ", options: .regularExpression)
        for lien in [" et puis ", " puis ", " ensuite ", " et après ", " après ça "] {
            s = s.replacingOccurrences(of: lien, with: ". ", options: .caseInsensitive)
        }
        return s.components(separatedBy: CharacterSet(charactersIn: ".;,"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 2 }
    }

    private static let nombres: [(String, String)] = [
        ("une", "1"), ("un", "1"), ("deux", "2"), ("trois", "3"), ("quatre", "4"), ("cinq", "5"), ("six", "6"),
        ("sept", "7"), ("huit", "8"), ("neuf", "9"), ("dix", "10"), ("onze", "11"), ("douze", "12"),
        ("quinze", "15"), ("vingt", "20"), ("trente", "30"),
    ]

    /// « deux heures et demie » → « 2 heures et demie » ; « une demi-heure » → « 0.5 heure ».
    static func nombresEnChiffres(_ texte: String) -> String {
        var s = texte
        s = s.replacingOccurrences(of: "(?i)\\b(une )?demi-heure\\b", with: "0.5 heure", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)\\btrois quarts? d[’']heure\\b", with: "0.75 heure", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)\\bun quart d[’']heure\\b", with: "0.25 heure", options: .regularExpression)
        for (mot, chiffre) in nombres {
            s = s.replacingOccurrences(of: "(?i)\\b\(mot)\\b", with: chiffre, options: .regularExpression)
        }
        return s
    }

    // MARK: - Heures

    /// « 3 heures », « 2 h 30 », « 2h30 », « 1,5 h », « 2 heures et demie », « 45 minutes ».
    static func duree(dans texte: String) -> Double? {
        let s = texte.lowercased()
        let motif = "(\\d+(?:[.,]\\d+)?)\\s*(?:h\\b|heures?\\b|h(?=\\d))\\s*(\\d{1,2})?(\\s*et (?:demie?|quart))?"
        if let m = premier(motif, dans: s) {
            var h = Double(m[1].replacingOccurrences(of: ",", with: ".")) ?? 0
            if let minutes = Double(m[2]), minutes < 60 { h += minutes / 60 }
            if m[3].contains("demi") { h += 0.5 } else if m[3].contains("quart") { h += 0.25 }
            return h > 0 && h <= 24 ? h : nil
        }
        if let m = premier("(\\d+)\\s*min(?:utes?)?\\b", dans: s), let minutes = Double(m[1]), minutes > 0 {
            return minutes / 60
        }
        return nil
    }

    private static let pasDesNoms: Set<String> = [
        "j", "je", "on", "nous", "il", "elle", "ils", "elles", "le", "la", "les", "total", "pour", "avec", "et", "chacun", "chacune",
        "heures", "heure", "matin", "après-midi", "aujourd’hui", "aujourd'hui", "travaillé", "passé", "fait", "mis", "compté",
    ]

    /// Noms propres de la clause (« Marco et moi », « pour Luc »), sinon `moi`.
    static func intervenants(dans clause: String, moi: String) -> [String] {
        let mots = clause.split(whereSeparator: { $0 == " " || $0 == "’" || $0 == "'" }).map(String.init)
        var noms: [String] = []
        for (i, mot) in mots.enumerated() {
            guard let premiere = mot.first, premiere.isUppercase, premiere.isLetter else { continue }
            let propre = mot.trimmingCharacters(in: .punctuationCharacters)
            guard !pasDesNoms.contains(propre.lowercased()), propre.count >= 2 else { continue }
            // Premier mot : un verbe au passé (« Posé », « Travaillé ») n'est pas un nom.
            if i == 0 {
                let bas = propre.lowercased()
                guard !["é", "és", "ée", "ées", "er", "ai", "ais", "is", "it"].contains(where: { bas.hasSuffix($0) }) else { continue }
            }
            if !noms.contains(propre) { noms.append(propre) }
        }
        let bas = " " + clause.lowercased() + " "
        let avecMoi = bas.contains(" moi ") || bas.contains(" j’ai ") || bas.contains(" j'ai ") || bas.contains(" je ")
        if avecMoi || noms.isEmpty { noms.insert(moi, at: 0) }
        return noms
    }

    /// Un même intervenant cité deux fois : heures additionnées.
    static func fusionner(_ paires: [Resultat.Paire]) -> [Resultat.Paire] {
        var ordre: [String] = []
        var totaux: [String: Double] = [:]
        for p in paires {
            if totaux[p.intervenant] == nil { ordre.append(p.intervenant) }
            totaux[p.intervenant, default: 0] += p.heures
        }
        return ordre.map { .init(intervenant: $0, heures: totaux[$0] ?? 0) }
    }

    // MARK: - Matériel

    private static let unites: [(motif: String, unite: String)] = [
        ("mètres? linéaires?|ml", "m"), ("mètres?|m", "m"), ("pièces?|pces?|pcs|x", "pce"), ("rouleaux?", "rouleau"),
        ("sacs?", "sac"), ("kilos?|kg", "kg"), ("litres?|l", "l"), ("boîtes?|boites?", "boîte"), ("paquets?", "paquet"),
        ("cartouches?", "cartouche"), ("barres?", "barre"),
    ]

    private static let pasDuMateriel = ["heure", "minute", "jour", "fois", "étage", "etage", "semaine", "client", "personne", "gars"]

    /// « posé 2 raccords Mapress 22 » → 2 pce « raccords Mapress 22 » ; « 4 mètres de tube multicouche 16 » → 4 m.
    static func article(dans texte: String) -> Resultat.Article? {
        let unitesMotif = unites.map(\.motif).joined(separator: "|")
        let motif = "(?:^|\\s)(\\d+(?:[.,]\\d+)?)\\s*(\(unitesMotif))?\\s+(?:de |d’|d')?([a-zA-ZÀ-ÿ].*)$"
        guard let m = premier(motif, dans: texte) else { return nil }
        let quantite = Double(m[1].replacingOccurrences(of: ",", with: ".")) ?? 1
        var designation = m[3].trimmingCharacters(in: .whitespaces)
        guard designation.count >= 3, quantite > 0, quantite < 10_000 else { return nil }
        let bas = designation.lowercased()
        guard !pasDuMateriel.contains(where: { bas.hasPrefix($0) }) else { return nil }
        var unite = "pce"
        if !m[2].isEmpty, let u = unites.first(where: { premier("^(?:\($0.motif))$", dans: m[2].lowercased()) != nil }) {
            unite = u.unite
        }
        designation = designation.prefix(1).uppercased() + designation.dropFirst()
        return .init(designation: designation, quantite: quantite, unite: unite)
    }

    // MARK: - Outils

    /// Groupes capturés du premier résultat (chaîne vide pour un groupe absent).
    static func premier(_ motif: String, dans texte: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: motif, options: [.caseInsensitive]) else { return nil }
        let ns = texte as NSString
        guard let r = regex.firstMatch(in: texte, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<r.numberOfRanges).map { i in
            let range = r.range(at: i)
            return range.location == NSNotFound ? "" : ns.substring(with: range)
        }
    }

    static func majuscule(_ s: String) -> String {
        s.prefix(1).uppercased() + s.dropFirst()
    }
}
