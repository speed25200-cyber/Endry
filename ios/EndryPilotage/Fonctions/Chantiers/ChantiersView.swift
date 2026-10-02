import EndryKit
import SwiftUI

/// Chantiers : filtres par étape, liste avec rail d'avancement, bloc « Sur les chantiers · 7 jours ».
struct ChantiersView: View {
    @Environment(ModeleApp.self) private var app
    @AppStorage(ModeDevantClient.cle) private var devantClient = false
    var modele: ModeleChantiers

    @Namespace private var espaceFiltres
    @Namespace private var espaceZoom
    @State private var chemin: [Dossier] = []
    @State private var visible = false

    private func ouvrirCible() {
        guard let id = app.dossierCible, let dossier = modele.tous.first(where: { $0.id == id }) else { return }
        chemin = [dossier]
        app.dossierCible = nil
    }

    var body: some View {
        NavigationStack(path: $chemin) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Espace.m, pinnedViews: [.sectionHeaders]) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Chantiers").etiquetteMaison()
                            .frame(height: 34, alignment: .center)
                        Text(modele.tous.isEmpty ? "Les chantiers" : "\(modele.tous.count) dossiers")
                            .font(Police.serif(40, relativeTo: .largeTitle))
                            .foregroundStyle(Color.encre)
                            .contentTransition(.numericText(value: Double(modele.tous.count)))
                    }
                    .padding(.top, Espace.s)
                    .padding(.horizontal, Espace.bord)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    if !modele.tous.isEmpty {
                        pipeline
                            .padding(.horizontal, Espace.bord)
                    }

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
                .verrouillerLargeur()
            }
            .scrollIndicators(.hidden)
            .tirerPourActualiser { await modele.actualiser() }
            .background(FondMaison(discret: true))
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: app.dossierCible, initial: true) { _, _ in ouvrirCible() }
            // Lancement à froid : le chantier demandé arrive avec la liste.
            .onChange(of: modele.tous.count) { _, _ in ouvrirCible() }
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
        // Fiche ouverte : le sélecteur Pipeline / Planning s'efface (il chevauchait l'en-tête de la fiche).
        .onChange(of: chemin.isEmpty, initial: true) { _, vide in app.dossierOuvert = !vide }
        .task {
            if modele.etat == .initial { await modele.charger() }
            visible = true
        }
    }

    /// Supervision du carnet : dossiers par étape (toucher filtre), valeur des chantiers en cours.
    private var pipeline: some View {
        let comptes = EtapeChantier.allCases.map { etape in modele.tous.filter { $0.etapeIndex == etape.index }.count }
        let enCours = modele.tous.filter { (2...4).contains($0.etapeIndex) }
        let carnet = enCours.reduce(0) { $0 + ($1.montant ?? 0) }
        return VStack(alignment: .leading, spacing: 14) {
            LibelleInstrument(symbole: "chart.bar.xaxis", titre: "Carnet · \(enCours.count) en cours") {
                if !devantClient, carnet > 0 {
                    Text("CHF \(FormatSuisse.francs(carnet))")
                        .font(Police.mono(12))
                        .foregroundStyle(Color.encre)
                }
            }
            EntonnoirChantiers(comptes: comptes, selection: modele.filtre) { cle in
                withAnimation(.endry) { modele.choisir(cle) }
            }
        }
        .padding(16)
        .tuileMaison(rayon: 22)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("carnet-chantiers")
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
        .background(Color.fond.opacity(0.96))
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
                // Une colonne sur iPhone ; sur iPad, autant de cartes de front que la largeur le permet.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Adaptatif.carteChantier), spacing: Espace.m, alignment: .top)],
                          alignment: .leading, spacing: Espace.m) {
                    ForEach(Array(modele.chantiers.enumerated()), id: \.element.id) { index, dossier in
                        NavigationLink(value: dossier) {
                            LigneChantier(dossier: dossier)
                                .matchedTransitionSource(id: dossier.id, in: espaceZoom)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                        .transitionDefilement()
                        .apparitionEnCascade(index: index, visible: visible)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .accessibilityIdentifier("chantier-\(dossier.id)")
                    }
                }
            }
        }
    }
}

/// Tuile d'un chantier (Maison Endry) : client en Cinzel, objet en Cormorant, lieu et dates en mono,
/// montant à droite, avancement en sept segments, point crème si une décision attend.
struct LigneChantier: View {
    var dossier: Dossier

    var body: some View {
        let etapes = EtapeChantier.allCases.count
        let courant = min(max(dossier.etapeIndex, 0), etapes - 1)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(dossier.client.isEmpty ? "Chantier" : dossier.client)
                    .etiquetteMaison(10, couleur: .etiquette)
                    .lineLimit(1)
                Spacer(minLength: Espace.xs)
                if dossier.decisionEnAttente {
                    Circle().fill(Color.signal).frame(width: 8, height: 8)
                        .accessibilityLabel(Text("Décision en attente"))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Espace.s) {
                Text(objet)
                    .font(Police.serif(22, relativeTo: .title3))
                    .foregroundStyle(Color.encre)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Espace.xs)
                if let montant = dossier.montant {
                    Text(FormatSuisse.francs(montant))
                        .font(Police.serif(20, relativeTo: .headline))
                        .monospacedDigit()
                        .foregroundStyle(Color.encre)
                        .lineLimit(1)
                }
            }
            .padding(.top, 6)
            Text([dossier.lieu, dossier.dates].compactMap { $0 }.joined(separator: " · "))
                .font(Police.mono(11.5))
                .foregroundStyle(Color.encreDouce)
                .lineLimit(1)
                .padding(.top, 4)
            HStack(spacing: 3) {
                ForEach(0..<etapes, id: \.self) { index in
                    Capsule()
                        .fill(index < courant ? Color.encre : index == courant ? Color.signal : Color.filetFort)
                        .frame(height: 3)
                }
            }
            .padding(.top, 14)
            HStack {
                Text(dossier.etapeLibelle)
                Spacer()
                Text("Étape \(courant + 1) / \(etapes)")
            }
            .font(Police.mono(11.5))
            .foregroundStyle(Color.encreDouce)
            .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileMaison(rayon: 24)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// « Nicolas et Linda Favre — Ch. de la Croix 41 » : le client est déjà au-dessus, on garde l'objet.
    private var objet: String {
        let morceaux = dossier.titre.components(separatedBy: " — ")
        if morceaux.count > 1, morceaux[0].trimmingCharacters(in: .whitespaces) == dossier.client {
            let reste = morceaux.dropFirst().joined(separator: " — ")
            return reste.prefix(1).uppercased() + String(reste.dropFirst())
        }
        return dossier.titre
    }
}

#Preview("Chantiers — démo") {
    let app = ModeleApp()
    app.activerDemo()
    return ChantiersView(modele: app.chantiers!)
        .environment(app)
}
