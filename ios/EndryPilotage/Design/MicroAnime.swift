import SwiftUI

/// Gros bouton micro : respiration au repos, anneaux et forme d'onde qui réagissent au niveau audio pendant la dictée.
struct MicroAnime: View {
    var ecoute: Bool
    var niveau: Float
    var historique: [Float]
    var diametre: CGFloat = 132
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        VStack(spacing: Espace.l) {
            Button(action: action) {
                ZStack {
                    // Anneaux concentriques : ils s'écartent avec la voix.
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .strokeBorder(Color.signal.opacity(ecoute ? 0.5 - Double(i) * 0.14 : 0.16 - Double(i) * 0.04), lineWidth: 0.75)
                            .frame(width: diametre + CGFloat(i + 1) * 26, height: diametre + CGFloat(i + 1) * 26)
                            .scaleEffect(ecoute && !reduireAnimations ? 1 + CGFloat(niveau) * (0.10 + CGFloat(i) * 0.06) : 1)
                            .animation(.endry, value: niveau)
                    }

                    // Maison Endry : bulle de verre au repos, crème dorée pendant l'écoute.
                    Group {
                        if ecoute {
                            Circle().fill(Color.bouton.shadow(.drop(color: Color.signal.opacity(0.35), radius: 26, y: 8)))
                        } else {
                            Color.clear.verreMaison(Circle(), interactif: true)
                        }
                    }
                    .frame(width: diametre, height: diametre)

                    Image(systemName: ecoute ? "stop.fill" : "mic")
                        .font(.system(size: diametre * 0.26, weight: ecoute ? .semibold : .light))
                        .foregroundStyle(ecoute ? Color.boutonTexte : Color.encre)
                        .contentTransition(.symbolEffect(.replace))
                }
                .keyframeAnimator(initialValue: 1.0, trigger: ecoute) { contenu, echelle in
                    contenu.scaleEffect(echelle)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(0.9, duration: 0.12)
                        SpringKeyframe(1.06, duration: 0.22)
                        SpringKeyframe(1.0, duration: 0.3)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(height: diametre + 90)
            .sensoryFeedback(.impact(weight: .heavy), trigger: ecoute)
            .accessibilityLabel(Text(ecoute ? "Arrêter la dictée" : "Commencer la dictée"))
            .accessibilityIdentifier("micro")

            FormeOnde(historique: historique, active: ecoute)
                .frame(height: 36)
                .padding(.horizontal, Espace.xl)
                .accessibilityHidden(true)
        }
    }
}

/// Forme d'onde : barres arrondies alimentées par l'historique du niveau audio.
struct FormeOnde: View {
    var historique: [Float]
    var active: Bool

    /// Toutes les barres en un seul tracé (une barre animée par vue relançait 28 ressorts à chaque tampon audio).
    var body: some View {
        Canvas { ctx, taille in
            let n = historique.count
            guard n > 0 else { return }
            let largeur: CGFloat = 3
            let ecart: CGFloat = 3
            var x = (taille.width - CGFloat(n) * largeur - CGFloat(n - 1) * ecart) / 2
            var barres = Path()
            for (index, valeur) in historique.enumerated() {
                let h = max(3, CGFloat(active ? valeur : 0.05) * taille.height * enveloppe(index))
                barres.addRoundedRect(in: CGRect(x: x, y: (taille.height - h) / 2, width: largeur, height: h),
                                      cornerSize: CGSize(width: largeur / 2, height: largeur / 2))
                x += largeur + ecart
            }
            ctx.fill(barres, with: .color(active ? Color.signal : Color.filetFort))
        }
    }

    /// Les barres du centre montent plus haut que celles des bords.
    private func enveloppe(_ i: Int) -> CGFloat {
        let n = CGFloat(max(historique.count - 1, 1))
        let x = CGFloat(i) / n
        return 0.45 + 0.55 * sin(.pi * x)
    }
}

#Preview {
    VStack {
        MicroAnime(ecoute: false, niveau: 0, historique: Array(repeating: 0, count: 28)) {}
        MicroAnime(ecoute: true, niveau: 0.6, historique: (0..<28).map { _ in Float.random(in: 0...1) }) {}
    }
    .background(Color.fond)
}
