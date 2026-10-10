import EndryKit
import SwiftUI

// MARK: - Matières

/// Aurore dorée : MeshGradient figé (fond des cartes héros). Rendu une fois, jamais redessiné pendant le défilement.
struct AuroreOr: View {
    var intensite: Double = 1

    var body: some View {
        MeshGradient(
                width: 3,
                height: 3,
                points: Self.points(t: 11, amplitude: 1),
                colors: [
                    Color(hex: 0x3A2D1E), Color(hex: 0x241C15), Color(hex: 0x1B150F),
                    Color(hex: 0x46341C), Color(hex: 0x9F722A).opacity(0.35 + 0.2 * intensite), Color(hex: 0x241C15),
                    Color(hex: 0x17120D), Color(hex: 0x2A2016), Color(hex: 0x1B150F),
                ],
                smoothsColors: true
            )
    }

    /// Points du maillage 3×3 : les bords restent fixes, le centre et les milieux dérivent.
    static func points(t: Float, amplitude a: Float) -> [SIMD2<Float>] {
        let hautMilieu = SIMD2<Float>(0.5 + 0.08 * a * sin(t * 0.21), 0)
        let gauche = SIMD2<Float>(0, 0.45 + 0.12 * a * sin(t * 0.33))
        let centre = SIMD2<Float>(0.55 + 0.18 * a * sin(t * 0.17), 0.42 + 0.14 * a * cos(t * 0.23))
        let droite = SIMD2<Float>(1, 0.55 + 0.10 * a * cos(t * 0.29))
        let basMilieu = SIMD2<Float>(0.5 + 0.10 * a * cos(t * 0.19), 1)
        return [
            SIMD2<Float>(0, 0), hautMilieu, SIMD2<Float>(1, 0),
            gauche, centre, droite,
            SIMD2<Float>(0, 1), basMilieu, SIMD2<Float>(1, 1),
        ]
    }
}

/// Fond des écrans secondaires (Maison Endry) : brun profond ou papier, une lueur crème à peine posée en haut.
/// Aucun dégradé animé ni grain : rien ne se recalcule pendant le défilement.
/// Même trame de points que l'accueil (poste de pilotage).
struct FondAmbiant: View {
    var body: some View {
        FondMaison(discret: true)
            .overlay(alignment: .topLeading) {
                RadialGradient(colors: [Color.signal.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 420)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
    }
}

struct MatiereEspresso: View {
    var rayon: CGFloat = Espace.rayon

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: rayon, style: .continuous)
        AuroreOr()
            .clipShape(forme)
            .colorEffect(ShaderLibrary.refletEspresso(.boundingRect, .float(0), .float(0)))
            .background(forme.fill(Color.espresso.shadow(.drop(color: Color.ombre, radius: 26, y: 16))))
        .overlay {
            forme.strokeBorder(
                LinearGradient(colors: [Color.orClair.opacity(0.5), Color.or.opacity(0.10), Color.or.opacity(0.3)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: Espace.filet
            )
        }
    }
}
