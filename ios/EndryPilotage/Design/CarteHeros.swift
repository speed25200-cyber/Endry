import EndryKit
import SwiftUI

/// Matière espresso : dégradé radial profond + grain + reflet lumineux (shader Metal).
struct MatiereEspresso: View {
    var rayon: CGFloat = Espace.rayon
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: rayon, style: .continuous)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduireAnimations)) { contexte in
            let temps = Float(contexte.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1_400))
            forme
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x4A3624), Color.espresso, Color.espressoProfond],
                        center: UnitPoint(x: 0.22, y: 0.0),
                        startRadius: 10,
                        endRadius: 520
                    )
                )
                .colorEffect(ShaderLibrary.refletEspresso(.boundingRect, .float(temps), .float(reduireAnimations ? 0 : 1)))
        }
        .overlay {
            forme.strokeBorder(
                LinearGradient(colors: [Color.or.opacity(0.55), Color.or.opacity(0.08), Color.or.opacity(0.3)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.8
            )
        }
        .shadow(color: Color.espressoProfond.opacity(0.35), radius: 24, y: 14)
    }
}

/// Carte héros « À encaisser » de l'écran Décisions.
struct CarteHeros: View {
    var encaisser: Encaisser
    var offres: Offres
    var payer: Payer
    var ouvrirArgent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.l) {
            VStack(alignment: .leading, spacing: Espace.xs) {
                HStack {
                    Text("À encaisser")
                        .font(Police.texte(12, relativeTo: .caption, graisse: .semibold))
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(Color.or.opacity(0.85))
                    Spacer()
                    Text("\(encaisser.factures.count) factures")
                        .styleTexte(12, relativeTo: .caption, graisse: .medium)
                        .foregroundStyle(Color.orClair.opacity(0.6))
                }
                MontantView(montant: encaisser.total, taille: 44, couleur: .orClair, couleurDevise: Color.or.opacity(0.7))
            }

            BarreAnciennete(segments: [
                .init(libelle: "À échoir", montant: encaisser.anciennete.aEchoir, couleur: Color.orClair),
                .init(libelle: "0–30 j", montant: encaisser.anciennete.jours0a30, couleur: Color.bronzeMoyen),
                .init(libelle: "> 30 j", montant: encaisser.anciennete.plus30, couleur: Color(hex: 0xC4583C)),
            ], hauteur: 8, surFondSombre: true)

            Rectangle().fill(Color.or.opacity(0.14)).frame(height: 0.5)

            HStack(alignment: .top, spacing: Espace.m) {
                TuileHeros(titre: "Offres en attente", montant: offres.total, detail: "\(offres.offres.count) offres")
                Rectangle().fill(Color.or.opacity(0.14)).frame(width: 0.5)
                TuileHeros(titre: "À payer cette semaine", montant: payer.totalSemaine, detail: "\(payer.cetteSemaine.count) échéances")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Espace.l)
        .background(MatiereEspresso())
        .contentShape(RoundedRectangle(cornerRadius: Espace.rayon, style: .continuous))
        .onTapGesture(perform: ouvrirArgent)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Ouvre l’écran Argent"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct TuileHeros: View {
    var titre: String
    var montant: Double
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre)
                .styleTexte(12, relativeTo: .caption, graisse: .medium)
                .foregroundStyle(Color.orClair.opacity(0.65))
            MontantView(montant: montant, taille: 20, couleur: .orClair, couleurDevise: Color.or.opacity(0.6), afficherCentimes: false, style: .title3)
            Text(detail)
                .styleTexte(11, relativeTo: .caption2)
                .foregroundStyle(Color.orClair.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Carte héros") {
    let a = Fixtures.accueil
    return CarteHeros(encaisser: a.encaisser, offres: a.offres, payer: a.payer) {}
        .padding()
        .background(Color.fond)
}
