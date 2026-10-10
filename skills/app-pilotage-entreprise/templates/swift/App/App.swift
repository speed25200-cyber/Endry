import SwiftUI
import {{PREFIXE}}Kit

// Point d'entrée minimal (skill app-pilotage-entreprise) : un poste de pilotage de démonstration qui assemble les
// briques du design system. À remplacer par ModeleApp, ContenuPrincipal (onglets) et les vrais écrans.

@main
struct {{PREFIXE}}PilotageApp: App {
    var body: some Scene {
        WindowGroup {
            PosteDePilotage()
        }
    }
}

struct PosteDePilotage: View {
    @State private var valide = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Bonjour")
                        .font(Police.serif(34, relativeTo: .largeTitle))
                        .foregroundStyle(Color.encre)
                    TitreSection(titre: "Pouls de l’entreprise", repere: "démo")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        Indicateur(symbole: "exclamationmark.triangle", titre: "En retard", valeur: "2", unite: "factures",
                                   detail: "CHF 4’300 · 12 j", ton: .alerte, identifiant: "instrument-retards") {}
                        Indicateur(symbole: "checkmark.seal", titre: "À décider", valeur: "3",
                                   detail: "à valider d’un geste", identifiant: "instrument-decisions") {}
                    }
                    BandeChiffres(elements: [
                        .init(valeur: "22", libelle: "traitées"),
                        .init(valeur: "3", libelle: "en file"),
                        .init(valeur: "0", libelle: "bloqué", ton: .sain),
                    ])
                    GlisserPourValider(libelle: "Glisser pour valider", envoi: false) { valide = true }
                }
                .padding(16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Color.fond.ignoresSafeArea())
        }
    }
}
