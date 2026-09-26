import EndryKit
import SwiftUI
import WidgetKit

/// Entrée du widget : nombre de décisions et montant à encaisser.
struct EntreeEndry: TimelineEntry {
    let date: Date
    let resume: ResumeWidget?
    let connecte: Bool
}

/// Lit le résumé partagé par l'app, puis tente une actualisation avec le jeton du trousseau partagé.
nonisolated struct FournisseurEndry: TimelineProvider {
    func placeholder(in context: Context) -> EntreeEndry {
        EntreeEndry(date: .now, resume: .exemple, connecte: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (EntreeEndry) -> Void) {
        if context.isPreview {
            completion(EntreeEndry(date: .now, resume: .exemple, connecte: true))
        } else {
            completion(EntreeEndry(date: .now, resume: ResumeWidget.lire(groupe: Configuration.groupeApps), connecte: true))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntreeEndry>) -> Void) {
        nonisolated(unsafe) let terminer = completion
        Task {
            let entree = await Self.charger()
            // Actualisation raisonnable : toutes les 30 minutes (WidgetKit peut espacer davantage).
            let prochaine = Date().addingTimeInterval(30 * 60)
            terminer(Timeline(entries: [entree], policy: .after(prochaine)))
        }
    }

    static func charger() async -> EntreeEndry {
        let enCache = ResumeWidget.lire(groupe: Configuration.groupeApps)
        let coffre = CoffreTrousseau(groupe: Configuration.groupeTrousseau)
        guard let identifiants = coffre.lire(), !identifiants.estExpire else {
            return EntreeEndry(date: .now, resume: enCache, connecte: enCache != nil)
        }
        do {
            let accueil = try await ClientAPI(identifiants: identifiants).accueil()
            let resume = ResumeWidget(accueil: accueil)
            resume.enregistrer(groupe: Configuration.groupeApps)
            return EntreeEndry(date: .now, resume: resume, connecte: true)
        } catch {
            return EntreeEndry(date: .now, resume: enCache, connecte: true)
        }
    }
}

struct VueWidgetEndry: View {
    var entree: EntreeEndry
    @Environment(\.widgetFamily) private var famille
    @Environment(\.widgetRenderingMode) private var rendu

    var body: some View {
        Group {
            switch famille {
            case .accessoryCircular: circulaire
            case .accessoryRectangular: rectangulaire
            case .accessoryInline: enLigne
            case .systemMedium: moyen
            default: petit
            }
        }
        .widgetURL(URL(string: "endrypilotage://decisions"))
    }

    private var decisions: Int { entree.resume?.decisions ?? 0 }
    private var montant: Double { entree.resume?.aEncaisser ?? 0 }
    private var enCouleur: Bool { rendu == .fullColor }

    // MARK: - Écran d'accueil

    private var petit: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("E")
                    .font(Police.titre(15, relativeTo: .caption))
                    .foregroundStyle(enCouleur ? AnyShapeStyle(.degradeOr) : AnyShapeStyle(.primary))
                Spacer()
                if let maj = entree.resume?.majLe {
                    Text(maj, style: .time)
                        .font(Police.texte(10, relativeTo: .caption2))
                        .foregroundStyle(enCouleur ? Color.orClair.opacity(0.5) : .secondary)
                }
            }
            Spacer(minLength: 4)
            Text("\(decisions)")
                .font(Police.titre(46, relativeTo: .largeTitle))
                .tracking(-2)
                .monospacedDigit()
                .foregroundStyle(enCouleur ? Color.orClair : .primary)
                .contentTransition(.numericText(value: Double(decisions)))
                .widgetAccentable()
            Text(decisions == 1 ? "décision" : "décisions")
                .font(Police.texte(13, relativeTo: .footnote, graisse: .medium))
                .foregroundStyle(enCouleur ? Color.or.opacity(0.85) : .secondary)
            Spacer(minLength: 6)
            MontantView(montant: montant, taille: 15, couleur: enCouleur ? .orClair : .primary,
                        couleurDevise: enCouleur ? Color.or.opacity(0.6) : .secondary, afficherCentimes: false, style: .footnote)
            Text("à encaisser")
                .font(Police.texte(10, relativeTo: .caption2))
                .foregroundStyle(enCouleur ? Color.orClair.opacity(0.55) : .secondary)
        }
        .containerBackground(for: .widget) { FondWidget() }
        .accessibilityElement(children: .combine)
    }

    private var moyen: some View {
        HStack(alignment: .top, spacing: Espace.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text("À décider")
                    .font(Police.texte(11, relativeTo: .caption2, graisse: .semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(enCouleur ? Color.or.opacity(0.85) : .secondary)
                Text("\(decisions)")
                    .font(Police.titre(52, relativeTo: .largeTitle))
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundStyle(enCouleur ? Color.orClair : .primary)
                    .widgetAccentable()
                Spacer(minLength: 0)
                if let prochaine = entree.resume?.prochaineDecision {
                    Text(prochaine)
                        .font(Police.texte(12, relativeTo: .caption, graisse: .medium))
                        .foregroundStyle(enCouleur ? Color.orClair.opacity(0.75) : .secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text("À encaisser")
                    .font(Police.texte(11, relativeTo: .caption2, graisse: .semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(enCouleur ? Color.or.opacity(0.85) : .secondary)
                MontantView(montant: montant, taille: 22, couleur: enCouleur ? .orClair : .primary,
                            couleurDevise: enCouleur ? Color.or.opacity(0.6) : .secondary, afficherCentimes: false, style: .title3)
                if let retard = entree.resume?.enRetardPlus30, retard > 0 {
                    Text("dont \(FormatSuisse.chfArrondi(retard)) > 30 j")
                        .font(Police.texte(11, relativeTo: .caption2, graisse: .medium))
                        .foregroundStyle(enCouleur ? Color(hex: 0xE58A6F) : .secondary)
                }
                Spacer(minLength: 0)
                if !entree.connecte {
                    Text("Ouvrez l’app pour vous connecter")
                        .font(Police.texte(10, relativeTo: .caption2))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .containerBackground(for: .widget) { FondWidget() }
    }

    // MARK: - Écran verrouillé

    private var circulaire: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Text("\(decisions)")
                    .font(Police.titre(24, relativeTo: .title))
                    .monospacedDigit()
                    .widgetAccentable()
                Text("décis.")
                    .font(Police.texte(9, relativeTo: .caption2, graisse: .medium))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .accessibilityLabel(Text("\(decisions) décisions en attente"))
    }

    private var rectangulaire: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Endry · \(decisions) décision\(decisions > 1 ? "s" : "")")
                .font(Police.titre(15, relativeTo: .headline))
                .widgetAccentable()
            Text("\(FormatSuisse.chfArrondi(montant)) à encaisser")
                .font(Police.texte(13, relativeTo: .footnote))
                .monospacedDigit()
            if let prochaine = entree.resume?.prochaineDecision {
                Text(prochaine).font(Police.texte(11, relativeTo: .caption2)).lineLimit(1).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var enLigne: some View {
        Text("\(decisions) décisions · \(FormatSuisse.chfArrondi(montant))")
            .containerBackground(for: .widget) { Color.clear }
    }
}

private struct FondWidget: View {
    var body: some View {
        RadialGradient(
            colors: [Color(hex: 0x4A3624), Color.espresso, Color.espressoProfond],
            center: UnitPoint(x: 0.2, y: 0),
            startRadius: 4,
            endRadius: 260
        )
    }
}

struct EndryWidget: Widget {
    let kind = "EndryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FournisseurEndry()) { entree in
            VueWidgetEndry(entree: entree)
        }
        .configurationDisplayName("Endry Pilotage")
        .description("Décisions en attente et montant à encaisser.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct PaquetWidgetsEndry: WidgetBundle {
    var body: some Widget {
        EndryWidget()
    }
}

#Preview("Petit", as: .systemSmall) {
    EndryWidget()
} timeline: {
    EntreeEndry(date: .now, resume: .exemple, connecte: true)
}

#Preview("Moyen", as: .systemMedium) {
    EndryWidget()
} timeline: {
    EntreeEndry(date: .now, resume: .exemple, connecte: true)
}

#Preview("Verrouillé", as: .accessoryRectangular) {
    EndryWidget()
} timeline: {
    EntreeEndry(date: .now, resume: .exemple, connecte: true)
}
