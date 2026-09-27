import SwiftUI

/// Tirer-pour-actualiser personnalisé : anneau doré qui se remplit, monogramme au centre, retour haptique au seuil.
struct TirerPourActualiser: ViewModifier {
    var action: @MainActor () async -> Void

    @State private var tirage: CGFloat = 0
    @State private var arme = false
    @State private var enCours = false
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    private let seuil: CGFloat = 86

    func body(content: Content) -> some View {
        content
            .contentMargins(.top, enCours ? 64 : 0, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                -(geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, valeur in
                tirage = max(0, valeur)
                if tirage >= seuil, !arme, !enCours { arme = true }
            }
            .onScrollPhaseChange { ancienne, nouvelle in
                if ancienne == .interacting, nouvelle != .interacting {
                    if arme, !enCours { lancer() }
                    arme = false
                }
            }
            .overlay(alignment: .top) {
                IndicateurActualisation(progression: enCours ? 1 : min(tirage / seuil, 1), enCours: enCours)
                    .opacity(enCours || tirage > 8 ? 1 : 0)
                    .offset(y: enCours ? 12 : min(tirage, seuil) * 0.5 - 24)
                    .animation(.endry, value: enCours)
                    .allowsHitTesting(false)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: arme) { _, nouveau in nouveau }
            // VoiceOver : action nommée à la place du geste.
            .accessibilityAction(named: Text("Actualiser")) { lancer() }
    }

    private func lancer() {
        withAnimation(.endry) { enCours = true }
        Task {
            await action()
            withAnimation(.endry) { enCours = false }
        }
    }
}

struct IndicateurActualisation: View {
    var progression: CGFloat
    var enCours: Bool
    @State private var rotation = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        ZStack {
            Circle().stroke(Color.or.opacity(0.18), lineWidth: 2)
            Circle()
                .trim(from: 0, to: enCours ? 0.28 : progression)
                .stroke(.degradeOr, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90 + rotation))
            Text("E")
                .font(Police.titre(15, relativeTo: .caption))
                .foregroundStyle(Color.bronze)
                .scaleEffect(0.7 + 0.3 * progression)
        }
        .frame(width: 34, height: 34)
        .background(Color.surface, in: Circle())
        .shadow(color: Color.espresso.opacity(0.12), radius: 8, y: 3)
        .onChange(of: enCours) { _, actif in
            if actif, !reduireAnimations {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) { rotation = 360 }
            } else {
                withAnimation(.default) { rotation = 0 }
            }
        }
        .accessibilityLabel(Text(enCours ? "Actualisation en cours" : "Tirer pour actualiser"))
    }
}

extension View {
    func tirerPourActualiser(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(TirerPourActualiser(action: action))
    }
}
