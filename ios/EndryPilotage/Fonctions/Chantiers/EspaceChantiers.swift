import EndryKit
import SwiftUI

/// Espace Chantiers : pipeline des dossiers et planning, réunis sous un même onglet.
struct EspaceChantiers: View {
    var modele: ModeleChantiers
    @Environment(ModeleApp.self) private var app

    private var vue: VueChantiers { app.vueChantiers }

    var body: some View {
        @Bindable var app = app
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

            if !(vue == .pipeline && app.dossierOuvert) {
                SelecteurSegments(options: [
                    OptionSegment(valeur: VueChantiers.pipeline, titre: "Pipeline"),
                    OptionSegment(valeur: VueChantiers.planning, titre: "Planning"),
                ], selection: $app.vueChantiers, pleineLargeur: false)
                .fixedSize()
                .padding(.trailing, Espace.bord)
                .padding(.top, Espace.s)
                .transition(.opacity)
            }
        }
        .animation(.endry, value: vue)
        .animation(.endry, value: app.dossierOuvert)
    }
}
