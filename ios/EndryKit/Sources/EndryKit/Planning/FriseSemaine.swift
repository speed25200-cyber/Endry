import Foundation

/// Frise de la semaine (accueil Maison Endry) : chaque chantier des 7 jours devient une bande, du jour de début au
/// jour de fin, bornée à la semaine affichée (lundi → dimanche). Un chantier sans date est ignoré.
public enum FriseSemaine {
    public struct Bande: Sendable, Hashable, Identifiable {
        public var id: String
        public var titre: String
        public var lieu: String?
        /// Colonnes 0 (lundi) à 6 (dimanche), incluses.
        public var debut: Int
        public var fin: Int
        /// Le chantier commence avant ou finit après la semaine affichée.
        public var dejaCommence: Bool
        public var continueApres: Bool
    }

    /// `jours` : les 7 jours de la semaine (`DateEndry.semaine()`). Au plus `maximum` bandes, les plus tôt d'abord.
    public static func bandes(_ semaine: [Semaine], jours: [Date], maximum: Int = 3) -> [Bande] {
        guard let premier = jours.first, let dernier = jours.last else { return [] }
        let debutSemaine = Calendar(identifier: .gregorian).startOfDay(for: premier)
        return semaine.compactMap { s -> Bande? in
            guard let d = s.dateDebut else { return nil }
            let f = s.dateFin ?? d
            if f < debutSemaine || d > dernier.addingTimeInterval(86_399) { return nil }
            let i = index(de: d, dans: jours) ?? 0
            let j = index(de: f, dans: jours) ?? (jours.count - 1)
            return Bande(id: s.id, titre: s.titre, lieu: s.lieu, debut: max(0, min(i, j)), fin: max(i, j),
                         dejaCommence: d < debutSemaine, continueApres: f > dernier.addingTimeInterval(86_399))
        }
        .sorted { ($0.debut, $0.fin) < ($1.debut, $1.fin) }
        .prefix(maximum)
        .map { $0 }
    }

    /// Colonne du jour `d` dans la semaine, ou `nil` hors de la semaine.
    static func index(de d: Date, dans jours: [Date]) -> Int? {
        jours.firstIndex { DateEndry.memeJour($0, d) }
    }
}
