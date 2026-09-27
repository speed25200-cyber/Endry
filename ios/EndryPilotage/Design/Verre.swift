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
        case .aujourdhui: "sun.horizon"
        case .chantiers: "hammer"
        case .saisie: "mic"
        case .finances: "chart.line.uptrend.xyaxis"
        case .entreprise: "building.2"
        }
    }

    var iconeActive: String {
        switch self {
        case .aujourdhui: "sun.horizon.fill"
        case .chantiers: "hammer.fill"
        case .saisie: "mic.fill"
        case .finances: "chart.line.uptrend.xyaxis"
        case .entreprise: "building.2.fill"
        }
    }
}

/// Barre d'onglets flottante en verre sombre ; onglet actif en or, micro doré surélevé au centre.
struct BarreOnglets: View {
    @Binding var selection: Onglet
    var badgeDecisions: Int
    /// Toucher long du micro : assistant vocal plein écran.
    var ouvrirAssistant: () -> Void = {}
    @Namespace private var espace
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
        .background(Color(clair: 0xFBF8F2, sombre: 0x070605, opaciteClair: 0.55, opaciteSombre: 0.55), in: Capsule())
        .verre(Capsule(), interactif: true)
        .overlay(Capsule().strokeBorder(Color.bordureOr, lineWidth: Espace.filet))
        .shadow(color: Color.ombre, radius: 26, y: 12)
        .padding(.horizontal, Espace.m)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func bouton(_ onglet: Onglet) -> some View {
        let actif = selection == onglet
        return Button {
            withAnimation(reduireAnimations ? .easeOut(duration: 0.15) : .endry) {
                selection = onglet
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: actif ? onglet.iconeActive : onglet.icone)
                    .font(.system(size: 18, weight: actif ? .semibold : .regular))
                    .symbolEffect(.bounce.down, value: actif)
                    .foregroundStyle(actif ? AnyShapeStyle(.degradeOr) : AnyShapeStyle(Color.encrePale))
                    .overlay(alignment: .topTrailing) {
                        if onglet == .aujourdhui, badgeDecisions > 0 {
                            Text("\(badgeDecisions)")
                                .font(Police.titre(10, relativeTo: .caption2))
                                .monospacedDigit()
                                .foregroundStyle(Color.espressoProfond)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Color.or, in: Capsule())
                                .offset(x: 11, y: -7)
                                .contentTransition(.numericText(value: Double(badgeDecisions)))
                                .accessibilityHidden(true)
                        }
                    }
                Text(onglet.titre)
                    .font(Police.texte(10, relativeTo: .caption2, graisse: actif ? .semibold : .medium))
                    .foregroundStyle(actif ? Color.bronze : Color.encrePale)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                // Point lumineux sous l'onglet actif.
                ZStack {
                    if actif {
                        Circle()
                            .fill(Color.or)
                            .frame(width: 4, height: 4)
                            .shadow(color: Color.or, radius: 4)
                            .matchedGeometryEffect(id: "point", in: espace)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(onglet == .aujourdhui && badgeDecisions > 0 ? "\(onglet.titre), \(badgeDecisions) décisions en attente" : onglet.titre))
        .accessibilityAddTraits(actif ? .isSelected : [])
        .accessibilityIdentifier("onglet-\(onglet.rawValue)")
    }
}

/// Bouton micro doré, qui respire au repos et rayonne quand il est actif.
/// Toucher court : dictée (saisie terrain). Toucher long : assistant vocal plein écran.
struct BoutonMicroCentral: View {
    var actif: Bool
    var appuiLong: () -> Void = {}
    var action: () -> Void
    @GestureState private var presse = false
    @State private var assistantOuvert = 0
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.or.opacity(actif || presse ? 0.35 : 0.18))
                .frame(width: 76, height: 76)
                .blur(radius: 14)
            Circle()
                .fill(.degradeOr)
                .frame(width: 60, height: 60)
                .overlay(Circle().strokeBorder(Color.orClair.opacity(0.7), lineWidth: Espace.filet).padding(1))
                .shadow(color: Color.or.opacity(0.45), radius: 16, y: 6)
            Image(systemName: presse ? "waveform" : "mic.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.espressoProfond)
                .contentTransition(.symbolEffect(.replace))
        }
        .scaleEffect(presse ? 1.08 : 1)
        .phaseAnimator(reduireAnimations || actif ? [false] : [false, true]) { contenu, phase in
            contenu.scaleEffect(phase ? 1.05 : 1)
        } animation: { _ in
            .easeInOut(duration: 1.8)
        }
        .offset(y: -16)
        .contentShape(Circle())
        .gesture(
            LongPressGesture(minimumDuration: 0.45)
                .updating($presse) { valeur, etat, _ in etat = valeur }
                .onEnded { _ in
                    assistantOuvert += 1
                    appuiLong()
                }
                .exclusively(before: TapGesture().onEnded { action() })
        )
        .animation(.endryVif, value: presse)
        .sensoryFeedback(.impact(weight: .medium), trigger: assistantOuvert)
        .accessibilityElement()
        .accessibilityLabel(Text("Dicter une saisie terrain"))
        .accessibilityHint(Text("Toucher long : assistant vocal."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
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
