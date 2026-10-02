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

    /// Date lue (gardée en mémoire : les mêmes horodatages reviennent à chaque affichage d'une liste).
    public static func lire(_ texte: String) -> Date? {
        let s = texte.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if let connue = memoire.valeur(s) { return connue }
        let date = analyser(s)
        memoire.garder(s, date)
        return date
    }

    private static func analyser(_ s: String) -> Date? {
        if s.count == 10, let d = jourSimple(s) { return d }
        if let d = isoRapide(s) { return d }
        // Formes rares (« 22.09.2026 », ISO exotique) : formateurs créés une seule fois.
        for f in formateursISO { if let d = f.date(from: s) { return d } }
        for f in formateurs { if let d = f.date(from: s) { return d } }
        return nil
    }

    /// ISO 8601 lu à la main, sans formateur : `2026-09-22T08:15:00`, `…:00.123456`, `…Z`, `…+02:00`,
    /// `2026-09-22 08:15:00`, `2026-09-22T08:15`. Sans fuseau : heure suisse.
    static func isoRapide(_ s: String) -> Date? {
        let o = Array(s.utf8)
        func nombre(_ debut: Int, _ longueur: Int) -> Int? {
            guard debut >= 0, debut + longueur <= o.count else { return nil }
            var v = 0
            for i in debut..<(debut + longueur) {
                let c = o[i]
                guard c >= 48, c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            return v
        }
        guard o.count >= 16, o[4] == 45, o[7] == 45, o[10] == 84 || o[10] == 32, o[13] == 58,
              let an = nombre(0, 4), let mois = nombre(5, 2), let jour = nombre(8, 2),
              let heure = nombre(11, 2), let minute = nombre(14, 2),
              (1...12).contains(mois), (1...31).contains(jour), heure < 24, minute < 60 else { return nil }
        var i = 16
        var seconde = 0
        var fraction = 0.0
        if i < o.count, o[i] == 58 {
            guard let sec = nombre(i + 1, 2), sec < 61 else { return nil }
            seconde = sec
            i += 3
            if i < o.count, o[i] == 46 {
                i += 1
                var echelle = 0.1
                while i < o.count, o[i] >= 48, o[i] <= 57 {
                    fraction += Double(o[i] - 48) * echelle
                    echelle /= 10
                    i += 1
                }
            }
        }
        var zone = calendrier.timeZone
        if i < o.count {
            if o[i] == 90 {
                zone = TimeZone(secondsFromGMT: 0) ?? zone
                i += 1
            } else if o[i] == 43 || o[i] == 45 {
                let signe = o[i] == 43 ? 1 : -1
                guard let hh = nombre(i + 1, 2) else { return nil }
                var j = i + 3
                if j < o.count, o[j] == 58 { j += 1 }
                var mm = 0
                if let m = nombre(j, 2) {
                    mm = m
                    j += 2
                }
                guard let decalage = TimeZone(secondsFromGMT: signe * (hh * 3_600 + mm * 60)) else { return nil }
                zone = decalage
                i = j
            }
        }
        guard i == o.count else { return nil }
        var composantes = DateComponents(year: an, month: mois, day: jour, hour: heure, minute: minute, second: seconde)
        composantes.timeZone = zone
        return calendrier.date(from: composantes)?.addingTimeInterval(fraction)
    }

    nonisolated(unsafe) private static let formateursISO: [ISO8601DateFormatter] = {
        let fraction = ISO8601DateFormatter()
        fraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let simple = ISO8601DateFormatter()
        simple.formatOptions = [.withInternetDateTime]
        return [fraction, simple]
    }()

    nonisolated(unsafe) private static let formateurs: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "dd.MM.yyyy"].map {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = calendrier.timeZone
            f.dateFormat = $0
            return f
        }
    }()

    private static let memoire = MemoireDates()

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

    /// Date du contrat (`AAAA-MM-JJ`), en heure suisse.
    public static func iso(_ date: Date) -> String {
        let c = calendrier.dateComponents([.day, .month, .year], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Horodatage du contrat (`AAAA-MM-JJTHH:MM:SS`), heure suisse sans fuseau, comme le PC.
    public static func horodatage(_ date: Date) -> String {
        let c = calendrier.dateComponents([.day, .month, .year, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// `0932` (heure et minutes sur quatre chiffres, pour les numéros de documents).
    public static func hhmm(_ date: Date) -> String {
        let c = calendrier.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// `14 h 32`
    public static func heure(_ date: Date) -> String {
        let c = calendrier.dateComponents([.hour, .minute], from: date)
        return String(format: "%d h %02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// `22.09.2026`
    public static func courte(_ date: Date) -> String {
        courte(iso(date))
    }

    /// Nombre de jours civils de `a` à `b` (négatif si `b` est avant `a`).
    public static func jours(de a: Date, a b: Date) -> Int {
        let debut = calendrier.startOfDay(for: a)
        let fin = calendrier.startOfDay(for: b)
        return calendrier.dateComponents([.day], from: debut, to: fin).day ?? 0
    }

    /// Jour de la semaine (1 = lundi … 7 = dimanche).
    public static func jourSemaine(_ date: Date) -> Int {
        let w = calendrier.component(.weekday, from: date)
        return w == 1 ? 7 : w - 1
    }

    /// Même mois civil.
    public static func memeMois(_ a: Date, _ b: Date) -> Bool {
        calendrier.isDate(a, equalTo: b, toGranularity: .month)
    }

    /// Premier jour du mois suivant `date`.
    public static func moisSuivant(_ date: Date) -> Date {
        let debut = calendrier.dateInterval(of: .month, for: date)?.start ?? date
        return calendrier.date(byAdding: .month, value: 1, to: debut) ?? date
    }

    /// Nom du mois (« octobre »).
    public static func nomMois(_ date: Date) -> String {
        mois[(calendrier.component(.month, from: date) - 1) % 12]
    }

    /// `date` à `heure`:`minute`, heure suisse.
    public static func a(_ heure: Int, _ minute: Int = 0, le date: Date) -> Date {
        calendrier.date(bySettingHour: heure, minute: minute, second: 0, of: date) ?? date
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

/// Dates déjà lues (texte → date, ou échec), partagées entre fils ; vidée au-delà de 2000 entrées.
final class MemoireDates: @unchecked Sendable {
    private let verrou = NSLock()
    private var dates: [String: Date?] = [:]

    func valeur(_ texte: String) -> Date?? {
        verrou.lock()
        defer { verrou.unlock() }
        return dates[texte]
    }

    func garder(_ texte: String, _ date: Date?) {
        verrou.lock()
        defer { verrou.unlock() }
        if dates.count > 2_000 { dates.removeAll(keepingCapacity: true) }
        dates[texte] = .some(date)
    }
}
