import EndryKit
import SwiftUI

/// Chantiers : filtres par étape, liste avec rail d'avancement, bloc « Sur les chantiers · 7 jours ».
struct ChantiersView: View {
    @Environment(ModeleApp.self) private var app
    var modele: ModeleChantiers

    @Namespace private var espaceFiltres
    @Namespace private var espaceZoom
    @State private var chemin: [Dossier] = []
    @State private var visible = false

    var body: some View {
        NavigationStack(path: $chemin) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Espace.m, pinnedViews: [.sectionHeaders]) {
                    Text("Chantiers")
                        .styleTitre(34, relativeTo: .largeTitle)
                        .foregroundStyle(Color.encre)
                        .padding(.top, Espace.m)
                        .padding(.horizontal, Espace.bord)

                    Section {
                        VStack(alignment: .leading, spacing: Espace.m) {
                            if modele.horsLigne {
                                BandeauHorsLigne(majLe: modele.majLe)
                            }
                            liste
                            if !modele.semaine.isEmpty {
                                SemaineChantiers(semaine: modele.semaine)
                                    .padding(.top, Espace.s)
                            }
                        }
                        .padding(.horizontal, Espace.bord)
                    } header: {
                        filtres
                    }
                }
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .tirerPourActualiser { await modele.actualiser() }
            .background(Color.fond)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Dossier.self) { dossier in
                DossierView(modele: ModeleDossier(dossier: dossier, api: app.session.api ?? APIDemo(), cache: app.session.estDemo ? nil : app.session.cache) { app.session.signaler($0) })
                    .navigationTransition(.zoom(sourceID: dossier.id, in: espaceZoom))
            }
        }
        .toast(Binding(get: { modele.toast }, set: { modele.toast = $0 }))
        .task {
            if modele.etat == .initial { await modele.charger() }
            visible = true
        }
    }

    private var filtres: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Espace.xs) {
                let etapes = modele.etapes.isEmpty
                    ? [CompteurEtape(cle: "tous", libelle: "Tous", nombre: 0)] + EtapeChantier.allCases.map { CompteurEtape(cle: $0.rawValue, libelle: $0.libelle, nombre: 0) }
                    : modele.etapes
                ForEach(etapes) { etape in
                    PuceFiltre(
                        libelle: etape.libelle,
                        nombre: modele.etapes.isEmpty ? nil : etape.nombre,
                        selectionne: modele.filtre == etape.cle,
                        espace: espaceFiltres
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            modele.filtre = etape.cle
                        }
                        Task { await modele.charger() }
                    }
                    .accessibilityIdentifier("filtre-\(etape.cle)")
                }
            }
            .padding(.horizontal, Espace.bord)
            .padding(.vertical, Espace.xs)
        }
        .background(Color.fond.opacity(0.94))
        .sensoryFeedback(.selection, trigger: modele.filtre)
    }

    @ViewBuilder
    private var liste: some View {
        switch modele.etat {
        case .initial, .chargement where modele.chantiers.isEmpty:
            ForEach(0..<3, id: \.self) { _ in Squelette(hauteur: 150, rayon: Espace.rayon) }
        case .erreur(let erreur) where modele.chantiers.isEmpty:
            VueErreur(erreur: erreur) { Task { await modele.charger() } }
        default:
            if modele.chantiers.isEmpty {
                EtatVide(titre: "Aucun chantier.", message: "Aucun dossier à cette étape pour le moment.", icone: "hammer")
            } else {
                ForEach(Array(modele.chantiers.enumerated()), id: \.element.id) { index, dossier in
                    NavigationLink(value: dossier) {
                        LigneChantier(dossier: dossier)
                            .matchedTransitionSource(id: dossier.id, in: espaceZoom)
                    }
                    .buttonStyle(.plain)
                    .transitionDefilement()
                    .apparitionEnCascade(index: index, visible: visible)
                    .accessibilityIdentifier("chantier-\(dossier.id)")
                }
            }
        }
    }
}

struct LigneChantier: View {
    var dossier: Dossier

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(dossier.client.isEmpty ? dossier.titre : dossier.client)
                    .styleTitre(19, relativeTo: .headline)
                    .foregroundStyle(Color.encre)
                Spacer()
                if let montant = dossier.montant {
                    MontantView(montant: montant, taille: 17, afficherCentimes: false, style: .headline)
                }
            }
            Text(dossier.titre)
                .styleTexte(14, relativeTo: .subheadline)
                .foregroundStyle(Color.encreDouce)
                .lineLimit(2)
            HStack(spacing: Espace.xs) {
                if let lieu = dossier.lieu {
                    Label(lieu, systemImage: "mappin.and.ellipse")
                        .styleTexte(12, relativeTo: .caption, graisse: .medium)
                        .foregroundStyle(Color.encrePale)
                }
                if let dates = dossier.dates {
                    Label(dates, systemImage: "calendar")
                        .styleTexte(12, relativeTo: .caption, graisse: .medium)
                        .foregroundStyle(Color.encrePale)
                }
                Spacer()
                if dossier.decisionEnAttente {
                    Pastille(texte: "Décision en attente", couleur: .bronze, icone: "circle.fill")
                }
            }
            .labelStyle(.titleAndIcon)

            RailAvancement(index: dossier.etapeIndex)
                .padding(.top, Espace.xxs)
            HStack {
                Text(dossier.etapeLibelle)
                    .styleTexte(12, relativeTo: .caption, graisse: .semibold)
                    .foregroundStyle(Color.bronze)
                Spacer()
                Text("Étape \(dossier.etapeIndex + 1) / 7")
                    .styleTexte(11, relativeTo: .caption2)
                    .foregroundStyle(Color.encrePale)
                    .monospacedDigit()
            }
        }
        .padding(Espace.l)
        .surfaceCarte()
        .contentShape(RoundedRectangle(cornerRadius: Espace.rayon, style: .continuous))
    }
}

#Preview("Chantiers — démo") {
    let app = ModeleApp()
    app.activerDemo()
    return ChantiersView(modele: app.chantiers!)
        .environment(app)
}
