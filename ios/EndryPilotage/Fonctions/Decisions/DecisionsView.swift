import EndryKit
import SwiftUI

/// Accueil — poste de pilotage : en-tête, salutation et résumé du jour, puis le pouls de l'entreprise
/// (trésorerie et quatre instruments), la pile « À décider » à glisser, le bureau en direct, la semaine,
/// les outils de terrain, le briefing et ce qui a été fait. On lit l'entreprise d'un coup d'œil, de haut en bas
/// par ordre d'urgence ; chaque chiffre mène à son espace.
struct DecisionsView: View {
    @AppStorage(Salutation.clePrenom) private var prenomPatron = ""
    @AppStorage(ModeDevantClient.cle) private var devantClient = false
    @Environment(ModeleApp.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations
    @Environment(\.animationsEnPause) private var enPause
    var modele: ModeleDecisions

    @State private var visible = false
    @State private var carteVisible: String?
    @State private var fiche: Carte?
    @Namespace private var zoom

    private static let ancreDecisions = "section-decisions"

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                FondMaison()
                ScrollViewReader { defilement in
                    ScrollView {
                        contenu {
                            withAnimation(.endry(reduire: reduireAnimations)) {
                                defilement.scrollTo(Self.ancreDecisions, anchor: .top)
                            }
                        }
                        .largeurLisible(Adaptatif.ecran)
                        .padding(.bottom, 130)
                        .verrouillerLargeur()
                    }
                    .scrollIndicators(.hidden)
                    .tirerPourActualiser { await modele.charger() }
                }
            }
            // Fiche d'une décision ouverte par-dessus : l'accueil cesse d'animer.
            .environment(\.animationsEnPause, enPause || fiche != nil)
            .toolbar(.hidden, for: .navigationBar)
        }
        .toast(Binding(get: { modele.toast }, set: { modele.toast = $0 }))
        .sensoryFeedback(.success, trigger: modele.nombreDecisions) { ancien, nouveau in nouveau < ancien }
        .sheet(item: $fiche) { carte in
            // La tuile grandit jusqu'à devenir la fiche.
            FicheDecision(carte: carte, modele: modele)
                .apercuDocuments()
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
        .task(id: app.agents == nil) {
            if let agents = app.agents, !agents.charge { await agents.charger() }
        }
    }

    /// Reprise depuis le bandeau de pause (serveur v1.1 et plus).
    private var repriseAssistant: (() async -> Void)? {
        guard let pilotage = app.pilotage, pilotage.disponible else { return nil }
        return { _ = await pilotage.reprendre() }
    }

    @ViewBuilder
    private func contenu(ouvrirDecisions: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EnTeteMaison(initiale: prenom.first.map { String($0).uppercased() })
                .padding(.horizontal, Espace.bord)
                .padding(.top, 4)
                .apparitionEnCascade(index: 0, visible: visible)

            salutation
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .apparitionEnCascade(index: 1, visible: visible)

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
                Squelette(hauteur: 190, rayon: 24)
                    .padding(.horizontal, Espace.bord)
                    .padding(.top, Espace.l)
                HStack(spacing: 10) {
                    Squelette(hauteur: 128, rayon: 22)
                    Squelette(hauteur: 128, rayon: 22)
                }
                .padding(.horizontal, Espace.bord)
                .padding(.top, 10)
            case .erreur(let erreur) where modele.accueil == nil:
                VueErreur(erreur: erreur) { Task { await modele.charger() } }
                    .padding(.top, Espace.l)
            default:
                sections(ouvrirDecisions: ouvrirDecisions)
            }
        }
    }

    @ViewBuilder
    private func sections(ouvrirDecisions: @escaping () -> Void) -> some View {
        if let accueil = modele.accueil {
            PoulsEntreprise(accueil: accueil, cartes: modele.cartes, chantiersEnCours: chantiersEnCours,
                            majLe: modele.majLe, ouvrirDecisions: ouvrirDecisions)
                .padding(.horizontal, Espace.bord)
                .padding(.top, 26)
                .apparitionEnCascade(index: 2, visible: visible)
        }

        TuileDecisions(modele: modele, visible: $carteVisible, zoom: zoom) { fiche = $0 }
            .padding(.top, 26)
            .id(Self.ancreDecisions)
            .apparitionEnCascade(index: 3, visible: visible)

        // v1.12 : les derniers e-mails reçus, visibles dès l'accueil.
        CarteCourrier()
            .padding(.horizontal, Espace.bord)
            .padding(.top, 26)
            .apparitionEnCascade(index: 4, visible: visible)

        if let agents = app.agents {
            BureauEnDirect(modele: agents) { app.onglet = .entreprise }
                .padding(.horizontal, Espace.bord)
                .padding(.top, 26)
                .apparitionEnCascade(index: 4, visible: visible)
        }

        if !app.session.estOuvrier && !app.session.estDirecteur {
            VStack(alignment: .leading, spacing: 10) {
                TitreSection(titre: "Développement")
                CarteProspection()
            }
            .padding(.horizontal, Espace.bord)
            .padding(.top, 26)
        }

        if let accueil = modele.accueil {
            VStack(alignment: .leading, spacing: 10) {
                TitreSection(titre: "Cette semaine · sem. \(FriseSemaineView.numeroSemaine())", lien: "Planning", action: ouvrirPlanning)
                FriseSemaineView(semaine: accueil.chantiers7Jours) { ouvrirPlanning() }
                    .padding(14)
                    .tuileMaison(rayon: 22)
            }
            .padding(.horizontal, Espace.bord)
            .padding(.top, 26)
            .apparitionEnCascade(index: 5, visible: visible)
        }

        if !app.session.estOuvrier {
            VStack(alignment: .leading, spacing: 10) {
                TitreSection(titre: "Terrain")
                ActionsTerrain()
            }
            .padding(.horizontal, Espace.bord)
            .padding(.top, 26)
            .apparitionEnCascade(index: 6, visible: visible)
        }

        CarteBriefing()
            .padding(.horizontal, Espace.bord)
            .padding(.top, 12)
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

    /// Date et semaine en petites capitales, « Bonjour, Luc. » (prénom en crème), puis le résumé du jour.
    private var salutation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((modele.accueil?.date ?? DateEndry.longue(Date())).capitalizedPremiere)
                .etiquetteMaison(11)
            let lignes = Salutation.lignes(salut: modele.accueil?.salut, prenom: prenom)
            Text("\(Text(lignes.debut))\(Text(lignes.fin.isEmpty ? "" : " "))\(Text(lignes.fin.isEmpty ? "" : lignes.fin + ".").foregroundStyle(Color.signal))")
                .font(Police.serif(36, relativeTo: .largeTitle))
                .tracking(-0.7)
                .foregroundStyle(Color.encre)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            if let accueil = modele.accueil {
                Text(ResumeDuJour.phrase(accueil: accueil, decisions: modele.nombreDecisions, devantClient: devantClient))
                    .font(.system(size: UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 15)))
                    .foregroundStyle(Color.encreDouce)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .accessibilityIdentifier("resume-du-jour")
            }
        }
    }

    /// Prénom saisi dans Réglages ; en démo, un prénom fictif.
    private var prenom: String {
        let saisi = prenomPatron.trimmingCharacters(in: .whitespacesAndNewlines)
        if saisi.isEmpty, app.session.estDemo { return Salutation.prenomDemo }
        return saisi
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
