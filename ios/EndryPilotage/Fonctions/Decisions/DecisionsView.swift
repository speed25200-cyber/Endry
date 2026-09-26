import EndryKit
import SwiftUI

/// Écran principal : salutation, carte héros « À encaisser », puis les décisions à prendre.
struct DecisionsView: View {
    @Environment(ModeleApp.self) private var app
    var modele: ModeleDecisions

    @State private var visible = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { lecteur in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Espace.l) {
                        entete
                            .apparitionEnCascade(index: 0, visible: visible)

                        if modele.horsLigne {
                            BandeauHorsLigne(majLe: modele.majLe)
                        }
                        if let accueil = modele.accueil, accueil.pause {
                            Label("L’assistant est en pause : les décisions seront traitées à la reprise.", systemImage: "pause.circle")
                                .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                                .foregroundStyle(Color.ambre)
                                .padding(Espace.m)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.ambre.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        contenu(lecteur: lecteur)
                    }
                    .padding(.horizontal, Espace.bord)
                    .padding(.top, Espace.xs)
                    .padding(.bottom, 120)
                    .animation(.spring(response: 0.5, dampingFraction: 0.82), value: modele.cartes.map(\.id))
                }
                .scrollIndicators(.hidden)
                .tirerPourActualiser { await modele.charger() }
                .onChange(of: app.referenceCiblee) { _, reference in
                    guard let reference else { return }
                    withAnimation(.spring) { lecteur.scrollTo(reference, anchor: .top) }
                }
            }
            .background(Color.fond)
            .toolbar(.hidden, for: .navigationBar)
        }
        .toast(Binding(get: { modele.toast }, set: { modele.toast = $0 }))
        .sensoryFeedback(.success, trigger: modele.nombreDecisions) { ancien, nouveau in nouveau < ancien }
        .task {
            if modele.etat == .initial { await modele.charger() }
            visible = true
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Espace.xxs) {
                Text(modele.accueil?.date ?? DateEndry.longue(Date()))
                    .styleSurtitre()
                Text(modele.accueil?.salut ?? "Bonjour")
                    .styleTitre(32, relativeTo: .largeTitle)
                    .foregroundStyle(Color.encre)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Espace.m)
            Button {
                app.reglagesPresentes = true
            } label: {
                ZStack {
                    Circle().fill(Color.espresso)
                    Text("E").font(Police.titre(17, relativeTo: .body)).foregroundStyle(.degradeOr)
                    if app.session.estDemo {
                        Circle().fill(Color.or).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color.fond, lineWidth: 2))
                            .offset(x: 14, y: -14)
                    }
                }
                .frame(width: 40, height: 40)
            }
            .accessibilityLabel(Text("Réglages"))
            .accessibilityIdentifier("bouton-reglages")
        }
        .padding(.top, Espace.m)
    }

    // MARK: - Contenu

    @ViewBuilder
    private func contenu(lecteur: ScrollViewProxy) -> some View {
        switch modele.etat {
        case .initial, .chargement where modele.accueil == nil:
            Squelette(hauteur: 250, rayon: Espace.rayon)
            SqueletteCarte()
            SqueletteCarte()
        case .erreur(let erreur) where modele.accueil == nil:
            VueErreur(erreur: erreur) { Task { await modele.charger() } }
        default:
            if let accueil = modele.accueil {
                CarteHeros(encaisser: accueil.encaisser, offres: accueil.offres, payer: accueil.payer) {
                    app.onglet = .argent
                }
                .apparitionEnCascade(index: 1, visible: visible)

                HStack(alignment: .firstTextBaseline, spacing: Espace.xs) {
                    Text("À décider").styleTitre(24, relativeTo: .title2).foregroundStyle(Color.encre)
                    Text("\(modele.nombreDecisions)")
                        .styleTitre(24, relativeTo: .title2)
                        .foregroundStyle(Color.bronze)
                        .contentTransition(.numericText(value: Double(modele.nombreDecisions)))
                    Spacer()
                    if !modele.decisionsAutorisees {
                        Pastille(texte: "Lecture seule", couleur: .ambre, icone: "lock.fill")
                    }
                }
                .padding(.top, Espace.xs)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("titre-a-decider")
                .apparitionEnCascade(index: 2, visible: visible)

                if modele.cartes.isEmpty {
                    EtatVide(titre: "Rien à décider.", message: "L’assistant vous préviendra dès qu’une proposition attend votre accord.")
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    ForEach(Array(modele.cartes.enumerated()), id: \.element.id) { index, carte in
                        CarteDecisionView(
                            carte: carte,
                            actionsPossibles: modele.actionsPossibles,
                            enCours: modele.enCours.contains(carte.reference),
                            enAvant: app.referenceCiblee == carte.reference,
                            agir: { action, consignes in await modele.agir(action, sur: carte, consignes: consignes) },
                            ouvrirPiece: { piece in
                                Task { await app.documents.ouvrir(piece.url, nom: piece.nom, api: app.session.api) }
                            }
                        )
                        .id(carte.reference)
                        .transitionDefilement()
                        .apparitionEnCascade(index: index + 3, visible: visible)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.92))
                        ))
                    }
                }

                if !accueil.chantiers7Jours.isEmpty {
                    SemaineChantiers(semaine: accueil.chantiers7Jours)
                        .padding(.top, Espace.s)
                }
            }
        }
    }
}

/// Bloc « Sur les chantiers · 7 jours ».
struct SemaineChantiers: View {
    var semaine: [Semaine]

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: "Sur les chantiers", detail: "7 jours")
            VStack(spacing: 0) {
                ForEach(Array(semaine.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: Espace.m) {
                        VStack(spacing: 0) {
                            if let date = item.dateDebut {
                                Text(DateEndry.jourAbrege(date)).styleTexte(11, relativeTo: .caption2, graisse: .semibold)
                                    .foregroundStyle(Color.encrePale)
                                    .textCase(.uppercase)
                                Text("\(DateEndry.numeroJour(date))").styleTitre(22, relativeTo: .title3)
                                    .foregroundStyle(Color.encre)
                            } else {
                                Image(systemName: "calendar").foregroundStyle(Color.encrePale)
                            }
                        }
                        .frame(width: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.titre).styleTexte(15, relativeTo: .subheadline, graisse: .semibold).foregroundStyle(Color.encre)
                            Text([item.lieu, item.dates].compactMap { $0 }.joined(separator: " · "))
                                .styleTexte(13, relativeTo: .footnote)
                                .foregroundStyle(Color.encreDouce)
                        }
                        Spacer()
                    }
                    .padding(.vertical, Espace.s)
                    .accessibilityElement(children: .combine)
                    if index < semaine.count - 1 {
                        Rectangle().fill(Color.filet).frame(height: 0.5).padding(.leading, 60)
                    }
                }
            }
            .padding(.horizontal, Espace.m)
            .padding(.vertical, Espace.xs)
            .surfaceCarte(rayon: 22)
        }
    }
}

#Preview("Décisions — démo") {
    let app = ModeleApp()
    app.activerDemo()
    return DecisionsView(modele: app.decisions!)
        .environment(app)
}
