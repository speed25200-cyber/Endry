import EndryKit
import SwiftUI

@main
struct EndryPilotageApp: App {
    @UIApplicationDelegateAdaptor(DelegueApp.self) private var delegue
    @State private var modele = ModeleApp()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RacineView()
                .environment(modele)
                .preferredColorScheme(Configuration.schemaForce == "sombre" ? .dark : Configuration.schemaForce == "clair" ? .light : nil)
                .onAppear {
                    delegue.surJetonAPNs = { [modele] jeton in modele.recevoirJetonAPNs(jeton) }
                    delegue.surReference = { [modele] reference in modele.ouvrir(reference: reference) }
                    if let reference = delegue.consommerReferenceEnAttente() { modele.ouvrir(reference: reference) }
                }
                .onChange(of: phase) { _, nouvelle in
                    switch nouvelle {
                    case .background:
                        modele.verrou.verrouiller()
                    case .active:
                        if modele.session.estConnecte {
                            Task { await modele.verrou.deverrouiller() }
                        }
                    default:
                        break
                    }
                }
                .onOpenURL { url in
                    // Widget : endrypilotage://decisions
                    if url.scheme == "endrypilotage", url.host == "decisions" {
                        modele.onglet = .decisions
                        return
                    }
                    // Lien d'accès ouvert depuis Mail (lien universel ou schéma personnalisé).
                    if url.absoluteString.contains(LienAcces.marqueur) {
                        modele.connexionPresentee = true
                        Task { try? await modele.connecter(texte: url.absoluteString) }
                    }
                }
        }
    }
}

struct RacineView: View {
    @Environment(ModeleApp.self) private var modele
    @Environment(\.scenePhase) private var phase

    var body: some View {
        @Bindable var modele = modele
        ZStack {
            Color.fond.ignoresSafeArea()

            if modele.session.estConnecte {
                ContenuPrincipal()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                ConnexionView()
                    .transition(.opacity)
            }

            if modele.session.estConnecte, modele.verrou.doitAfficherEcran {
                EcranVerrou()
                    .transition(.opacity)
                    .zIndex(2)
            }

            // Masquage du contenu dans le sélecteur d'apps.
            if phase != .active, modele.session.estConnecte, !Configuration.testsUI {
                EcranConfidentialite()
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .animation(.smooth(duration: 0.35), value: modele.session.estConnecte)
        .animation(.smooth(duration: 0.25), value: modele.verrou.doitAfficherEcran)
        .animation(.easeOut(duration: 0.15), value: phase)
        .tint(Color.bronze)
        .sheet(isPresented: $modele.connexionPresentee) {
            ConnexionView(enFeuille: true)
                .presentationDragIndicator(.visible)
        }
        .task {
            if modele.session.estConnecte { await modele.verrou.deverrouiller() }
        }
    }
}

/// Écran affiché quand l'app passe en arrière-plan : aucun montant visible dans le sélecteur d'apps.
struct EcranConfidentialite: View {
    var body: some View {
        ZStack {
            MatiereEspresso(rayon: 0).ignoresSafeArea()
            LogoEndry(taille: 72)
        }
        .accessibilityHidden(true)
    }
}

struct EcranVerrou: View {
    @Environment(ModeleApp.self) private var modele

    var body: some View {
        ZStack {
            MatiereEspresso(rayon: 0).ignoresSafeArea()
            VStack(spacing: Espace.l) {
                Spacer()
                LogoEndry(taille: 84)
                Text("Endry Pilotage")
                    .styleTitre(28, relativeTo: .title)
                    .foregroundStyle(Color.orClair)
                if let erreur = modele.verrou.erreur {
                    Text(erreur).styleTexte(14, relativeTo: .subheadline).foregroundStyle(Color.orClair.opacity(0.7))
                }
                Spacer()
                Button {
                    Task { await modele.verrou.deverrouiller() }
                } label: {
                    Label("Déverrouiller avec \(modele.verrou.nomMethode)", systemImage: "faceid")
                }
                .buttonStyle(BoutonPrincipal(couleur: .or))
                .padding(.horizontal, Espace.xl)
                .padding(.bottom, Espace.xxl)
            }
        }
    }
}

/// Monogramme « E » or dans un cadre fin.
struct LogoEndry: View {
    var taille: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: taille * 0.28, style: .continuous)
                .strokeBorder(Color.or.opacity(0.8), lineWidth: max(1, taille / 90))
                .frame(width: taille, height: taille)
            Text("E")
                .font(Police.titre(taille * 0.56, relativeTo: .largeTitle))
                .foregroundStyle(.degradeOr)
        }
        .accessibilityLabel(Text("Endry SA"))
    }
}
