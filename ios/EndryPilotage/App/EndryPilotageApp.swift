import EndryKit
import SwiftUI

@main
struct EndryPilotageApp: App {
    @UIApplicationDelegateAdaptor(DelegueApp.self) private var delegue
    @State private var modele = ModeleApp()
    @Environment(\.scenePhase) private var phase
    @AppStorage(ThemeApparence.cle) private var apparence: ThemeApparence = .systeme

    var body: some Scene {
        WindowGroup {
            RacineView()
                .environment(modele)
                .preferredColorScheme(schema)
                .onAppear {
                    delegue.surJetonAPNs = { [modele] jeton in modele.recevoirJetonAPNs(jeton) }
                    delegue.surReference = { [modele] reference in modele.ouvrir(reference: reference) }
                    delegue.surNotificationRecue = { [modele] in Task { await modele.rafraichirTout() } }
                    delegue.surOui = { [modele] reference in Task { await modele.accepterDepuisNotification(reference) } }
                    delegue.surSaisieTraitee = { [modele] in modele.onglet = .saisie }
                    // Le jeton APNs peut changer : on le réenregistre à chaque lancement.
                    if modele.session.estConnecte { Task { await modele.proposerNotifications() } }
                    if let reference = delegue.consommerReferenceEnAttente() { modele.ouvrir(reference: reference) }
                }
                .onChange(of: phase) { _, nouvelle in
                    switch nouvelle {
                    case .background:
                        modele.verrou.verrouiller()
                        modele.suspendreFlux()
                    case .active:
                        if modele.session.estConnecte {
                            Task { await modele.verrou.deverrouiller() }
                            Task { await modele.rafraichirTout() }
                            modele.reprendreFlux()
                        }
                    default:
                        break
                    }
                }
                .onOpenURL { url in
                    // Lien interne : endrypilotage://decisions
                    if url.scheme == "endrypilotage", url.host == "decisions" {
                        modele.onglet = .aujourdhui
                        return
                    }
                    // Lien d'accès (Mail, QR, endrypilotage://…) : jamais de connexion sans confirmation de l'hôte.
                    if url.absoluteString.contains(LienAcces.marqueur), let lien = try? LienAcces.analyser(url.absoluteString) {
                        modele.lienEnAttente = lien
                    }
                }
        }
    }

    /// Captures forcées (`-clair` / `-sombre`), sinon le choix des Réglages (système par défaut).
    private var schema: ColorScheme? {
        switch Configuration.schemaForce {
        case "clair": .light
        case "sombre": .dark
        default: apparence.schema
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
        .animation(.endry, value: modele.session.estConnecte)
        .animation(.endry, value: modele.verrou.doitAfficherEcran)
        .animation(.fonduDoux, value: phase)
        .tint(Color.bronze)
        .confirmationDialog(
            "Connecter l’app à \(modele.lienEnAttente?.hoteAffiche ?? "ce serveur") ?",
            isPresented: Binding(get: { modele.lienEnAttente != nil }, set: { if !$0 { modele.lienEnAttente = nil } }),
            titleVisibility: .visible,
            presenting: modele.lienEnAttente
        ) { lien in
            let confiance = lien.estDeConfiance(hoteEnregistre: modele.session.baseEnregistree)
            Button(confiance ? "Connecter" : "Connecter quand même", role: confiance ? nil : .destructive) {
                Task { await modele.connecterLienConfirme(lien) }
            }
            Button("Annuler", role: .cancel) { modele.lienEnAttente = nil }
        } message: { lien in
            if lien.estDeConfiance(hoteEnregistre: modele.session.baseEnregistree) {
                Text("Serveur privé de l’entreprise. Le jeton restera dans le trousseau de cet iPhone.")
            } else {
                Text("Attention : cet hôte n’est ni sur votre réseau Tailscale (*.ts.net) ni votre serveur actuel. Ne continuez que si le lien vient du bureau.")
            }
        }
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
