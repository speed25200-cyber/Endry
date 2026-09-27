import EndryKit
import SwiftUI

// MARK: - Matières

/// Aurore dorée : MeshGradient dont les points dérivent lentement (fond des cartes héros et de l'accueil).
struct AuroreOr: View {
    var intensite: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduireAnimations)) { contexte in
            let t = Float(contexte.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600))
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.points(t: t, amplitude: reduireAnimations ? 0 : 1),
                colors: [
                    Color(hex: 0x2A1F0F), Color(hex: 0x0D0D10), Color(hex: 0x070708),
                    Color(hex: 0x3A2A10), Color(hex: 0x7A5A22).opacity(0.55 + 0.25 * intensite), Color(hex: 0x0E0E12),
                    Color(hex: 0x060607), Color(hex: 0x1D160B), Color(hex: 0x09090B),
                ],
                smoothsColors: true
            )
        }
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

/// Matière des cartes héros : aurore + grain + reflet qui balaie (shader Metal), filet doré.
struct MatiereEspresso: View {
    var rayon: CGFloat = Espace.rayon
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: rayon, style: .continuous)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduireAnimations)) { contexte in
            let temps = Float(contexte.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1_400))
            AuroreOr()
                .clipShape(forme)
                .colorEffect(ShaderLibrary.refletEspresso(.boundingRect, .float(temps), .float(reduireAnimations ? 0 : 1)))
        }
        .overlay {
            forme.strokeBorder(
                LinearGradient(colors: [Color.orClair.opacity(0.55), Color.or.opacity(0.06), Color.or.opacity(0.28)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.8
            )
        }
        .shadow(color: Color.or.opacity(0.10), radius: 30, y: 0)
        .shadow(color: .black.opacity(0.6), radius: 28, y: 18)
    }
}

// MARK: - Effets

/// Reflet lumineux qui traverse un texte doré toutes les quelques secondes.
struct RefletDore: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(geo.size.width * 0.3, 1))
                        .rotationEffect(.degrees(18))
                        .offset(x: phase * geo.size.width * 1.3)
                        .blendMode(.plusLighter)
                }
                .mask(content)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onAppear {
                guard !reduireAnimations else { return }
                withAnimation(.easeInOut(duration: 2.6).delay(0.8).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

extension View {
    func refletDore() -> some View { modifier(RefletDore()) }
}

/// Montant qui « compte » depuis zéro à l'apparition, puis défile à chaque changement.
struct MontantAnime: View {
    var montant: Double
    var taille: CGFloat = 34
    var dore = false
    var couleur: Color = .encre
    var afficherCentimes = true
    var style: Font.TextStyle = .largeTitle

    @State private var affiche: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        MontantView(montant: affiche, taille: taille, couleur: couleur,
                    couleurDevise: dore ? Color.or.opacity(0.75) : nil,
                    afficherCentimes: afficherCentimes, style: style, dore: dore)
            .onAppear {
                if reduireAnimations {
                    affiche = montant
                } else {
                    withAnimation(.spring(response: 1.1, dampingFraction: 0.9).delay(0.15)) { affiche = montant }
                }
            }
            .onChange(of: montant) { _, nouveau in
                withAnimation(.snappy) { affiche = nouveau }
            }
            .accessibilityLabel(Text(FormatSuisse.chf(montant)))
    }
}

// MARK: - Carte héros

/// Carte héros « Trésorerie » de l'écran Aujourd'hui.
struct CarteHeros: View {
    var encaisser: Encaisser
    var offres: Offres
    var payer: Payer
    var ouvrirFinances: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.l) {
            HStack(alignment: .center) {
                Label("Trésorerie", systemImage: "sparkle")
                    .font(Police.texte(11, relativeTo: .caption2, graisse: .semibold))
                    .textCase(.uppercase)
                    .tracking(1.6)
                    .foregroundStyle(Color.or)
                Spacer()
                Text("\(encaisser.factures.count) factures ouvertes")
                    .font(Police.texte(11, relativeTo: .caption2, graisse: .medium))
                    .foregroundStyle(Color.orClair.opacity(0.55))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("À encaisser")
                    .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                    .foregroundStyle(Color.orClair.opacity(0.7))
                MontantAnime(montant: encaisser.total, taille: 50, dore: true)
                    .refletDore()
            }

            BarreAnciennete(segments: [
                .init(libelle: "À échoir", montant: encaisser.anciennete.aEchoir, couleur: Color.orClair),
                .init(libelle: "0–30 j", montant: encaisser.anciennete.jours0a30, couleur: Color.or),
                .init(libelle: "> 30 j", montant: encaisser.anciennete.plus30, couleur: Color(hex: 0xE0674E)),
            ], hauteur: 6, surFondSombre: true)

            HStack(spacing: Espace.s) {
                TuileVerre(titre: "Offres en attente", montant: offres.total, detail: "\(offres.offres.count) offres", icone: "doc.richtext")
                TuileVerre(titre: "À payer · 7 jours", montant: payer.totalSemaine, detail: "\(payer.cetteSemaine.count) échéances", icone: "calendar.badge.clock")
            }
        }
        .padding(Espace.l)
        .background(MatiereEspresso())
        .contentShape(RoundedRectangle(cornerRadius: Espace.rayon, style: .continuous))
        .onTapGesture(perform: ouvrirFinances)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Ouvre l’espace Finances"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Petite tuile en verre posée sur une matière sombre.
struct TuileVerre: View {
    var titre: String
    var montant: Double
    var detail: String
    var icone: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icone)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.or)
            Text(titre)
                .styleTexte(11, relativeTo: .caption2, graisse: .medium)
                .foregroundStyle(Color.orClair.opacity(0.6))
                .lineLimit(1)
            MontantAnime(montant: montant, taille: 19, couleur: .orClair, afficherCentimes: false, style: .headline)
            Text(detail)
                .styleTexte(10, relativeTo: .caption2)
                .foregroundStyle(Color.orClair.opacity(0.45))
        }
        .padding(Espace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6))
    }
}

#Preview("Carte héros") {
    let a = Fixtures.accueil
    return CarteHeros(encaisser: a.encaisser, offres: a.offres, payer: a.payer) {}
        .padding()
        .background(Color.fond)
        .preferredColorScheme(.dark)
}
