import EndryKit
import QuickLook
import SwiftUI

/// Les quatre espaces et la saisie, gardés en mémoire (position de défilement conservée), sous la barre d'onglets en verre.
struct ContenuPrincipal: View {
    @Environment(ModeleApp.self) private var app

    private func ouvrirAssistantDemande() {
        guard DemandesRaccourcis.partage.assistantDemande, !app.verrou.doitAfficherEcran else { return }
        DemandesRaccourcis.partage.assistantDemande = false
        app.reglagesPresentes = false
        app.ouvrirAssistant()
    }

    var body: some View {
        @Bindable var app = app
        @Bindable var documents = app.documents
        ZStack(alignment: .bottom) {
            ZStack {
                ecran(.aujourdhui) { if let m = app.decisions { DecisionsView(modele: m).id(ObjectIdentifier(m)) } }
                ecran(.chantiers) { if let m = app.chantiers { EspaceChantiers(modele: m).id(ObjectIdentifier(m)) } }
                ecran(.saisie) { if let m = app.saisie { SaisieView(modele: m).id(ObjectIdentifier(m)) } }
                ecran(.finances) { if let m = app.argent { ArgentView(modele: m).id(ObjectIdentifier(m)) } }
                ecran(.entreprise) { EntrepriseView() }
            }

            BarreOnglets(selection: $app.onglet, badgeDecisions: app.decisions?.nombreDecisions ?? 0) {
                app.ouvrirAssistant()
            }
                .padding(.bottom, 4)
                .ignoresSafeArea(.keyboard)
        }
        .overlay(alignment: .top) {
            if app.session.connexionPerdue {
                BanniereConnexionPerdue {
                    app.connexionPresentee = true
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.endry, value: app.session.connexionPerdue)
        .toast($app.toast)
        .quickLookPreview($documents.apercu)
        .alert("Document indisponible", isPresented: Binding(
            get: { app.documents.erreur != nil },
            set: { if !$0 { app.documents.erreur = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.documents.erreur ?? "")
        }
        .sheet(isPresented: $app.reglagesPresentes) {
            ReglagesView()
        }
        .fullScreenCover(isPresented: $app.assistantPresente) {
            VueAssistantVocal()
        }
        // « Dis Siri, parler à Endry » : l'assistant s'ouvre une fois l'app déverrouillée.
        .onChange(of: DemandesRaccourcis.partage.assistantDemande, initial: true) { ouvrirAssistantDemande() }
        .onChange(of: app.verrou.doitAfficherEcran) { ouvrirAssistantDemande() }
        .overlay {
            if app.documents.chargement != nil {
                ProgressView()
                    .controlSize(.large)
                    .padding(Espace.l)
                    .verre(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.documents.chargement)
    }

    @ViewBuilder
    private func ecran<Contenu: View>(_ onglet: Onglet, @ViewBuilder contenu: () -> Contenu) -> some View {
        let actif = app.onglet == onglet
        contenu()
            .opacity(actif ? 1 : 0)
            .scaleEffect(actif ? 1 : 0.985)
            .allowsHitTesting(actif)
            .accessibilityHidden(!actif)
            // L'écran actif passe devant : les écrans masqués ne recouvrent jamais ses champs.
            .zIndex(actif ? 1 : 0)
            .animation(.endry, value: actif)
    }
}

extension ModeleApp {
    /// L'assistant se présente sans glissement de feuille : c'est lui qui éclot au-dessus de l'app.
    func ouvrirAssistant() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { assistantPresente = true }
    }

    func fermerAssistant() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { assistantPresente = false }
    }
}

/// « Connexion perdue : collez le nouveau lien » (401 ou tunnel changé).
struct BanniereConnexionPerdue: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Espace.s) {
                Image(systemName: "link.badge.plus").font(.system(size: 17, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connexion perdue").styleTexte(15, relativeTo: .subheadline, graisse: .semibold)
                    Text("Collez le nouveau lien d’accès.").styleTexte(13, relativeTo: .footnote)
                        .opacity(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
            }
            .foregroundStyle(Color.orClair)
            .padding(.horizontal, Espace.m)
            .padding(.vertical, Espace.s)
            .background(MatiereEspresso(rayon: 20))
            .padding(.horizontal, Espace.m)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("banniere-connexion-perdue")
    }
}
