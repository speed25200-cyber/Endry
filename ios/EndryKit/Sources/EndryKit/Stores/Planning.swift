import Foundation

/// Calculs du planning multi-semaines : chantiers actifs un jour donné et barres d'une frise.
public enum Planning {
    /// Une barre de frise : indices de jours (inclus) dans la fenêtre affichée.
    public struct Barre: Identifiable, Sendable, Hashable {
        public var dossier: Dossier
        public var debut: Int
        public var fin: Int
        /// Le chantier commence avant la fenêtre ou se termine après.
        public var coupeAvant: Bool
        public var coupeApres: Bool

        public var id: String { dossier.id }
        public var duree: Int { fin - debut + 1 }
    }

    private static var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = DateEndry.fuseau
        c.firstWeekday = 2
        return c
    }

    /// Lundi de la semaine contenant `date`, décalé de `semaines`.
    public static func lundi(de date: Date, decalage semaines: Int = 0) -> Date {
        let c = calendrier
        let debut = c.dateInterval(of: .weekOfYear, for: date)?.start ?? c.startOfDay(for: date)
        return c.date(byAdding: .day, value: 7 * semaines, to: debut) ?? debut
    }

    /// Les `nombre` jours à partir de `debut`.
    public static func jours(depuis debut: Date, nombre: Int) -> [Date] {
        (0..<nombre).compactMap { calendrier.date(byAdding: .day, value: $0, to: calendrier.startOfDay(for: debut)) }
    }

    /// Intervalle de jours d'un dossier (fin = début si absente).
    static func intervalle(_ d: Dossier) -> (Date, Date)? {
        guard let debut = d.debut else { return nil }
        let c = calendrier
        let fin = max(d.fin ?? debut, debut)
        return (c.startOfDay(for: debut), c.startOfDay(for: fin))
    }

    /// Chantiers en cours ce jour-là (date de début ≤ jour ≤ date de fin).
    public static func actifs(le jour: Date, dans dossiers: [Dossier]) -> [Dossier] {
        let j = calendrier.startOfDay(for: jour)
        return dossiers.filter { d in
            guard let (debut, fin) = intervalle(d) else { return false }
            return debut <= j && j <= fin
        }
        .sorted { ($0.debut ?? .distantPast) < ($1.debut ?? .distantPast) }
    }

    /// Barres des chantiers qui touchent la fenêtre [debut, debut + nombreJours[.
    public static func barres(_ dossiers: [Dossier], depuis debut: Date, nombreJours: Int) -> [Barre] {
        let c = calendrier
        let origine = c.startOfDay(for: debut)
        return dossiers.compactMap { d -> Barre? in
            guard let (debutD, finD) = intervalle(d) else { return nil }
            let i = c.dateComponents([.day], from: origine, to: debutD).day ?? 0
            let f = c.dateComponents([.day], from: origine, to: finD).day ?? 0
            guard f >= 0, i < nombreJours else { return nil }
            return Barre(dossier: d, debut: max(i, 0), fin: min(f, nombreJours - 1), coupeAvant: i < 0, coupeApres: f >= nombreJours)
        }
        .sorted { ($0.debut, $0.dossier.titre) < ($1.debut, $1.dossier.titre) }
    }

    /// « 28.09 – 02.10 » ou « 05.10 » à partir des vraies dates.
    public static func libelleDates(_ d: Dossier) -> String? {
        guard let debut = d.debut else { return d.dates }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CH")
        f.timeZone = DateEndry.fuseau
        f.dateFormat = "dd.MM"
        let fin = d.fin ?? debut
        return calendrier.isDate(debut, inSameDayAs: fin) ? f.string(from: debut) : "\(f.string(from: debut)) – \(f.string(from: fin))"
    }

    /// Nombre de jours ouvrables (lun–ven) du chantier.
    public static func joursOuvrables(_ d: Dossier) -> Int? {
        guard let (debut, fin) = intervalle(d) else { return nil }
        let c = calendrier
        var n = 0
        var jour = debut
        while jour <= fin {
            let semaine = c.component(.weekday, from: jour)
            if semaine != 1 && semaine != 7 { n += 1 }
            jour = c.date(byAdding: .day, value: 1, to: jour) ?? fin.addingTimeInterval(1)
        }
        return n
    }
}
