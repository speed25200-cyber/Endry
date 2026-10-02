import Foundation

/// Réglages de l'app. Aucun secret ici.
nonisolated enum Configuration {
    /// Arguments de lancement utilisés par les tests UI et les captures.
    static var lancementDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    static var testsUI: Bool { ProcessInfo.processInfo.arguments.contains("-uitests") }
    /// Démo du mode équipe (écran de l'ouvrier).
    static var demoOuvrier: Bool { ProcessInfo.processInfo.arguments.contains("-demo-ouvrier") }
    /// Captures d'écran : force le mode clair (`-clair`) ou sombre (`-sombre`).
    static var schemaForce: String? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-sombre") { return "sombre" }
        if args.contains("-clair") { return "clair" }
        return nil
    }

    /// Environnement APNs : sandbox pour les builds de debug, production pour TestFlight / App Store.
    static var environnementAPNs: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}
