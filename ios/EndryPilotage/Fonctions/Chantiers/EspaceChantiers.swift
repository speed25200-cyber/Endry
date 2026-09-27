import EndryKit
import SwiftUI

/// Espace Chantiers : pipeline des dossiers et planning, réunis sous un même onglet.
struct EspaceChantiers: View {
    var modele: ModeleChantiers

    enum Vue: Hashable { case pipeline, planning }

    @State private var vue: Vue = .pipeline

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ChantiersView(modele: modele)
                .opacity(vue == .pipeline ? 1 : 0)
                .offset(x: vue == .pipeline ? 0 : -24)
                .allowsHitTesting(vue == .pipeline)
                .accessibilityHidden(vue != .pipeline)
            PlanningView(modele: modele)
                .opacity(vue == .planning ? 1 : 0)
                .offset(x: vue == .planning ? 0 : 24)
                .allowsHitTesting(vue == .planning)
                .accessibilityHidden(vue != .planning)

            SelecteurSegments(options: [
                OptionSegment(valeur: Vue.pipeline, titre: "Pipeline"),
                OptionSegment(valeur: Vue.planning, titre: "Planning"),
            ], selection: $vue)
            .padding(.trailing, Espace.bord)
            .padding(.top, Espace.s)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: vue)
    }
}
