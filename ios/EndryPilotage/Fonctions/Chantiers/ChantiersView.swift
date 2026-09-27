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
            .background(FondAmbiant())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Dossier.self) { dossier in
                Group {
                    // Jamais de repli sur la démo en mode réel : sans client API, on l'explique.
                    if let api = app.session.api {
                        DossierView(modele: ModeleDossier(dossier: dossier, api: api, cache: app.session.estDemo ? nil : app.session.cache) { app.session.signaler($0) })
                    } else {
                        VueErreur(erreur: .nonAuthentifie(nil)) { app.connexionPresentee = true }
                    }
                }
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
                    : modele.compteurs
                ForEach(etapes) { etape in
                    PuceFiltre(
                        libelle: etape.libelle,
                        nombre: modele.etapes.isEmpty ? nil : etape.nombre,
                        selectionne: modele.filtre == etape.cle,
                        espace: espaceFiltres
                    ) {
                        withAnimation(.endry) {
                            modele.choisir(etape.cle)
                        }
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
        case .chargement where modele.chantiers.isEmpty, .initial:
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
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .accessibilityIdentifier("chantier-\(dossier.id)")
                }
            }
        }
    }
}

struct LigneChantier: View {
    var dossier: Dossier

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                CompositionMaison(motif: PhotosMarque.pour(id: dossier.id), graine: PhotosMarque.graine(dossier.id))
                    .frame(height: 118)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(VoilePhoto(haut: 0.15, bas: 0.85))
                    .accessibilityHidden(true)
                HStack(alignment: .lastTextBaseline) {
                    Text(dossier.client.isEmpty ? dossier.titre : dossier.client)
                        .styleTitre(22, relativeTo: .title3)
                        .foregroundStyle(Color(hex: 0xF7F2E9))
                        .lineLimit(1)
                    Spacer()
                    if let montant = dossier.montant {
                        Text(FormatSuisse.chfArrondi(montant))
                            .font(Police.chiffres(15, relativeTo: .subheadline))
                            .foregroundStyle(Color.or)
                    }
                }
                .padding(.horizontal, Espace.m)
                .padding(.bottom, Espace.s)
            }

            VStack(alignment: .leading, spacing: Espace.s) {
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
            .padding(Espace.m)
        }
        .clipShape(RoundedRectangle(cornerRadius: Espace.rayon, style: .continuous))
        .surfaceCarte()
        .contentShape(RoundedRectangle(cornerRadius: Espace.rayon, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Chantiers — démo") {
    let app = ModeleApp()
    app.activerDemo()
    return ChantiersView(modele: app.chantiers!)
        .environment(app)
}
