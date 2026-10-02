import SwiftUI

/// Accueil Maison Endry : les quatre outils de terrain à portée de pouce, en pastilles de verre
/// (Régie, Bon, Photo, Relevé 3D). « Photo » ouvre la saisie terrain (photos, dictée, envoi au bureau).
struct ActionsTerrain: View {
    @Environment(ModeleApp.self) private var app

    private struct Action: Identifiable {
        let id: String
        let titre: String
        let icone: String
        let ouvrir: @MainActor (ModeleApp) -> Void
    }

    private let actions: [Action] = [
        Action(id: "regie", titre: "Régie", icone: "doc.text") { $0.ouvrirOutil(.regie) },
        Action(id: "bon", titre: "Bon", icone: "shippingbox") { $0.ouvrirOutil(.bonLivraison) },
        Action(id: "photo", titre: "Photo", icone: "camera") { $0.onglet = .saisie },
        Action(id: "releve", titre: "Relevé 3D", icone: "cube") { $0.ouvrirOutil(.releve) },
    ]

    var body: some View {
        HStack(spacing: Espace.xs) {
            ForEach(actions) { action in
                Button { action.ouvrir(app) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: action.icone)
                            .font(.system(size: 19, weight: .light))
                            .foregroundStyle(Color.encre)
                            .frame(width: 54, height: 54)
                            .verreMaison(Circle())
                        Text(action.titre)
                            .styleTexte(11.5, relativeTo: .caption)
                            .foregroundStyle(Color.encre)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ActionPressee())
                .accessibilityIdentifier("action-\(action.id)")
            }
        }
    }
}
