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

/// Fond des écrans : noir chaud (ou ivoire), aurore or presque imperceptible, grain photographique léger
/// (shader Metal). Figé : rendu une fois, le défilement ne le redessine pas.
struct FondAmbiant: View {
    @Environment(\.colorScheme) private var schema

    var body: some View {
        ZStack(alignment: .top) {
            Color.fond
            MeshGradient(
                width: 3,
                height: 3,
                points: AuroreOr.points(t: 7, amplitude: 1),
                colors: schema == .dark ? Self.nuit : Self.jour,
                smoothsColors: true
            )
            .frame(height: 560)
            .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
        }
        .colorEffect(ShaderLibrary.grain(.float(schema == .dark ? 0.035 : 0.025)))
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private static let nuit: [Color] = [
        Color(hex: 0x33281C), Color(hex: 0x241C15), Color(hex: 0x211A13),
        Color(hex: 0x2A2118), Color(hex: 0x3A2D1C), Color(hex: 0x221B14),
        Color(hex: 0x211A13), Color(hex: 0x211A13), Color(hex: 0x211A13),
    ]
    private static let jour: [Color] = [
        Color(hex: 0xEFE7D8), Color(hex: 0xF6F5F2), Color(hex: 0xF6F5F2),
        Color(hex: 0xF3EDE2), Color(hex: 0xEDE2CD), Color(hex: 0xF6F5F2),
        Color(hex: 0xF6F5F2), Color(hex: 0xF6F5F2), Color(hex: 0xF6F5F2),
    ]
}

/// Matière des cartes héros : aurore + grain + lueur chaude (shader Metal), filet doré. Figée.
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
                // Un seul passage à l'apparition : aucune animation perpétuelle.
                withAnimation(.easeInOut(duration: 2.6).delay(0.8)) {
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
                    withAnimation(.endry.delay(0.15)) { affiche = montant }
                }
            }
            .onChange(of: montant) { _, nouveau in
                withAnimation(.endry) { affiche = nouveau }
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
