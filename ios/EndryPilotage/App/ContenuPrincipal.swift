import EndryKit
import QuickLook
import SwiftUI

/// Les quatre espaces et la saisie, gardés en mémoire (position de défilement conservée), sous la barre d'onglets en verre.
struct ContenuPrincipal: View {
    @Environment(ModeleApp.self) private var app

    /// Siri, Spotlight, bouton Action : la demande attend que l'app soit déverrouillée.
    private func ouvrirAssistantDemande() {
        let demandes = DemandesRaccourcis.partage
        guard demandes.enAttente, !app.verrou.doitAfficherEcran else { return }
        app.reglagesPresentes = false
        if demandes.assistantDemande {
            demandes.assistantDemande = false
            app.ouvrirAssistant()
        }
        if let outil = demandes.outil {
            demandes.outil = nil
            app.ouvrirOutil(outil)
        }
        if let chantier = demandes.chantier {
            demandes.chantier = nil
            app.ouvrirChantier(chantier)
        }
        if demandes.briefingDemande {
            demandes.briefingDemande = false
            app.briefingPresente = true
        }
        if let type = demandes.creation {
            demandes.creation = nil
            app.nouveauDocument(type)
        }
        if demandes.conversationDemande {
            demandes.conversationDemande = false
            app.ouvrirConversation()
        }
    }

    var body: some View {
        @Bindable var app = app
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
                .environment(\.animationsEnPause, app.ecranParDessus)
                // iPad : un dock flottant centré, pas une barre étirée sur toute la largeur.
                .frame(maxWidth: 520)
                .padding(.bottom, 4)
                .ignoresSafeArea(.keyboard)
        }
        .overlay(alignment: .top) {
            if app.session.connexionPerdue {
                BanniereConnexionPerdue {
                    app.connexionPresentee = true
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                RappelModeClient()
                    .padding(.top, 2)
            }
        }
        .animation(.endry, value: app.session.connexionPerdue)
        .toast($app.toast)
        .apercuDocuments()
        .sheet(isPresented: $app.reglagesPresentes) {
            ReglagesView()
        }
        .fullScreenCover(isPresented: $app.assistantPresente) {
            VueAssistantVocal().apercuDocuments()
        }
        // Plein écran : l'app derrière cesse de se dessiner (la feuille gardait l'accueil animé dessous : saccades).
        .fullScreenCover(isPresented: $app.conversationPresentee) {
            if let modele = app.conversation { ConversationView(modele: modele) }
        }
        .sheet(isPresented: $app.recherchePresentee) {
            RechercheView().apercuDocuments()
        }
        .sheet(isPresented: $app.briefingPresente) {
            BriefingView().apercuDocuments()
        }
        .sheet(item: $app.creation) { creation in
            NouveauDocumentView(creation: creation, dossier: app.dossier(creation.chantierId)).apercuDocuments()
        }
        .sheet(item: Binding(get: { app.suiviOuvert.map(IdentifiantSuivi.init) }, set: { app.suiviOuvert = $0?.id })) { cible in
            if let modele = app.suiviActions { FicheSuiviView(modele: modele, id: cible.id).apercuDocuments() }
        }
        // Le bureau a répondu pendant que la conversation était fermée : on le signale.
        .onChange(of: app.conversation?.derniereArrivee?.id) { _, id in
            guard id != nil, !app.conversationPresentee, !app.assistantPresente,
                  let arrivee = app.conversation?.derniereArrivee else { return }
            let debut = ResumeOral.lisible(arrivee.texte).replacingOccurrences(of: "\n", with: " ")
            app.toast = Toast("Le bureau a répondu : \(debut.count > 70 ? String(debut.prefix(68)) + "…" : debut)", style: .info)
        }
        // Une décision aboutit (fait ou erreur) : le patron le voit, même s'il a quitté l'écran.
        .onChange(of: app.suiviActions?.derniereIssue?.id) { _, id in
            guard id != nil, let issue = app.suiviActions?.derniereIssue else { return }
            app.suiviActions?.oublierIssue()
            let titre = issue.titre.count > 70 ? String(issue.titre.prefix(68)) + "…" : issue.titre
            app.toast = Toast(issue.etat == .erreur ? "Pas abouti : \(titre)" : "Fait : \(titre)",
                              style: issue.etat == .erreur ? .erreur : .succes)
        }
        .fullScreenCover(item: $app.outilTerrain) { demande in
            // Sans chantier précisé : celui où le patron vient d'arriver (rappel d'arrivée), s'il y en a un.
            let chantier = app.dossier(demande.chantierId ?? ArriveeChantier.chantierRecent())
            switch demande.outil {
            case .regie: RegieView(chantier: chantier)
            case .bonLivraison: BonLivraisonView(chantierId: chantier?.id)
            case .releve: Releve3DView(chantierId: chantier?.id)
            }
        }
        // « Dis Siri, parler à Endry » : l'assistant s'ouvre une fois l'app déverrouillée.
        .onChange(of: DemandesRaccourcis.partage.enAttente, initial: true) { ouvrirAssistantDemande() }
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
            // Onglet caché ou écran plein par-dessus : ses animations (points en direct, orbe) s'arrêtent.
            .environment(\.animationsEnPause, !actif || app.ecranParDessus)
            // Fondu seul (sans mise à l'échelle) : l'écran n'est pas redessiné image par image pendant le changement.
            .opacity(actif ? 1 : 0)
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

    /// La conversation écrite / dictée avec l'assistant du bureau (depuis l'assistant vocal : il se ferme d'abord).
    func ouvrirConversation() {
        guard conversation != nil else { return }
        reglagesPresentes = false
        guard assistantPresente else {
            conversationPresentee = true
            return
        }
        fermerAssistant()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            conversationPresentee = true
        }
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

/// Identifiant d'une fiche de suivi présentée en feuille.
struct IdentifiantSuivi: Identifiable, Hashable {
    let id: String
}
