import Foundation

/// Montant décomposé pour l'affichage « CHF » en petites capitales, francs en grand, centimes en exposant.
public struct PartiesMontant: Sendable, Equatable {
    public var signe: String
    public var francs: String
    public var centimes: String

    public var complet: String { "CHF \(signe)\(francs).\(centimes)" }
}

/// Formats suisses, indépendants de la langue de l'appareil : séparateur de milliers ’ (U+2019), point décimal.
public enum FormatSuisse {
    public static let separateurMilliers = "\u{2019}"

    /// `13695.45` → `CHF 13’695.45`
    public static func chf(_ montant: Double) -> String {
        parties(montant).complet
    }

    /// `13695.45` → `13’695.45` (sans devise).
    public static func nombre(_ montant: Double) -> String {
        let p = parties(montant)
        return "\(p.signe)\(p.francs).\(p.centimes)"
    }

    /// `13695.45` → `CHF 13’695` (arrondi au franc, pour les tuiles compactes).
    public static func chfArrondi(_ montant: Double) -> String {
        let arrondi = montant.rounded()
        let p = parties(arrondi)
        return "CHF \(p.signe)\(p.francs)"
    }

    public static func parties(_ montant: Double) -> PartiesMontant {
        guard montant.isFinite else { return PartiesMontant(signe: "", francs: "0", centimes: "00") }
        let totalCentimes = Int64((abs(montant) * 100).rounded())
        let francs = totalCentimes / 100
        let centimes = totalCentimes % 100
        let signe = (montant < 0 && totalCentimes > 0) ? "−" : ""
        return PartiesMontant(
            signe: signe,
            francs: grouper(francs),
            centimes: centimes < 10 ? "0\(centimes)" : "\(centimes)"
        )
    }

    public static func grouper(_ valeur: Int64) -> String {
        let chiffres = String(valeur)
        var resultat = ""
        for (i, chiffre) in chiffres.enumerated() {
            if i > 0, (chiffres.count - i) % 3 == 0 {
                resultat += separateurMilliers
            }
            resultat.append(chiffre)
        }
        return resultat
    }

    /// Heures au format suisse : `12.5` → `12 h 30`.
    public static func heures(_ heures: Double) -> String {
        let minutesTotales = Int((heures * 60).rounded())
        let h = minutesTotales / 60
        let m = minutesTotales % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m < 10 ? "0" : "")\(m)"
    }
}

/// Lecture et affichage des dates de l'API (`AAAA-MM-JJ` ou ISO 8601).
public enum DateEndry {
    private static let calendrier: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        c.locale = Locale(identifier: "fr_CH")
        c.firstWeekday = 2
        return c
    }()

    public static var fuseau: TimeZone { calendrier.timeZone }

    public static func lire(_ texte: String) -> Date? {
        let s = texte.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if s.count == 10, let d = jourSimple(s) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        // ISO sans fuseau (« 2026-09-22T08:15:00 ») : heure suisse.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = fuseau
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "dd.MM.yyyy"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static func jourSimple(_ s: String) -> Date? {
        let morceaux = s.split(separator: "-").compactMap { Int($0) }
        guard morceaux.count == 3 else { return nil }
        return calendrier.date(from: DateComponents(year: morceaux[0], month: morceaux[1], day: morceaux[2], hour: 12))
    }

    private static let jours = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
    private static let mois = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août",
                               "septembre", "octobre", "novembre", "décembre"]
    private static let moisCourts = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août",
                                     "sept.", "oct.", "nov.", "déc."]

    /// `2026-09-22` → `22.09.2026`
    public static func courte(_ texte: String?) -> String {
        guard let texte, let d = lire(texte) else { return texte ?? "" }
        let c = calendrier.dateComponents([.day, .month, .year], from: d)
        return String(format: "%02d.%02d.%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }

    /// `2026-09-22` → `22 sept.`
    public static func jourMois(_ texte: String?) -> String {
        guard let texte, let d = lire(texte) else { return texte ?? "" }
        let c = calendrier.dateComponents([.day, .month], from: d)
        return "\(c.day ?? 0) \(moisCourts[((c.month ?? 1) - 1) % 12])"
    }

    /// `2026-09-22` → `lundi 22 septembre`
    public static func longue(_ date: Date) -> String {
        let c = calendrier.dateComponents([.weekday, .day, .month], from: date)
        return "\(jours[((c.weekday ?? 1) - 1) % 7]) \(c.day ?? 0) \(mois[((c.month ?? 1) - 1) % 12])"
    }

    /// Jour de la semaine abrégé (« lun. »).
    public static func jourAbrege(_ date: Date) -> String {
        let c = calendrier.dateComponents([.weekday], from: date)
        return String(jours[((c.weekday ?? 1) - 1) % 7].prefix(3)) + "."
    }

    public static func numeroJour(_ date: Date) -> Int {
        calendrier.component(.day, from: date)
    }

    public static func estAujourdhui(_ date: Date, maintenant: Date = Date()) -> Bool {
        calendrier.isDate(date, inSameDayAs: maintenant)
    }

    /// Les 7 jours de la semaine courante (lundi → dimanche).
    public static func semaine(contenant date: Date = Date()) -> [Date] {
        guard let intervalle = calendrier.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { calendrier.date(byAdding: .day, value: $0, to: intervalle.start) }
    }

    public static func memeJour(_ a: Date, _ b: Date) -> Bool {
        calendrier.isDate(a, inSameDayAs: b)
    }

    /// « à l'instant », « il y a 5 min », « il y a 2 h », « il y a 3 jours ».
    public static func ilYa(_ date: Date, maintenant: Date = Date()) -> String {
        let secondes = max(0, maintenant.timeIntervalSince(date))
        switch secondes {
        case ..<60: return "à l’instant"
        case ..<3600: return "il y a \(Int(secondes / 60)) min"
        case ..<86_400: return "il y a \(Int(secondes / 3600)) h"
        default:
            let j = Int(secondes / 86_400)
            return j == 1 ? "hier" : "il y a \(j) jours"
        }
    }
}
