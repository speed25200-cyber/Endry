import SwiftUI

/// Orbe « façon Siri » aux couleurs Endry (maquette Maison Endry) : dans une sphère de verre sombre, des volutes de
/// lumière — crème dorée, bronze, ambre et une touche de bleu glacier — tournent chacune sur leur orbite et se mêlent ;
/// un fin anneau de lumière fait le tour du bord et la sphère respire. Plus vive quand Endry écoute.
/// « Réduire les animations » : orbe immobile.
struct OrbeSiri: View {
    var diametre: CGFloat = 52
    var actif = false
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    private static let creme = Color(hex: 0xF9DBA3)
    private static let bronze = Color(hex: 0xC98F3C)
    private static let ambre = Color(hex: 0xE9A27E)
    private static let glacier = Color(hex: 0x9EC9D8)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduireAnimations)) { contexte in
            orbe(t: reduireAnimations ? 1.2 : contexte.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: diametre, height: diametre)
        .accessibilityHidden(true)
    }

    private func orbe(t: Double) -> some View {
        let vitesse = actif ? 1.9 : 1.0
        let souffle = 1 + (actif ? 0.06 : 0.035) * sin(t * (actif ? 3.2 : 1.5))
        let d = diametre
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x2A1D12), Color(hex: 0x120C07)],
                                     center: UnitPoint(x: 0.5, y: 0.55), startRadius: 0, endRadius: d * 0.55))
            Canvas { ctx, taille in
                let c = CGPoint(x: taille.width / 2, y: taille.height / 2)
                let r = taille.width
                ctx.addFilter(.blur(radius: r * 0.12))
                ctx.blendMode = .screen
                // (couleur, taille relative, orbite relative, vitesse angulaire, phase)
                let volutes: [(Color, Double, Double, Double, Double)] = [
                    (Self.creme, 0.6, 0.14, 1.15, 0),
                    (Self.bronze, 0.52, 0.18, -0.9, 2.1),
                    (Self.ambre, 0.44, 0.2, 1.4, 4.2),
                    (Self.glacier.opacity(0.75), 0.36, 0.16, -1.7, 1)
                ]
                for (couleur, part, orbite, vit, phase) in volutes {
                    let angle = t * vit * vitesse + phase
                    let rayon = r * orbite * (1 + 0.25 * sin(t * 0.8 + phase))
                    let p = CGPoint(x: c.x + cos(angle) * rayon, y: c.y + sin(angle) * rayon)
                    let s = r * part
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)), with: .color(couleur))
                }
            }
            .clipShape(Circle())
            Circle()
                .strokeBorder(AngularGradient(colors: [Self.creme.opacity(0), Self.creme.opacity(0.95), Self.glacier.opacity(0.7),
                                                       Self.ambre.opacity(0), Self.creme.opacity(0)],
                                              center: .center),
                              lineWidth: max(d * 0.05, 1.5))
                .blur(radius: 0.6)
                .rotationEffect(.radians(t * 1.75 * vitesse))
                .padding(d * 0.08)
            // Verre : ombre intérieure en bas, éclat en haut à gauche, liseré.
            Circle()
                .fill(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom))
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.5), .white.opacity(0)],
                                     center: UnitPoint(x: 0.34, y: 0.24), startRadius: 0, endRadius: d * 0.34))
            Circle()
                .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
        }
        .scaleEffect(souffle)
    }
}

#Preview {
    HStack(spacing: 24) {
        OrbeSiri()
        OrbeSiri(diametre: 120, actif: true)
    }
    .padding(40)
    .background(Color.fond)
}
