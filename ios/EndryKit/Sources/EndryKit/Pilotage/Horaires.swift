import Foundation

/// Horaires de passage de l'assistant, lus dans le texte du PC (« du lundi au vendredi, de 7 h à 18 h »).
public struct HorairesAssistant: Sendable, Equatable {
    /// Jours ouverts, 1 = lundi … 7 = dimanche.
    public var jours: Set<Int>
    public var debut: Int
    public var fin: Int

    private static let nomsJours = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

    public init(jours: Set<Int>, debut: Int, fin: Int) {
        self.jours = jours
        self.debut = debut
        self.fin = fin
    }

    /// `nil` si le texte ne se laisse pas lire : l'app affiche alors le texte tel quel.
    public init?(texte: String) {
        let t = texte.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_CH"))
        let noms = Self.nomsJours
        var jours: Set<Int> = []
        if let du = noms.firstIndex(where: { t.contains("du \($0)") }), let au = noms.firstIndex(where: { t.contains("au \($0)") }), au >= du {
            jours = Set((du + 1)...(au + 1))
        } else {
            for (i, nom) in noms.enumerated() where t.contains(nom) { jours.insert(i + 1) }
        }
        if jours.isEmpty, t.contains("tous les jours") { jours = Set(1...7) }
        let heures = Self.heures(dans: t)
        guard !jours.isEmpty, heures.count >= 2, heures[0] < heures[1] else { return nil }
        self.init(jours: jours, debut: heures[0], fin: heures[1])
    }

    /// « 7 h », « 7h », « 07:00 », « 18 h 30 » → heures entières, dans l'ordre du texte.
    static func heures(dans t: String) -> [Int] {
        var resultat: [Int] = []
        let caracteres = Array(t)
        var i = 0
        while i < caracteres.count {
            if caracteres[i].isNumber {
                var nombre = ""
                while i < caracteres.count, caracteres[i].isNumber { nombre.append(caracteres[i]); i += 1 }
                var j = i
                while j < caracteres.count, caracteres[j] == " " { j += 1 }
                if j < caracteres.count, caracteres[j] == "h" || caracteres[j] == ":", let h = Int(nombre), h <= 24 {
                    resultat.append(h)
                }
            } else {
                i += 1
            }
        }
        return resultat
    }

    private static var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        c.locale = Locale(identifier: "fr_CH")
        return c
    }

    /// Jour ISO (1 = lundi) d'une date, à Zurich.
    static func jourISO(_ date: Date) -> Int {
        let w = calendrier.component(.weekday, from: date)   // 1 = dimanche
        return w == 1 ? 7 : w - 1
    }

    public func enService(_ date: Date = Date()) -> Bool {
        let h = Self.calendrier.component(.hour, from: date)
        return jours.contains(Self.jourISO(date)) && h >= debut && h < fin
    }

    /// Prochain passage : « aujourd’hui à 7 h », « demain à 7 h », « lundi à 7 h ».
    public func prochainPassage(apres date: Date = Date()) -> String {
        let c = Self.calendrier
        let h = c.component(.hour, from: date)
        for decalage in 0...7 {
            guard let jour = c.date(byAdding: .day, value: decalage, to: date) else { continue }
            guard jours.contains(Self.jourISO(jour)) else { continue }
            if decalage == 0, h >= debut { continue }
            let quand = decalage == 0 ? "aujourd’hui" : decalage == 1 ? "demain" : Self.nomsJours[Self.jourISO(jour) - 1]
            return "\(quand) à \(debut) h"
        }
        return "à la prochaine ouverture"
    }
}
