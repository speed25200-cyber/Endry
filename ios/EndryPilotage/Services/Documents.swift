import EndryKit
import Foundation
import Observation

/// Téléchargement des PDF (avec le jeton) puis aperçu QuickLook.
@MainActor
@Observable
final class Documents {
    var apercu: URL?
    private(set) var chargement: String?
    var erreur: String?

    func ouvrir(_ chemin: String, nom: String, api: (any EndryAPI)?) async {
        guard let api, chargement == nil else { return }
        chargement = chemin
        defer { chargement = nil }
        do {
            apercu = try await api.telechargerDocument(chemin, nom: nom)
        } catch {
            erreur = error.message
        }
    }

    /// Efface les PDF téléchargés (lancement et déconnexion) : rien ne traîne sur l'iPhone.
    static func purger() {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("documents", isDirectory: true)
        try? FileManager.default.removeItem(at: dossier)
    }
}
