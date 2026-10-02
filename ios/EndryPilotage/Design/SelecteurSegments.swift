import SwiftUI

/// Une option d'un sélecteur segmenté.
struct OptionSegment<Valeur: Hashable>: Identifiable {
    var valeur: Valeur
    var titre: String
    var id: Valeur { valeur }
}

/// Sélecteur segmenté Maison Endry : capsule de verre, segments de même largeur, loupe qui glisse sous l'option active.
struct SelecteurSegments<Valeur: Hashable>: View {
    var options: [OptionSegment<Valeur>]
    @Binding var selection: Valeur
    @Namespace private var espace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let actif = option.valeur == selection
                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { selection = option.valeur }
                } label: {
                    Text(option.titre)
                        .font(Police.texte(13, relativeTo: .footnote, graisse: actif ? .medium : .regular))
                        .foregroundStyle(actif ? Color.encre : Color.encreDouce)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if actif {
                                Capsule()
                                    .fill(Color.lentille)
                                    .overlay(Capsule().strokeBorder(Color.filet, lineWidth: Espace.filet))
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(LinearGradient(colors: [Color.refletBord, .clear], startPoint: .topLeading, endPoint: .center),
                                                          lineWidth: 1)
                                            .opacity(0.5)
                                    }
                                    .matchedGeometryEffect(id: "segment", in: espace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(actif ? .isSelected : [])
                .accessibilityIdentifier("segment-\(option.titre.lowercased())")
            }
        }
        .padding(4)
        .verreMaison(Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}
