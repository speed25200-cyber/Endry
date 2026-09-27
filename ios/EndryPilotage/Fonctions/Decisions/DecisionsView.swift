import EndryKit
import SwiftUI

/// Écran « Aujourd'hui », style Galerie : photo de réalisation Endry en plein écran, logo, salutation,
/// puis une feuille brune qui monte avec le carrousel des décisions (cartes papier), l'argent de la semaine
/// et les chantiers. Toucher une carte ouvre sa fiche complète.
struct DecisionsView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations
    var modele: ModeleDecisions

    @State private var visible = false
    /// Position de défilement lue seulement par la photo et la barre du haut : le reste de l'écran
    /// n'est pas réévalué à chaque image.
    @State private var suivi = SuiviDefilement()
    @State private var carteVisible: String?
    @State private var fiche: Carte?
    @Namespace private var zoom

    private let hauteurPhoto: CGFloat = 520

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.espresso.ignoresSafeArea()
                PhotoAccueil(suivi: suivi, hauteur: hauteurPhoto)

                ScrollView {
                    VStack(spacing: 0) {
                        entete
                            .frame(height: hauteurPhoto - 150, alignment: .bottom)
                        FeuilleMaison {
                            feuille
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .tirerPourActualiser { await modele.charger() }
                .onScrollGeometryChange(for: CGFloat.self) { geometrie in
                    // Au-delà de la photo, plus rien ne bouge : inutile de suivre.
                    min(geometrie.contentOffset.y + geometrie.contentInsets.top, 700)
                } action: { _, valeur in
                    suivi.y = valeur
                }
            }
            .overlay(alignment: .top) {
                BarreHauteAccueil(suivi: suivi) { barreHaute }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .toast(Binding(get: { modele.toast }, set: { modele.toast = $0 }))
        .sensoryFeedback(.success, trigger: modele.nombreDecisions) { ancien, nouveau in nouveau < ancien }
        .sheet(item: $fiche) { carte in
            // La carte du carrousel grandit jusqu'à devenir la fiche.
            FicheDecision(carte: carte, modele: modele)
                .navigationTransition(.zoom(sourceID: carte.reference, in: zoom))
        }
        .onChange(of: app.referenceCiblee) { _, reference in
            guard let reference else { return }
            withAnimation(.endry(reduire: reduireAnimations)) { carteVisible = reference }
            if let carte = modele.cartes.first(where: { $0.reference == reference }) { fiche = carte }
        }
        .task {
            if modele.etat == .initial { await modele.charger() }
            visible = true
        }
    }

    // MARK: - En-tête sur la photo

    /// Logo et réglages, fixes ; s'estompent quand la feuille recouvre la photo.
    private var barreHaute: some View {
        HStack(alignment: .center) {
            LogoMarque(largeur: 150)
            Spacer()
            Button {
                app.reglagesPresentes = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.or)
                    .frame(width: 44, height: 44)
                    .background(Color.espresso.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(Color.or.opacity(0.4), lineWidth: Espace.filet))
            }
            .accessibilityLabel(Text(app.session.estDemo ? "Réglages, mode démo" : "Réglages"))
            .accessibilityIdentifier("bouton-reglages")
        }
        .padding(.horizontal, Espace.bord + 4)
        .padding(.top, Espace.xs)
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            Text((modele.accueil?.date ?? DateEndry.longue(Date())).capitalizedPremiere)
                .font(Police.etiquette(Echelle.micro))
                .textCase(.uppercase)
                .tracking(2.4)
                .foregroundStyle(Color.or)
                .apparitionEnCascade(index: 0, visible: visible)
            Text(salutation.debut)
                .styleTitre(34, relativeTo: .largeTitle, graisse: .medium)
                .foregroundStyle(Color(hex: 0xF7F2E9))
                .apparitionEnCascade(index: 1, visible: visible)
            Text(salutation.fin)
                .styleTitre(34, relativeTo: .largeTitle, graisse: .italique)
                .foregroundStyle(Color.or)
                .fixedSize(horizontal: false, vertical: true)
                .apparitionEnCascade(index: 2, visible: visible)
                .accessibilityAddTraits(.isHeader)
            if let accueil = modele.accueil {
                Text(ResumeDuJour.phrase(accueil: accueil, decisions: modele.nombreDecisions))
                    .styleTexte(15, relativeTo: .subheadline)
                    .foregroundStyle(Color(hex: 0xE9DFCF))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .apparitionEnCascade(index: 3, visible: visible)
                    .accessibilityIdentifier("resume-du-jour")
            }
            BoutonParlerEndry { app.ouvrirAssistant() }
                .padding(.top, Espace.s)
                .apparitionEnCascade(index: 4, visible: visible)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Espace.bord + 4)
        .padding(.bottom, Espace.l)
        .environment(\.colorScheme, .dark)
    }

    /// « Bonjour, » puis le nom en italique doré (le serveur envoie « Bonjour Monsieur Endry »).
    private var salutation: (debut: String, fin: String) {
        let brut = modele.accueil?.salut ?? "Bonjour"
        let mots = brut.split(separator: " ", maxSplits: 1).map(String.init)
        guard mots.count == 2 else { return (brut, "") }
        let debut = mots[0].hasSuffix(",") ? mots[0] : mots[0] + ","
        return (debut, mots[1])
    }

    // MARK: - Feuille

    @ViewBuilder
    private var feuille: some View {
        VStack(alignment: .leading, spacing: Espace.l) {
            if modele.horsLigne {
                BandeauHorsLigne(majLe: modele.majLe)
                    .padding(.horizontal, Espace.bord)
            }
            if modele.enPause {
                BandeauPause()
                    .padding(.horizontal, Espace.bord)
            }
            switch modele.etat {
            case .chargement where modele.accueil == nil, .initial:
                Squelette(hauteur: 250, rayon: Espace.rayon).padding(.horizontal, Espace.bord)
            case .erreur(let erreur) where modele.accueil == nil:
                VueErreur(erreur: erreur) { Task { await modele.charger() } }
            default:
                decisions
                if let agents = app.agents {
                    BandeauBureau(modele: agents) { app.onglet = .entreprise }
                        .padding(.horizontal, Espace.bord)
                        .transitionDefilement()
                        .task { if !agents.charge { await agents.charger() } }
                }
                if let accueil = modele.accueil {
                    ResumeArgent(accueil: accueil) { app.onglet = .finances }
                        .padding(.horizontal, Espace.bord)
                        .transitionDefilement()
                    if !accueil.chantiers7Jours.isEmpty {
                        ChantiersSemaine(semaine: accueil.chantiers7Jours) {
                            app.vueChantiers = .planning
                            app.onglet = .chantiers
                        }
                        .transitionDefilement()
                    }
                }
            }
        }
        .padding(.top, Espace.l)
        .padding(.bottom, 130)
    }

    private var indexVisible: Int {
        modele.cartes.firstIndex { $0.reference == carteVisible } ?? 0
    }

    @ViewBuilder
    private var decisions: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            HStack(alignment: .center) {
                Text("À décider · \(modele.nombreDecisions)")
                    .font(Police.etiquette(12, relativeTo: .caption))
                    .textCase(.uppercase)
                    .tracking(2.4)
                    .foregroundStyle(Color.bronze)
                    .contentTransition(.numericText(value: Double(modele.nombreDecisions)))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("titre-a-decider")
                Spacer()
                if !modele.decisionsAutorisees {
                    Pastille(texte: "Lecture seule", couleur: .ambre, icone: "lock.fill")
                } else if modele.cartes.count > 1 {
                    PointsPagination(nombre: modele.cartes.count, actif: indexVisible)
                }
            }
            .padding(.horizontal, Espace.bord + 4)

            if modele.cartes.isEmpty {
                EtatVide(titre: "Rien à décider. Tout roule.",
                         message: "L’assistant vous préviendra dès qu’une proposition attendra votre accord.")
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Espace.s) {
                        ForEach(modele.cartes) { carte in
                            CarteApercuDecision(
                                carte: carte,
                                actionsPossibles: modele.actionsPossibles,
                                enCours: modele.enCours.contains(carte.reference),
                                ouvrir: { fiche = carte },
                                agir: { action in await modele.agir(action, sur: carte) }
                            )
                            .containerRelativeFrame(.horizontal) { largeur, _ in largeur * 0.82 }
                            .matchedTransitionSource(id: carte.reference, in: zoom)
                            .scrollTransition(.interactive, axis: .horizontal) { contenu, phase in
                                contenu
                                    .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                    .opacity(phase.isIdentity ? 1 : 0.7)
                            }
                            .id(carte.reference)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, Espace.s)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .contentMargins(.horizontal, Espace.bord + 4, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $carteVisible)
                .animation(.endry(reduire: reduireAnimations), value: modele.cartes.map(\.reference))
                .accessibilityIdentifier("carrousel-decisions")
            }
        }
    }
}

/// Position de défilement de l'accueil, observée par les seules vues qui en dépendent.
@MainActor
@Observable
final class SuiviDefilement {
    var y: CGFloat = 0
}

/// Photo de l'accueil : s'étire quand on tire, glisse en parallaxe quand on défile.
private struct PhotoAccueil: View {
    var suivi: SuiviDefilement
    var hauteur: CGFloat

    var body: some View {
        let y = suivi.y
        PhotoVivante(nom: PhotosMarque.accueil, ancre: UnitPoint(x: 0.4, y: 0.5))
            .frame(height: hauteur + max(0, -y))
            .overlay(VoilePhoto(haut: 0.7, bas: 0.95))
            .offset(y: y > 0 ? -y * 0.35 : 0)
            .ignoresSafeArea(edges: .top)
    }
}

/// Logo et réglages : s'estompent quand la feuille recouvre la photo.
private struct BarreHauteAccueil<Contenu: View>: View {
    var suivi: SuiviDefilement
    @ViewBuilder var contenu: Contenu

    var body: some View {
        let opacite = max(0, 1 - suivi.y / 220)
        contenu
            .opacity(opacite)
            .allowsHitTesting(opacite > 0.1)
    }
}

/// « Parler à Endry » : l'assistant vocal à portée de pouce, avec une onde d'or qui respire.
struct BoutonParlerEndry: View {
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        Button(action: action) {
            HStack(spacing: Espace.xs) {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating,
                                  isActive: !reduireAnimations && !Configuration.testsUI)
                Text("Parler à Endry")
                    .styleTexte(15, relativeTo: .subheadline, graisse: .semibold)
            }
            .foregroundStyle(Color.espresso)
            .padding(.horizontal, Espace.m)
            .frame(minHeight: 44)
            .background {
                Capsule().fill(.degradeOr).shadow(color: Color.or.opacity(0.35), radius: 14, y: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Ouvre l’assistant vocal : posez une question ou dictez une demande"))
        .accessibilityIdentifier("parler-endry")
    }
}

/// L'argent de la semaine : à encaisser en grand, à payer et offres en attente ; ouvre les Finances.
struct ResumeArgent: View {
    var accueil: Accueil
    var ouvrir: () -> Void

    var body: some View {
        Button(action: ouvrir) {
            VStack(alignment: .leading, spacing: Espace.m) {
                HStack {
                    Text("L’argent de la semaine").styleSurtitre()
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.bronze)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("À encaisser").styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
                    MontantAnime(montant: accueil.encaisser.total, taille: 34, afficherCentimes: false)
                }
                HStack(spacing: Espace.s) {
                    chiffre("À payer · 7 jours", accueil.payer.totalSemaine)
                    Rectangle().fill(Color.filet).frame(width: Espace.filet, height: 34)
                    chiffre("Offres en attente", accueil.offres.total)
                }
            }
            .padding(Espace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCarte(rayon: Espace.rayon)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Ouvre l’espace Finances"))
    }

    private func chiffre(_ titre: String, _ montant: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
            Text(FormatSuisse.chfArrondi(montant))
                .font(Police.chiffres(17, relativeTo: .headline))
                .foregroundStyle(Color.encre)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Chantiers de la semaine : cartes avec la photo de la réalisation ; ouvre le Planning.
struct ChantiersSemaine: View {
    var semaine: [Semaine]
    var ouvrir: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            HStack {
                Text("Cette semaine").styleSurtitre()
                Spacer()
                Button("Planning", action: ouvrir)
                    .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                    .foregroundStyle(Color.bronze)
            }
            .padding(.horizontal, Espace.bord + 4)
            ScrollView(.horizontal) {
                HStack(spacing: Espace.s) {
                    ForEach(semaine) { item in
                        Button(action: ouvrir) {
                            HStack(spacing: Espace.s) {
                                Image(PhotosMarque.pour(id: item.id))
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    if let date = item.dateDebut {
                                        Text("\(DateEndry.jourAbrege(date)) \(DateEndry.numeroJour(date))")
                                            .font(Police.etiquette(Echelle.micro))
                                            .textCase(.uppercase)
                                            .tracking(1.6)
                                            .foregroundStyle(Color.bronze)
                                    }
                                    Text(item.titre)
                                        .styleTexte(14, relativeTo: .subheadline, graisse: .semibold)
                                        .foregroundStyle(Color.encre)
                                        .lineLimit(2)
                                    if let lieu = item.lieu {
                                        Text(lieu).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
                                    }
                                }
                                .frame(width: 150, alignment: .leading)
                            }
                            .padding(Espace.s)
                            .surfaceCarte(rayon: Espace.rayonPetit)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .contentMargins(.horizontal, Espace.bord + 4, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
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
