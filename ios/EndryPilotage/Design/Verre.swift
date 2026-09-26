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
                .overlay(forme.stroke(Color.white.opacity(0.18), lineWidth: 0.5))
        }
        #else
        background(.ultraThinMaterial, in: forme)
            .overlay(forme.stroke(Color.white.opacity(0.18), lineWidth: 0.5))
        #endif
    }
}

// MARK: - Onglets

enum Onglet: String, CaseIterable, Identifiable, Hashable {
    case decisions, chantiers, saisie, argent, planning

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .decisions: "Décisions"
        case .chantiers: "Chantiers"
        case .saisie: "Dicter"
        case .argent: "Argent"
        case .planning: "Planning"
        }
    }

    var icone: String {
        switch self {
        case .decisions: "checkmark.seal"
        case .chantiers: "hammer"
        case .saisie: "mic"
        case .argent: "banknote"
        case .planning: "calendar"
        }
    }

    var iconeActive: String {
        switch self {
        case .decisions: "checkmark.seal.fill"
        case .chantiers: "hammer.fill"
        case .saisie: "mic.fill"
        case .argent: "banknote.fill"
        case .planning: "calendar.badge.clock"
        }
    }
}

/// Barre d'onglets flottante en verre, bouton micro central surélevé doré.
struct BarreOnglets: View {
    @Binding var selection: Onglet
    var badgeDecisions: Int
    @Namespace private var espace
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        HStack(spacing: 0) {
            bouton(.decisions)
            bouton(.chantiers)
            BoutonMicroCentral(actif: selection == .saisie) {
                selection = .saisie
            }
            .frame(maxWidth: .infinity)
            bouton(.argent)
            bouton(.planning)
        }
        .padding(.horizontal, 6)
        .frame(height: 64)
        .verre(Capsule(), interactif: true)
        .shadow(color: Color.espressoProfond.opacity(0.18), radius: 20, y: 8)
        .padding(.horizontal, Espace.m)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func bouton(_ onglet: Onglet) -> some View {
        let actif = selection == onglet
        return Button {
            withAnimation(reduireAnimations ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.78)) {
                selection = onglet
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: actif ? onglet.iconeActive : onglet.icone)
                    .font(.system(size: 18, weight: actif ? .semibold : .regular))
                    .symbolEffect(.bounce.down, value: actif)
                    .overlay(alignment: .topTrailing) {
                        if onglet == .decisions, badgeDecisions > 0 {
                            Text("\(badgeDecisions)")
                                .font(Police.titre(10, relativeTo: .caption2))
                                .monospacedDigit()
                                .foregroundStyle(Color.espresso)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Color.or, in: Capsule())
                                .offset(x: 10, y: -6)
                                .contentTransition(.numericText(value: Double(badgeDecisions)))
                                .accessibilityHidden(true)
                        }
                    }
                Text(onglet.titre)
                    .font(Police.texte(10, relativeTo: .caption2, graisse: actif ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(actif ? Color.encre : Color.encrePale)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                if actif {
                    Capsule()
                        .fill(Color.encre.opacity(0.07))
                        .matchedGeometryEffect(id: "onglet", in: espace)
                        .padding(.vertical, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(onglet == .decisions && badgeDecisions > 0 ? "\(onglet.titre), \(badgeDecisions) en attente" : onglet.titre))
        .accessibilityAddTraits(actif ? .isSelected : [])
        .accessibilityIdentifier("onglet-\(onglet.rawValue)")
    }
}

/// Bouton micro doré, qui respire au repos.
struct BoutonMicroCentral: View {
    var actif: Bool
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.degradeOr)
                    .frame(width: 60, height: 60)
                    .shadow(color: Color.bronzeMoyen.opacity(0.55), radius: 14, y: 6)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8).padding(1))
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.espresso)
            }
            .phaseAnimator(reduireAnimations || actif ? [false] : [false, true]) { contenu, phase in
                contenu.scaleEffect(phase ? 1.045 : 1)
            } animation: { _ in
                .easeInOut(duration: 1.8)
            }
            .offset(y: -14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Dicter une saisie terrain"))
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
        .shadow(color: Color.espressoProfond.opacity(0.15), radius: 18, y: 8)
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
                            withAnimation(.snappy) {
                                if toast.wrappedValue?.id == valeur.id { toast.wrappedValue = nil }
                            }
                        }
                        .onTapGesture { withAnimation(.snappy) { toast.wrappedValue = nil } }
                }
            }
            .padding(.bottom, decalageBas)
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: toast.wrappedValue?.id)
        }
    }
}
