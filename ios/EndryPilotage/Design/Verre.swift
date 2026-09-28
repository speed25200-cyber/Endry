import EndryKit
import SwiftUI

extension View {
    /// Verre : Liquid Glass sur iOS 26, matériau `.ultraThinMaterial` avant.
    @ViewBuilder
    func verre<S: Shape>(_ forme: S, interactif: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(interactif ? Glass.regular.interactive() : Glass.regular, in: forme)
        } else {
            background(.ultraThinMaterial, in: forme)
                .overlay(forme.stroke(Color.bordureOr, lineWidth: Espace.filet))
        }
        #else
        background(.ultraThinMaterial, in: forme)
            .overlay(forme.stroke(Color.bordureOr, lineWidth: Espace.filet))
        #endif
    }
}

// MARK: - Onglets

enum Onglet: String, CaseIterable, Identifiable, Hashable {
    case aujourdhui, chantiers, saisie, finances, entreprise

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .aujourdhui: "Aujourd’hui"
        case .chantiers: "Chantiers"
        case .saisie: "Dicter"
        case .finances: "Finances"
        case .entreprise: "Entreprise"
        }
    }

    var icone: String {
        switch self {
        case .aujourdhui: "house"
        case .chantiers: "calendar"
        case .saisie: "mic"
        case .finances: "chart.line.uptrend.xyaxis"
        case .entreprise: "person"
        }
    }

    var iconeActive: String {
        switch self {
        case .aujourdhui: "house.fill"
        case .chantiers: "calendar"
        case .saisie: "mic.fill"
        case .finances: "chart.line.uptrend.xyaxis"
        case .entreprise: "person.fill"
        }
    }
}

/// Dock de la maison : pilule brune, icônes crème, micro crème au centre (toucher long : assistant vocal).
struct BarreOnglets: View {
    @Binding var selection: Onglet
    var badgeDecisions: Int
    /// Toucher long du micro : assistant vocal plein écran.
    var ouvrirAssistant: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        HStack(spacing: 0) {
            bouton(.aujourdhui)
            bouton(.chantiers)
            BoutonMicroCentral(actif: selection == .saisie, appuiLong: ouvrirAssistant) {
                withAnimation(.endry) { selection = .saisie }
            }
            .frame(maxWidth: .infinity)
            bouton(.finances)
            bouton(.entreprise)
        }
        .padding(.horizontal, 6)
        .frame(height: 66)
        .background {
            Capsule()
                .fill(Color.espresso.opacity(0.94).shadow(.drop(color: .black.opacity(0.35), radius: 22, y: 10)))
                .overlay(Capsule().stroke(Color(hex: 0x443A2C), lineWidth: 1))
        }
        .padding(.horizontal, Espace.m)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func bouton(_ onglet: Onglet) -> some View {
        let actif = selection == onglet
        return Button {
            withAnimation(reduireAnimations ? .fonduDoux : .endryVif) {
                selection = onglet
            }
        } label: {
            Image(systemName: actif ? onglet.iconeActive : onglet.icone)
                .font(.system(size: 20, weight: actif ? .semibold : .regular))
                .symbolEffect(.bounce.down, value: actif)
                .foregroundStyle(actif ? Color.or : Color(hex: 0x8F8575))
                .overlay(alignment: .topTrailing) {
                    if onglet == .aujourdhui, badgeDecisions > 0 {
                        Text("\(badgeDecisions)")
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.espresso)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.or, in: Capsule())
                            .offset(x: 11, y: -8)
                            .contentTransition(.numericText(value: Double(badgeDecisions)))
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(Text(onglet == .aujourdhui && badgeDecisions > 0 ? "\(onglet.titre), \(badgeDecisions) décisions en attente" : onglet.titre))
        .accessibilityAddTraits(actif ? .isSelected : [])
        .accessibilityIdentifier("onglet-\(onglet.rawValue)")
    }
}

/// Bouton micro doré, qui rayonne quand il est actif.
/// Toucher court : dictée (saisie terrain). Toucher long : assistant vocal plein écran.
struct BoutonMicroCentral: View {
    var actif: Bool
    var appuiLong: () -> Void = {}
    var action: () -> Void
    @State private var presse = false
    @State private var appuiLongDeclenche = false
    @State private var assistantOuvert = 0
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        Button {
            // Après un toucher long (assistant ouvert), le relâchement n'ouvre pas la dictée.
            if appuiLongDeclenche {
                appuiLongDeclenche = false
                return
            }
            action()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.or.opacity(actif || presse ? 0.55 : 0.25), lineWidth: 1)
                    .frame(width: 62, height: 62)
                Circle()
                    .fill(Color.or)
                    .frame(width: 52, height: 52)
                Image(systemName: presse ? "waveform" : "mic.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.espresso)
                    .contentTransition(.symbolEffect(.replace))
            }
            .scaleEffect(presse ? 1.08 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    appuiLongDeclenche = true
                    assistantOuvert += 1
                    appuiLong()
                }
        )
        .onLongPressGesture(minimumDuration: 0.45, perform: {}, onPressingChanged: { enCours in
            withAnimation(.endryVif) { presse = enCours }
        })
        .sensoryFeedback(.impact(weight: .medium), trigger: assistantOuvert)
        .accessibilityLabel(Text("Dicter une saisie terrain"))
        .accessibilityHint(Text("Toucher long : assistant vocal."))
        .accessibilityAction(named: Text("Parler à l’assistant")) { appuiLong() }
        .accessibilityIdentifier("onglet-saisie")
    }
}

// MARK: - Toasts

struct ToastView: View {
    var toast: Toast

    var body: some View {
        HStack(spacing: Espace.s) {
            Image(systemName: icone)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(couleur)
                .symbolEffect(.bounce, value: toast.id)
            Text(toast.message)
                .styleTexte(15, relativeTo: .subheadline, graisse: .medium)
                .foregroundStyle(Color.encre)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Espace.l)
        .padding(.vertical, 14)
        .verre(Capsule())
        .shadow(color: Color.ombre, radius: 18, y: 8)
        .padding(.horizontal, Espace.l)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    private var icone: String {
        switch toast.style {
        case .succes: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .erreur: "exclamationmark.circle.fill"
        }
    }

    private var couleur: Color {
        switch toast.style {
        case .succes: .vertControle
        case .info: .bronze
        case .erreur: .rouille
        }
    }
}

extension View {
    /// Affiche le toast au-dessus de la barre d'onglets et le retire après quelques secondes.
    func toast(_ toast: Binding<Toast?>, decalageBas: CGFloat = 96) -> some View {
        overlay(alignment: .bottom) {
            ZStack {
                if let valeur = toast.wrappedValue {
                    ToastView(toast: valeur)
                        .id(valeur.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.92)))
                        .task(id: valeur.id) {
                            try? await Task.sleep(for: .seconds(valeur.style == .erreur ? 4.5 : 2.8))
                            withAnimation(.endry) {
                                if toast.wrappedValue?.id == valeur.id { toast.wrappedValue = nil }
                            }
                        }
                        .onTapGesture { withAnimation(.endry) { toast.wrappedValue = nil } }
                }
            }
            .padding(.bottom, decalageBas)
            .animation(.endry, value: toast.wrappedValue?.id)
        }
    }
}
