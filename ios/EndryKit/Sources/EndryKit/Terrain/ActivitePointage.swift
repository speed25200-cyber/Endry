#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity du pointage (mode équipe) : chantier en cours et chrono, sur l'écran verrouillé
/// et dans la Dynamic Island. Partagée entre l'app et l'extension widgets.
public struct ActivitePointage: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var chantier: String
        public var debut: Date
        public var totalJour: Double

        public init(chantier: String, debut: Date, totalJour: Double) {
            self.chantier = chantier
            self.debut = debut
            self.totalJour = totalJour
        }
    }

    public var ouvrier: String

    public init(ouvrier: String) {
        self.ouvrier = ouvrier
    }
}
#endif
