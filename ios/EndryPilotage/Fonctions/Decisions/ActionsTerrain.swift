import SwiftUI

/// Accueil Maison Endry : les outils de terrain à portée de pouce (pastilles de verre).
/// Régie, bon de livraison et relevé ouvrent l'outil ; « Dicter » ouvre la saisie.
struct ActionsTerrain: View {
    @Environment(ModeleApp.self) private var app

    private struct Action: Identifiable {
        let id: String
        let titre: String
        let icone: String
        let ouvrir: @MainActor (ModeleApp) -> Void
    }

    private let actions: [Action] = [
        Action(id: "regie", titre: "Régie", icone: OutilTerrain.regie.icone) { $0.ouvrirOutil(.regie) },
        Action(id: "bon", titre: "Bon", icone: OutilTerrain.bonLivraison.icone) { $0.ouvrirOutil(.bonLivraison) },
        Action(id: "releve", titre: "Relevé 3D", icone: OutilTerrain.releve.icone) { $0.ouvrirOutil(.releve) },
        Action(id: "dicter", titre: "Dicter", icone: "waveform") { $0.onglet = .saisie },
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            Text("Sur le terrain")
                .font(Police.etiquette(Echelle.micro))
                .textCase(.uppercase)
                .tracking(2.2)
                .foregroundStyle(Color.bronze)
            HStack(spacing: 0) {
                ForEach(actions) { action in
                    Button { action.ouvrir(app) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: action.icone)
                                .font(.system(size: 19, weight: .regular))
                                .foregroundStyle(Color.encre)
                                .frame(width: 56, height: 56)
                                .verre(Circle(), interactif: true)
                                .overlay(Circle().strokeBorder(Color.bordureOr, lineWidth: Espace.filet))
                            Text(action.titre)
                                .styleTexte(12, relativeTo: .caption, graisse: .medium)
                                .foregroundStyle(Color.encre)
                                .lineLimit(1)
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
}

/// Pression : la pastille se tasse puis revient avec un léger ressort.
private struct ActionPressee: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
