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
                    delegue.surSaisieTraitee = { [modele] saisieId in modele.ouvrirHistoriqueSaisies(saisieId) }
                    delegue.surLocale = { [modele] locale, action in modele.traiter(locale, action: action) }
                    if let enAttente = delegue.consommerLocaleEnAttente() { modele.traiter(enAttente.0, action: enAttente.1) }
                    // Le jeton APNs peut changer : on le réenregistre à chaque lancement.
                    if modele.session.estConnecte { Task { await modele.proposerNotifications() } }
                    if let reference = delegue.consommerReferenceEnAttente() { modele.ouvrir(reference: reference) }
                }
                .onChange(of: phase) { _, nouvelle in
                    switch nouvelle {
                    case .background:
                        modele.verrou.verrouiller()
                        modele.suspendreFlux()
                        modele.lecteur.arreter()
                        Task { await modele.apresChargement() }
                    case .active:
                        if modele.session.estConnecte {
                            modele.reessayerRoutesPC()
                            Task { await modele.verrou.deverrouiller() }
                            Task { await modele.rafraichirTout() }
                            modele.reprendreFlux()
                        }
                    default:
                        break
                    }
                }
                .onOpenURL { url in
                    // Liens internes (widgets, Centre de contrôle) : endrypilotage://decisions, …/outil/regie, …/assistant.
                    if url.scheme == "endrypilotage", let hote = url.host, ["decisions", "outil", "assistant", "briefing"].contains(hote) {
                        let demandes = DemandesRaccourcis.partage
                        switch hote {
                        case "outil":
                            demandes.outil = OutilTerrain(rawValue: url.lastPathComponent) ?? .regie
                        case "assistant":
                            demandes.assistantDemande = true
                        case "briefing":
                            demandes.briefingDemande = true
                        default:
                            modele.onglet = .aujourdhui
                        }
                        return
                    }
                    // Lien d'accès (Mail, QR, endrypilotage://…) : jamais de connexion sans confirmation de l'hôte.
                    if url.absoluteString.contains(LienAcces.marqueur), let lien = try? LienAcces.analyser(url.absoluteString) {
                        modele.lienEnAttente = lien
                    }
                }
        }
        // iPad avec clavier : ⌘1…⌘5 pour les espaces, ⌘K l'assistant vocal, ⌘N la conversation (maintenir ⌘ les affiche).
        .commands { CommandesEndry(modele: modele) }
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
    @State private var intro = !Configuration.testsUI

    var body: some View {
        @Bindable var modele = modele
        ZStack {
            Color.fond.ignoresSafeArea()

            if modele.session.estConnecte, modele.session.estOuvrier, let equipe = modele.equipe {
                EspaceOuvrier(modele: equipe)
                    .transition(.opacity)
            } else if modele.session.estConnecte {
                ContenuPrincipal()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                ConnexionView()
                    .toast($modele.toast)
                    .transition(.opacity)
            }

            if modele.session.estConnecte, modele.verrou.doitAfficherEcran {
                EcranVerrou()
                    .transition(.opacity)
                    .zIndex(2)
            }

            if intro {
                IntroMaison { intro = false }
                    .zIndex(4)
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
            if modele.session.estConnecte {
                await modele.migrerJetonSiNecessaire()
                await modele.verrou.deverrouiller()
            }
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
                LogoMarque(largeur: 240)
                Text("Pilotage")
                    .font(Police.etiquette(12, relativeTo: .caption))
                    .textCase(.uppercase)
                    .tracking(4)
                    .foregroundStyle(Color.or)
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
    /// Hauteur du monogramme EY.
    var taille: CGFloat = 64

    var body: some View {
        Image("MonogrammeEndry")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: taille)
            .accessibilityLabel(Text("Endry SA"))
    }
}

/// Logo complet « EY ENDRY SA — Sanitaire Chauffage Ventilation », détouré, pour les fonds sombres.
struct LogoMarque: View {
    var largeur: CGFloat = 160

    var body: some View {
        Image("LogoEndry")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: largeur)
            .accessibilityLabel(Text("Endry SA, sanitaire, chauffage, ventilation"))
    }
}

/// Raccourcis clavier (iPad avec clavier, Mac) : listés quand on maintient la touche ⌘.
struct CommandesEndry: Commands {
    let modele: ModeleApp

    private var actif: Bool {
        modele.session.estConnecte && !modele.session.estOuvrier && !modele.verrou.doitAfficherEcran
    }

    var body: some Commands {
        CommandMenu("Endry") {
            ForEach(Array(Onglet.allCases.enumerated()), id: \.element) { index, onglet in
                Button(onglet.titre) { modele.onglet = onglet }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(!actif)
            }
            Divider()
            Button("Parler à Endry") { modele.ouvrirAssistant() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!actif)
            Button("Écrire au bureau") { modele.ouvrirConversation() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!actif || modele.conversation == nil)
            Button("Rechercher") { modele.recherchePresentee = true }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!actif)
            Button("Actualiser") { Task { await modele.rafraichirTout() } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!modele.session.estConnecte)
        }
    }
}
