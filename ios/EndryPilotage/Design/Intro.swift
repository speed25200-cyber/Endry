import SwiftUI

/// Ouverture de l'app : le monogramme sort du brun du lancement, un filet d'or se trace sous « ENDRY SA »,
/// puis tout s'efface sur l'accueil. Raccourcie si « Réduire les animations » ; jamais pendant les tests.
struct IntroMaison: View {
    var terminer: () -> Void
    @State private var etape = 0
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        ZStack {
            Color.espresso.ignoresSafeArea()
            VStack(spacing: 20) {
                LogoEndry(taille: 92)
                    .scaleEffect(etape >= 1 || reduireAnimations ? 1 : 0.84)
                    .blur(radius: etape >= 1 || reduireAnimations ? 0 : 10)
                    .opacity(etape >= 1 ? 1 : 0)
                Capsule()
                    .fill(LinearGradient(colors: [Color.or.opacity(0), Color.or, Color.or.opacity(0)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: etape >= 2 ? 150 : 0, height: 1)
                Text("Endry SA")
                    .font(Police.etiquette(13, relativeTo: .footnote))
                    .textCase(.uppercase)
                    .tracking(etape >= 2 ? 7 : 2)
                    .foregroundStyle(Color.or)
                    .opacity(etape >= 2 ? 1 : 0)
            }
            .scaleEffect(etape >= 3 && !reduireAnimations ? 1.06 : 1)
        }
        .opacity(etape >= 3 ? 0 : 1)
        .allowsHitTesting(etape < 3)
        .accessibilityHidden(true)
        .task {
            let rythme = reduireAnimations ? 0.5 : 1.0
            withAnimation(.easeOut(duration: 0.7 * rythme)) { etape = 1 }
            try? await Task.sleep(for: .seconds(0.45 * rythme))
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.8 * rythme)) { etape = 2 }
            try? await Task.sleep(for: .seconds(0.85 * rythme))
            withAnimation(.easeIn(duration: 0.45)) { etape = 3 }
            try? await Task.sleep(for: .seconds(0.45))
            terminer()
        }
    }
}
