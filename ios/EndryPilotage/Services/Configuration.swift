import Foundation

/// Identifiants partagés entre l'app et le widget. Aucun secret ici.
nonisolated enum Configuration {
    /// Groupe d'apps (résumé pour le widget). À créer dans le portail Apple Developer.
    static let groupeApps = "group.com.endrysa.endry"

    /// Groupe de trousseau partagé app ↔ widget : « <Team ID>.com.endrysa.endry ».
    /// Le préfixe d'équipe est injecté au build dans Info.plist (clé `EndryPrefixeEquipe`).
    static var groupeTrousseau: String? {
        guard let prefixe = Bundle.main.object(forInfoDictionaryKey: "EndryPrefixeEquipe") as? String,
              !prefixe.isEmpty, !prefixe.contains("$") else { return nil }
        return prefixe.hasSuffix(".") ? "\(prefixe)com.endrysa.endry" : "\(prefixe).com.endrysa.endry"
    }

    /// Arguments de lancement utilisés par les tests UI et les captures.
    static var lancementDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    static var testsUI: Bool { ProcessInfo.processInfo.arguments.contains("-uitests") }
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
