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
}
