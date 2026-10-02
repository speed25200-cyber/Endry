import EndryKit
import Foundation
import Observation
import QuickLook
import SwiftUI

/// Téléchargement des PDF (avec le jeton) puis aperçu QuickLook.
@MainActor
@Observable
final class Documents {
    var apercu: URL?
    private(set) var chargement: String?
    var erreur: String?
    /// Fenêtres qui savent afficher un aperçu, de la plus basse à celle du dessus.
    var pile: [UUID] = []

    func ouvrir(_ chemin: String, nom: String, api: (any EndryAPI)?) async {
        guard let api, chargement == nil else { return }
        chargement = chemin
        defer { chargement = nil }
        do {
            apercu = try await api.telechargerDocument(chemin, nom: nom)
        } catch .serveur(let statut, _) where statut == 404 || statut == 410 {
            // Le PC annonce le fichier mais ne le sert pas (pièce générée dans le dossier du bureau, pas d'adresse).
            erreur = "Le bureau n’a pas encore mis « \(nom) » à disposition de l’iPhone : l’aperçu sera possible dès que le PC le servira."
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

extension Documents {
    /// Fenêtres ouvertes les unes sur les autres (écran principal, puis feuilles et écrans pleins) : l'aperçu
    /// d'un document s'affiche dans celle du dessus. Rattaché seulement à l'écran principal, il ne pouvait pas
    /// s'ouvrir depuis une feuille (fiche d'un e-mail, recherche…) : iOS refuse de présenter sous une feuille.
    func estAuDessus(_ fenetre: UUID) -> Bool { pile.last == fenetre }
}

/// Aperçu QuickLook des documents (PDF, Excel…) et message d'erreur, dans cette fenêtre si elle est au-dessus.
private struct ApercuDocuments: ViewModifier {
    @Environment(ModeleApp.self) private var app
    @State private var fenetre = UUID()

    func body(content: Content) -> some View {
        let documents = app.documents
        content
            .quickLookPreview(Binding(get: { documents.estAuDessus(fenetre) ? documents.apercu : nil },
                                      set: { documents.apercu = $0 }))
            .alert("Document indisponible", isPresented: Binding(
                get: { documents.estAuDessus(fenetre) && documents.erreur != nil },
                set: { if !$0 { documents.erreur = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(documents.erreur ?? "")
            }
            .onAppear { documents.pile.append(fenetre) }
            .onDisappear { documents.pile.removeAll { $0 == fenetre } }
    }
}

extension View {
    /// À poser sur l'écran principal et sur chaque feuille ou écran plein qui ouvre des documents.
    func apercuDocuments() -> some View { modifier(ApercuDocuments()) }
}
