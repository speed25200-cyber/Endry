import SwiftUI

/// Une option d'un sélecteur segmenté.
struct OptionSegment<Valeur: Hashable>: Identifiable {
    var valeur: Valeur
    var titre: String
    var id: Valeur { valeur }
}

/// Sélecteur segmenté en verre ; l'option active glisse sous une pastille dorée.
struct SelecteurSegments<Valeur: Hashable>: View {
    var options: [OptionSegment<Valeur>]
    @Binding var selection: Valeur
    @Namespace private var espace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let actif = option.valeur == selection
                Button {
                    withAnimation(.endry) { selection = option.valeur }
                } label: {
                    Text(option.titre)
                        .font(Police.texte(13, relativeTo: .footnote, graisse: .semibold))
                        .foregroundStyle(actif ? Color.espressoProfond : Color.encreDouce)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .background {
                            if actif {
                                Capsule().fill(.degradeOr).matchedGeometryEffect(id: "segment", in: espace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(actif ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.surfaceCreuse.opacity(0.9), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.bordureOr, lineWidth: Espace.filet))
        .sensoryFeedback(.selection, trigger: selection)
    }
}
