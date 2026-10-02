import AppIntents
import EndryKit
import SwiftUI
import WidgetKit

/// Widgets d'Endry : écran d'accueil, écran verrouillé, Centre de contrôle.
/// Le widget lit le PC avec le jeton de l'iPhone (trousseau partagé) ; montants seulement si le patron l'a choisi.
@main
struct EndryWidgets: WidgetBundle {
    var body: some Widget {
        WidgetAujourdhui()
        LiveActivitePointageWidget()
        ControleRegie()
        ControleBonLivraison()
        ControleAssistant()
    }
}

// MARK: - Données

struct ConfigurationAujourdhui: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Endry aujourd’hui"
    static let description: IntentDescription? = IntentDescription("Décisions, chantiers du jour et encaissements.")

    @Parameter(title: "Afficher les montants", default: false)
    var montants: Bool
}

struct EntreeEndry: TimelineEntry {
    enum Etat {
        case donnees(ResumeWidget)
        case deconnecte
        case injoignable
    }

    let date: Date
    let etat: Etat
    let montants: Bool
}

struct ResumeWidget {
    var decisions: Int
    var envois: Int
    var aEncaisser: Double
    var retard30: Double
    var chantiersDuJour: [String]
    var pause: Bool

    static let exemple = ResumeWidget(decisions: 3, envois: 1, aEncaisser: 42_300, retard30: 8_450,
                                      chantiersDuJour: ["Gérance Morel SA · Epalinges", "PPE Les Cèdres · Bussy"], pause: false)

    init(decisions: Int, envois: Int, aEncaisser: Double, retard30: Double, chantiersDuJour: [String], pause: Bool) {
        self.decisions = decisions
        self.envois = envois
        self.aEncaisser = aEncaisser
        self.retard30 = retard30
        self.chantiersDuJour = chantiersDuJour
        self.pause = pause
    }

    init(_ a: Accueil, le date: Date = Date()) {
        decisions = a.decisions.count
        envois = a.decisions.filter(\.exigeGlisser).count
        aEncaisser = a.encaisser.total
        retard30 = a.encaisser.anciennete.plus30
        chantiersDuJour = a.chantiers7Jours.filter { s in
            guard let d = s.dateDebut else { return false }
            return DateEndry.jours(de: d, a: date) >= 0 && DateEndry.jours(de: date, a: s.dateFin ?? d) >= 0
        }.map { [$0.client ?? $0.titre, $0.lieu].compactMap { $0 }.joined(separator: " · ") }
        pause = a.pause
    }
}

struct FournisseurAujourdhui: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> EntreeEndry {
        EntreeEndry(date: Date(), etat: .donnees(.exemple), montants: false)
    }

    func snapshot(for configuration: ConfigurationAujourdhui, in context: Context) async -> EntreeEndry {
        if context.isPreview { return EntreeEndry(date: Date(), etat: .donnees(.exemple), montants: configuration.montants) }
        return await entree(configuration)
    }

    func timeline(for configuration: ConfigurationAujourdhui, in context: Context) async -> Timeline<EntreeEndry> {
        let e = await entree(configuration)
        return Timeline(entries: [e], policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func entree(_ configuration: ConfigurationAujourdhui) async -> EntreeEndry {
        guard let i = CoffreTrousseau().lire(), !i.estExpire else {
            return EntreeEndry(date: Date(), etat: .deconnecte, montants: configuration.montants)
        }
        guard !i.estOuvrier, let accueil = try? await ClientAPI(identifiants: i).accueil() else {
            return EntreeEndry(date: Date(), etat: .injoignable, montants: configuration.montants)
        }
        return EntreeEndry(date: Date(), etat: .donnees(ResumeWidget(accueil)), montants: configuration.montants)
    }
}

// MARK: - Widget

struct WidgetAujourdhui: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.endrysa.endry.aujourdhui", intent: ConfigurationAujourdhui.self, provider: FournisseurAujourdhui()) { entree in
            VueAujourdhui(entree: entree)
                .containerBackground(for: .widget) { FondWidget() }
                .widgetURL(URL(string: "endrypilotage://decisions"))
        }
        .configurationDisplayName("Endry aujourd’hui")
        .description("Décisions à prendre, chantiers du jour, encaissements.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

private enum Teinte {
    static let espresso = Color(red: 0.13, green: 0.10, blue: 0.075)
    static let or = Color(red: 0.976, green: 0.859, blue: 0.639)
    static let orPale = Color(red: 1.0, green: 0.94, blue: 0.83)
}

struct FondWidget: View {
    var body: some View {
        LinearGradient(colors: [Teinte.espresso, Color(red: 0.09, green: 0.07, blue: 0.05)], startPoint: .top, endPoint: .bottom)
    }
}

struct VueAujourdhui: View {
    var entree: EntreeEndry
    @Environment(\.widgetFamily) private var famille

    var body: some View {
        switch entree.etat {
        case .deconnecte:
            message("Connectez Endry", "Ouvrez l’app et collez le lien du bureau.")
        case .injoignable:
            message("Bureau injoignable", "Nouvel essai dans 30 min.")
        case .donnees(let r):
            switch famille {
            case .accessoryInline:
                Text("Endry · \(r.decisions) décision\(r.decisions > 1 ? "s" : "")")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Text("\(r.decisions)").font(.system(.title2, design: .serif, weight: .semibold))
                        Text("à décider").font(.system(size: 8, weight: .medium))
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Endry").font(.headline)
                    Text("\(r.decisions) à décider\(r.envois > 0 ? " · \(r.envois) envoi" : "")")
                    Text(r.chantiersDuJour.first ?? "Aucun chantier aujourd’hui").lineLimit(1)
                }
                .font(.caption)
            case .systemMedium:
                HStack(alignment: .top, spacing: 16) {
                    blocDecisions(r)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AUJOURD’HUI").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(Teinte.or.opacity(0.8))
                        if r.chantiersDuJour.isEmpty {
                            Text("Aucun chantier").font(.subheadline).foregroundStyle(Teinte.orPale.opacity(0.7))
                        }
                        ForEach(r.chantiersDuJour.prefix(3), id: \.self) { c in
                            Text(c).font(.subheadline.weight(.medium)).foregroundStyle(Teinte.orPale).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if entree.montants {
                            Text("À encaisser \(FormatSuisse.chfArrondi(r.aEncaisser))").font(.caption).foregroundStyle(Teinte.or)
                        }
                    }
                }
            default:
                blocDecisions(r)
            }
        }
    }

    private func blocDecisions(_ r: ResumeWidget) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("À DÉCIDER").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(Teinte.or.opacity(0.8))
            Text("\(r.decisions)")
                .font(.system(size: 46, weight: .semibold, design: .serif))
                .foregroundStyle(Teinte.or)
                .contentTransition(.numericText(value: Double(r.decisions)))
            if r.envois > 0 {
                Text("\(r.envois) envoi\(r.envois > 1 ? "s" : "") à un tiers").font(.caption2).foregroundStyle(Teinte.orPale.opacity(0.8))
            }
            Spacer(minLength: 0)
            if r.pause {
                Label("Assistant en pause", systemImage: "pause.circle").font(.caption2).foregroundStyle(Teinte.orPale.opacity(0.8))
            } else if entree.montants, famille == .systemSmall {
                Text(FormatSuisse.chfArrondi(r.aEncaisser)).font(.caption.weight(.semibold)).foregroundStyle(Teinte.orPale)
            } else {
                Text("\(r.chantiersDuJour.count) chantier\(r.chantiersDuJour.count > 1 ? "s" : "") aujourd’hui")
                    .font(.caption2).foregroundStyle(Teinte.orPale.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(_ titre: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.headline).foregroundStyle(Teinte.or)
            Text(detail).font(.caption).foregroundStyle(Teinte.orPale.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Centre de contrôle, écran verrouillé, bouton Action

struct ControleRegie: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.endrysa.endry.controle.regie") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "endrypilotage://outil/regie")!)) {
                Label("Bon de régie", systemImage: "signature")
            }
        }
        .displayName("Bon de régie")
        .description("Ouvre un bon de régie à faire signer.")
    }
}

struct ControleBonLivraison: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.endrysa.endry.controle.bon") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "endrypilotage://outil/bonLivraison")!)) {
                Label("Bon de livraison", systemImage: "shippingbox")
            }
        }
        .displayName("Bon de livraison")
        .description("Photographie un bon fournisseur.")
    }
}

struct ControleAssistant: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.endrysa.endry.controle.assistant") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "endrypilotage://assistant")!)) {
                Label("Parler à Endry", systemImage: "waveform")
            }
        }
        .displayName("Parler à Endry")
        .description("Ouvre l’assistant vocal.")
    }
}

// MARK: - Live Activity du pointage (mode équipe)

struct LiveActivitePointageWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ActivitePointage.self) { contexte in
            HStack(spacing: 14) {
                Image(systemName: "timer")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Teinte.or)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contexte.state.chantier).font(.headline).foregroundStyle(Teinte.orPale).lineLimit(1)
                    Text("\(contexte.attributes.ouvrier) · aujourd’hui \(FormatSuisse.heures(contexte.state.totalJour))")
                        .font(.caption).foregroundStyle(Teinte.orPale.opacity(0.7))
                }
                Spacer()
                Text(contexte.state.debut, style: .timer)
                    .font(.system(.title, design: .serif, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Teinte.or)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            .padding(16)
            .activityBackgroundTint(Teinte.espresso)
            .activitySystemActionForegroundColor(Teinte.or)
        } dynamicIsland: { contexte in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Pointage", systemImage: "timer").font(.caption).foregroundStyle(Teinte.or)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(contexte.state.debut, style: .timer).monospacedDigit().foregroundStyle(Teinte.or)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(contexte.state.chantier).font(.subheadline).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Teinte.or)
            } compactTrailing: {
                Text(contexte.state.debut, style: .timer).monospacedDigit().frame(maxWidth: 52).foregroundStyle(Teinte.or)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Teinte.or)
            }
            .widgetURL(URL(string: "endrypilotage://decisions"))
        }
    }
}
