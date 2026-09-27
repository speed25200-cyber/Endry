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
                            Label("L’assistant est en pause : vous pouvez tout consulter, les actions reprendront à la reprise.", systemImage: "pause.circle")
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
            .background(FondAmbiant())
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
        VStack(alignment: .leading, spacing: Espace.m) {
            HStack(alignment: .center) {
                Text((modele.accueil?.date ?? DateEndry.longue(Date())).capitalizedPremiere)
                    .font(Police.texte(12, relativeTo: .caption, graisse: .semibold))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(Color.or)
                Spacer()
                Button {
                    app.reglagesPresentes = true
                } label: {
                    ZStack {
                        Circle().fill(Color.surfaceCreuse)
                        Circle().strokeBorder(.degradeOr, lineWidth: 1)
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
            Text(modele.accueil?.salut ?? "Bonjour")
                .styleTitre(36, relativeTo: .largeTitle)
                .foregroundStyle(Color.encre)
                .fixedSize(horizontal: false, vertical: true)
            if let accueil = modele.accueil {
                apercu(accueil)
            }
        }
        .padding(.top, Espace.s)
    }

    /// Résumé du jour en pastilles de verre.
    private func apercu(_ accueil: Accueil) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Espace.xs) {
                PastilleApercu(icone: "checkmark.seal.fill", texte: "\(modele.nombreDecisions) à décider", accent: modele.nombreDecisions > 0)
                PastilleApercu(icone: "hammer.fill", texte: "\(accueil.chantiers7Jours.count) chantiers cette semaine", accent: false)
                if !accueil.payer.cetteSemaine.isEmpty {
                    PastilleApercu(icone: "calendar.badge.clock", texte: "\(accueil.payer.cetteSemaine.count) paiements sous 7 j", accent: false)
                }
                if accueil.encaisser.anciennete.plus30 > 0 {
                    PastilleApercu(icone: "exclamationmark.triangle.fill", texte: "\(FormatSuisse.chfArrondi(accueil.encaisser.anciennete.plus30)) > 30 j", accent: false, alerte: true)
                }
            }
        }
        .scrollClipDisabled()
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
                    app.onglet = .finances
                }
                .apparitionEnCascade(index: 1, visible: visible)

                if !accueil.chantiers7Jours.isEmpty {
                    AgendaSemaine(semaine: accueil.chantiers7Jours) {
                        app.vueChantiers = .planning
                        app.onglet = .chantiers
                    }
                        .apparitionEnCascade(index: 2, visible: visible)
                }

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

            }
        }
    }
}

/// Pastille de résumé en verre.
struct PastilleApercu: View {
    var icone: String
    var texte: String
    var accent: Bool
    var alerte = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icone).font(.system(size: 11, weight: .bold))
            Text(texte).styleTexte(12, relativeTo: .caption, graisse: .semibold)
        }
        .foregroundStyle(alerte ? Color.rouille : accent ? Color.espressoProfond : Color.encreDouce)
        .padding(.horizontal, 12)
        .frame(minHeight: 30)
        .background {
            if accent {
                Capsule().fill(.degradeOr)
            } else {
                Capsule().fill(Color.surfaceCreuse)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 0.6))
            }
        }
    }
}

/// Agenda des 7 prochains jours : cartes horizontales qui s'effacent en glissant.
struct AgendaSemaine: View {
    var semaine: [Semaine]
    var ouvrir: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: "Cette semaine", detail: "sur les chantiers", action: ouvrir, libelleAction: "Planning")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Espace.s) {
                    ForEach(semaine) { item in
                        CarteJour(item: item)
                            .scrollTransition(.interactive, axis: .horizontal) { contenu, phase in
                                contenu
                                    .scaleEffect(phase.isIdentity ? 1 : 0.92)
                                    .opacity(phase.isIdentity ? 1 : 0.55)
                                    .rotation3DEffect(.degrees(phase.value * -8), axis: (x: 0, y: 1, z: 0))
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}

private struct CarteJour: View {
    var item: Semaine

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let date = item.dateDebut {
                    Text("\(DateEndry.numeroJour(date))")
                        .styleTitre(34, relativeTo: .largeTitle)
                        .foregroundStyle(.texteOr)
                    Text(DateEndry.jourAbrege(date))
                        .font(Police.texte(12, relativeTo: .caption, graisse: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.encreDouce)
                } else {
                    Image(systemName: "calendar").foregroundStyle(Color.or)
                }
            }
            Text(item.titre)
                .styleTexte(14, relativeTo: .subheadline, graisse: .semibold)
                .foregroundStyle(Color.encre)
                .lineLimit(2, reservesSpace: true)
            Label([item.lieu, item.dates].compactMap { $0 }.joined(separator: " · "), systemImage: "mappin.and.ellipse")
                .styleTexte(11, relativeTo: .caption2)
                .foregroundStyle(Color.encrePale)
                .lineLimit(1)
        }
        .padding(Espace.m)
        .frame(width: 210, alignment: .leading)
        .surfaceCarte(rayon: 24)
        .accessibilityElement(children: .combine)
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
        .preferredColorScheme(.dark)
}
