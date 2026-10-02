import EndryKit
import SwiftUI

/// Accueil « Maison Endry » (maquette E) : en-tête et statut du bureau en direct, salutation, frise de la semaine,
/// pile « À décider » à glisser, outils de terrain, tuiles Finances et Chantiers, briefing du jour.
/// Fond brun profond (ou papier) éclairé en haut par la photo d'ambiance fondue.
struct DecisionsView: View {
    @AppStorage(Salutation.clePrenom) private var prenomPatron = ""
    @Environment(ModeleApp.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations
    var modele: ModeleDecisions

    @State private var visible = false
    @State private var carteVisible: String?
    @State private var fiche: Carte?
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                FondMaison()
                ScrollView {
                    contenu
                        .largeurLisible(Adaptatif.ecran)
                        .padding(.bottom, 130)
                        .verrouillerLargeur()
                }
                .scrollIndicators(.hidden)
                .tirerPourActualiser { await modele.charger() }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .toast(Binding(get: { modele.toast }, set: { modele.toast = $0 }))
        .sensoryFeedback(.success, trigger: modele.nombreDecisions) { ancien, nouveau in nouveau < ancien }
        .sheet(item: $fiche) { carte in
            // La tuile grandit jusqu'à devenir la fiche.
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

    /// Reprise depuis le bandeau de pause (serveur v1.1 et plus).
    private var repriseAssistant: (() async -> Void)? {
        guard let pilotage = app.pilotage, pilotage.disponible else { return nil }
        return { _ = await pilotage.reprendre() }
    }

    @ViewBuilder
    private var contenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnTeteMaison(initiale: prenom.first.map { String($0).uppercased() })
                .padding(.horizontal, Espace.bord)
                .padding(.top, 4)
                .apparitionEnCascade(index: 0, visible: visible)

            if let agents = app.agents {
                StatutBureau(modele: agents) { app.onglet = .entreprise }
                    .padding(.horizontal, Espace.bord)
                    .padding(.top, 12)
                    .apparitionEnCascade(index: 1, visible: visible)
                    .task { if !agents.charge { await agents.charger() } }
            }

            salutation
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .apparitionEnCascade(index: 2, visible: visible)

            if modele.horsLigne {
                BandeauHorsLigne(majLe: modele.majLe)
                    .padding(.horizontal, Espace.bord)
                    .padding(.top, Espace.s)
            }
            if modele.enPause {
                BandeauPause(reprendre: repriseAssistant)
                    .padding(.horizontal, Espace.bord)
                    .padding(.top, Espace.s)
            }

            switch modele.etat {
            case .chargement where modele.accueil == nil, .initial:
                Squelette(hauteur: 210, rayon: 26)
                    .padding(.horizontal, Espace.bord)
                    .padding(.top, Espace.l)
            case .erreur(let erreur) where modele.accueil == nil:
                VueErreur(erreur: erreur) { Task { await modele.charger() } }
                    .padding(.top, Espace.l)
            default:
                sections
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
        if let accueil = modele.accueil {
            FriseSemaineView(semaine: accueil.chantiers7Jours) { ouvrirPlanning() }
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .apparitionEnCascade(index: 3, visible: visible)
        }

        TuileDecisions(modele: modele, visible: $carteVisible, zoom: zoom) { fiche = $0 }
            .padding(.top, 14)
            .apparitionEnCascade(index: 4, visible: visible)

        if !app.session.estOuvrier {
            ActionsTerrain()
                .padding(.horizontal, Espace.bord)
                .padding(.top, 12)
                .apparitionEnCascade(index: 5, visible: visible)
        }

        if let accueil = modele.accueil {
            HStack(alignment: .top, spacing: 10) {
                TuileFinances(accueil: accueil) { app.onglet = .finances }
                TuileChantiers(semaine: accueil.chantiers7Jours, enCours: chantiersEnCours) { ouvrirPlanning() }
            }
            .padding(.horizontal, Espace.bord)
            .padding(.top, 12)
            .apparitionEnCascade(index: 6, visible: visible)
        }

        CarteBriefing()
            .padding(.horizontal, Espace.bord)
            .padding(.top, 10)
            .apparitionEnCascade(index: 7, visible: visible)

        if let suiviActions = app.suiviActions {
            SectionFaitRecemment(modele: suiviActions)
                .padding(.horizontal, Espace.bord)
                .padding(.top, Espace.l)
                .transitionDefilement()
        }
    }

    /// Chantiers acceptés → réalisés, les plus avancés d'abord.
    private var chantiersEnCours: [Dossier] {
        (app.chantiers?.tous ?? []).filter { (2...4).contains($0.etapeIndex) }.sorted { $0.etapeIndex > $1.etapeIndex }
    }

    private func ouvrirPlanning() {
        app.vueChantiers = .planning
        app.onglet = .chantiers
    }

    /// Date en Cinzel, puis « Bonjour, » et le prénom en italique crème (« Bonjour. » sans prénom).
    private var salutation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((modele.accueil?.date ?? DateEndry.longue(Date())).capitalizedPremiere)
                .etiquetteMaison(10.5)
            let lignes = Salutation.lignes(salut: modele.accueil?.salut, prenom: prenom)
            Text("\(Text(lignes.debut))\(Text(lignes.fin.isEmpty ? "" : " "))\(Text(lignes.fin.isEmpty ? "" : lignes.fin + ".").font(Police.serif(42, relativeTo: .largeTitle, italique: true)).foregroundStyle(Color.bronze))")
                .font(Police.serif(42, relativeTo: .largeTitle))
                .tracking(-0.5)
                .foregroundStyle(Color.encre)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Prénom saisi dans Réglages ; en démo, un prénom fictif.
    private var prenom: String {
        let saisi = prenomPatron.trimmingCharacters(in: .whitespacesAndNewlines)
        if saisi.isEmpty, app.session.estDemo { return Salutation.prenomDemo }
        return saisi
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

/// « Écrire » : la conversation écrite ou dictée avec l'assistant du bureau, comme une session ouverte.
struct BoutonEcrireBureau: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Espace.xs) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 15, weight: .semibold))
                Text("Écrire")
                    .styleTexte(15, relativeTo: .subheadline, graisse: .semibold)
            }
            .foregroundStyle(Color.orClair)
            .padding(.horizontal, Espace.m)
            .frame(minHeight: 44)
            .background(Color.white.opacity(0.1), in: Capsule())
            .overlay(Capsule().stroke(Color.or.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Ouvre la conversation avec l’assistant du bureau : écrivez ou dictez"))
        .accessibilityIdentifier("ecrire-bureau")
    }
}

/// L'argent de la semaine : à encaisser en grand, à payer et offres en attente ; ouvre les Finances.
struct ResumeArgent: View {
    var accueil: Accueil
    var ouvrir: () -> Void
    @AppStorage(ModeDevantClient.cle) private var devantClient = false

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
                    if !devantClient {
                        chiffre("À payer · 7 jours", accueil.payer.totalSemaine)
                        Rectangle().fill(Color.filet).frame(width: Espace.filet, height: 34)
                    }
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

/// Chantiers de la semaine : cartes avec une photo d’ambiance ; ouvre le Planning.
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

/// Salutation : « Bonjour » / « Bonsoir » du PC, et le prénom gardé sur l'iPhone (jamais inventé).
enum Salutation {
    static let clePrenom = "prenom-patron"
    /// Prénom fictif du mode démo.
    static let prenomDemo = "Luc"

    static func lignes(salut: String?, prenom: String) -> (debut: String, fin: String) {
        // Seul le premier mot du PC compte (« Bonjour », « Bonsoir ») : aucun nom n'est repris du serveur.
        let mot = (salut ?? "Bonjour").split(separator: " ").first.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ",.")) }
        let bonjour = (mot?.isEmpty ?? true) ? "Bonjour" : mot!
        return prenom.isEmpty ? (bonjour + ".", "") : (bonjour + ",", prenom)
    }
}

/// Résumé du jour en une phrase, calculé à partir de l'accueil.
enum ResumeDuJour {
    static func phrase(accueil: Accueil, decisions: Int, devantClient: Bool = false) -> String {
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
        if accueil.payer.totalSemaine > 0, !devantClient {
            morceaux.append("\(FormatSuisse.chfArrondi(accueil.payer.totalSemaine)) à payer sous 7 jours")
        }
        guard morceaux.count > 1 else { return morceaux[0] + "." }
        let fin = morceaux.removeLast()
        return morceaux.joined(separator: ", ") + " et " + fin + "."
    }
}

/// Bandeau « assistant en pause » : on lit tout, les actions attendent la reprise.
struct BandeauPause: View {
    /// `nil` si la reprise n'est pas pilotable depuis l'app (serveur v1.0).
    var reprendre: (() async -> Void)?
    @State private var enCours = false

    var body: some View {
        HStack(alignment: .center, spacing: Espace.s) {
            Label("Assistant en pause : vos décisions s’exécutent, il ne prépare rien de nouveau.", systemImage: "pause.circle")
                .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                .foregroundStyle(Color.ambre)
                .fixedSize(horizontal: false, vertical: true)
            if let reprendre {
                Spacer(minLength: 0)
                Button {
                    enCours = true
                    Task {
                        await reprendre()
                        enCours = false
                    }
                } label: {
                    if enCours { ProgressView().controlSize(.small) } else { Text("Reprendre") }
                }
                .styleTexte(14, relativeTo: .subheadline, graisse: .semibold)
                .foregroundStyle(Color.fond)
                .padding(.horizontal, Espace.m)
                .frame(minHeight: 36)
                .background(Color.ambre, in: Capsule())
                .disabled(enCours)
                .accessibilityIdentifier("reprendre-assistant")
            }
        }
        .padding(Espace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ambre.opacity(0.12), in: RoundedRectangle(cornerRadius: Espace.rayonPetit, style: .continuous))
        .accessibilityElement(children: .contain)
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
