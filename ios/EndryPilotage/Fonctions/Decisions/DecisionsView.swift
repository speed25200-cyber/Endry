import EndryKit
import SwiftUI

/// Écran « Aujourd'hui » : salutation, résumé en une phrase, pile de décisions,
/// argent de la semaine, chantiers des prochains jours. L'en-tête se condense au défilement.
struct DecisionsView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations
    var modele: ModeleDecisions

    @State private var visible = false
    @State private var condense = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Espace.l) {
                    entete
                        .apparitionEnCascade(index: 0, visible: visible)

                    if modele.horsLigne {
                        BandeauHorsLigne(majLe: modele.majLe)
                    }
                    if modele.enPause {
                        BandeauPause()
                    }

                    contenu
                }
                .padding(.horizontal, Espace.bord)
                .padding(.top, Espace.xs)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .tirerPourActualiser { await modele.charger() }
            .onScrollGeometryChange(for: Bool.self) { geometrie in
                geometrie.contentOffset.y + geometrie.contentInsets.top > 96
            } action: { _, nouveau in
                withAnimation(.endry(reduire: reduireAnimations)) { condense = nouveau }
            }
            .overlay(alignment: .top) {
                if condense {
                    EnTeteCondense(titre: "Aujourd’hui", detail: modele.nombreDecisions > 0 ? "\(modele.nombreDecisions) à décider" : nil)
                        .transition(.move(edge: .top).combined(with: .opacity))
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
        VStack(alignment: .leading, spacing: Espace.s) {
            HStack(alignment: .center) {
                Text((modele.accueil?.date ?? DateEndry.longue(Date())).capitalizedPremiere)
                    .font(Police.texte(11, relativeTo: .caption2, graisse: .semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Color.bronze)
                Spacer()
                Button {
                    app.reglagesPresentes = true
                } label: {
                    ZStack {
                        Circle().fill(Color.surface)
                        Circle().strokeBorder(Color.bordureOr, lineWidth: Espace.filet)
                        Text("E").font(Police.titre(17, relativeTo: .body)).foregroundStyle(.degradeOr)
                        if app.session.estDemo {
                            Circle().fill(Color.or).frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Color.fond, lineWidth: 2))
                                .offset(x: 15, y: -15)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text(app.session.estDemo ? "Réglages, mode démo" : "Réglages"))
                .accessibilityIdentifier("bouton-reglages")
            }
            Text(modele.accueil?.salut ?? "Bonjour")
                .styleTitre(34, relativeTo: .largeTitle)
                .foregroundStyle(Color.encre)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let accueil = modele.accueil {
                Text(ResumeDuJour.phrase(accueil: accueil, decisions: modele.nombreDecisions))
                    .styleTexte(17, relativeTo: .body)
                    .foregroundStyle(Color.encreDouce)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("resume-du-jour")
            } else {
                Squelette(hauteur: 17, largeur: 260)
            }
        }
        .padding(.top, Espace.s)
    }

    // MARK: - Contenu

    @ViewBuilder
    private var contenu: some View {
        switch modele.etat {
        case .chargement where modele.accueil == nil, .initial:
            SqueletteCarte()
            Squelette(hauteur: 220, rayon: Espace.rayon)
        case .erreur(let erreur) where modele.accueil == nil:
            VueErreur(erreur: erreur) { Task { await modele.charger() } }
        default:
            if let accueil = modele.accueil {
                titreDecisions
                    .apparitionEnCascade(index: 1, visible: visible)

                Group {
                    if modele.cartes.isEmpty {
                        EtatVide(titre: "Rien à décider. Tout roule.",
                                 message: "L’assistant vous préviendra dès qu’une proposition attendra votre accord.")
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        PileDecisions(modele: modele)
                    }
                }
                .apparitionEnCascade(index: 2, visible: visible)

                VStack(alignment: .leading, spacing: Espace.s) {
                    EnTeteSection(titre: "L’argent de la semaine", action: { app.onglet = .finances }, libelleAction: "Finances")
                    CarteHeros(encaisser: accueil.encaisser, offres: accueil.offres, payer: accueil.payer) {
                        app.onglet = .finances
                    }
                }
                .transitionDefilement()
                .apparitionEnCascade(index: 3, visible: visible)

                if !accueil.chantiers7Jours.isEmpty {
                    AgendaSemaine(semaine: accueil.chantiers7Jours) {
                        app.vueChantiers = .planning
                        app.onglet = .chantiers
                    }
                    .transitionDefilement()
                    .apparitionEnCascade(index: 4, visible: visible)
                }
            }
        }
    }

    private var titreDecisions: some View {
        HStack(alignment: .firstTextBaseline, spacing: Espace.xs) {
            Text("À décider").styleTitre(28, relativeTo: .title).foregroundStyle(Color.encre)
            Text("\(modele.nombreDecisions)")
                .font(Police.chiffres(28, relativeTo: .title, graisse: .medium))
                .foregroundStyle(Color.bronze)
                .contentTransition(.numericText(value: Double(modele.nombreDecisions)))
            Spacer()
            if !modele.decisionsAutorisees {
                Pastille(texte: "Lecture seule", couleur: .ambre, icone: "lock.fill")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("titre-a-decider")
    }
}

/// Résumé du jour en une phrase, calculé à partir de l'accueil.
enum ResumeDuJour {
    static func phrase(accueil: Accueil, decisions: Int) -> String {
        var morceaux: [String] = []
        switch decisions {
        case 0: morceaux.append("Aucune décision en attente")
        case 1: morceaux.append("Une décision vous attend")
        default: morceaux.append("\(decisions) décisions vous attendent")
        }
        let chantiers = accueil.chantiers7Jours.count
        if chantiers > 0 {
            morceaux.append(chantiers == 1 ? "un chantier cette semaine" : "\(chantiers) chantiers cette semaine")
        }
        if accueil.payer.totalSemaine > 0 {
            morceaux.append("\(FormatSuisse.chfArrondi(accueil.payer.totalSemaine)) à payer sous 7 jours")
        }
        guard morceaux.count > 1 else { return morceaux[0] + "." }
        let fin = morceaux.removeLast()
        return morceaux.joined(separator: ", ") + " et " + fin + "."
    }
}

/// Bandeau « assistant en pause » : on lit tout, les actions attendent la reprise.
struct BandeauPause: View {
    var body: some View {
        Label("L’assistant est en pause : vous pouvez tout consulter, les actions reprendront à la reprise.", systemImage: "pause.circle")
            .styleTexte(15, relativeTo: .subheadline, graisse: .medium)
            .foregroundStyle(Color.ambre)
            .padding(Espace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ambre.opacity(0.12), in: RoundedRectangle(cornerRadius: Espace.rayonPetit, style: .continuous))
            .accessibilityIdentifier("bandeau-pause")
    }
}

/// En-tête condensé : apparaît en verre quand le grand titre sort de l'écran.
struct EnTeteCondense: View {
    var titre: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Espace.xs) {
            Text(titre).styleTitre(17, relativeTo: .headline).foregroundStyle(Color.encre)
            if let detail {
                Text(detail).styleTexte(13, relativeTo: .footnote, graisse: .medium).foregroundStyle(Color.bronze)
            }
            Spacer()
        }
        .padding(.horizontal, Espace.bord)
        .padding(.vertical, Espace.s)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.bordureOr).frame(height: Espace.filet) }
                .ignoresSafeArea(edges: .top)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
                    .overlay(Capsule().strokeBorder(Color.bordureOr, lineWidth: Espace.filet))
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
