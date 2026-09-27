import EndryKit
import SwiftUI

/// Montant suisse haut de gamme : « CHF » en petites capitales, francs en grand, centimes en exposant.
/// Les chiffres défilent (`numericText`) quand la valeur change.
struct MontantView: View {
    var montant: Double
    var taille: CGFloat = 34
    var couleur: Color = .encre
    var couleurDevise: Color? = nil
    var afficherCentimes = true
    var style: Font.TextStyle = .largeTitle
    /// Chiffres en or brossé (montants héros).
    var dore = false

    var body: some View {
        let parties = FormatSuisse.parties(afficherCentimes ? montant : montant.rounded())
        HStack(alignment: .firstTextBaseline, spacing: taille * 0.14) {
            Text("CHF")
                .font(Police.texte(max(10, taille * 0.34), relativeTo: .caption, graisse: .semibold))
                .tracking(taille * 0.02)
                .foregroundStyle(couleurDevise ?? couleur.opacity(0.62))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(parties.signe + parties.francs)
                    .font(Police.titre(taille, relativeTo: style))
                    .tracking(-0.045 * taille)
                    .contentTransition(.numericText(value: montant))
                if afficherCentimes {
                    Text(parties.centimes)
                        .font(Police.titre(taille * 0.46, relativeTo: style, graisse: .medium))
                        .tracking(-0.01 * taille)
                        .baselineOffset(taille * 0.42)
                        .contentTransition(.numericText(value: montant))
                        .opacity(0.78)
                }
            }
            .foregroundStyle(dore ? AnyShapeStyle(.texteOr) : AnyShapeStyle(couleur))
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(FormatSuisse.chf(montant)))
    }
}

/// Référence technique (V-7K3F9Q, RE-2026-0412) en monospace dans une pastille discrète.
struct ReferenceView: View {
    var texte: String

    var body: some View {
        Text(texte)
            .font(Police.reference(11))
            .foregroundStyle(Color.encreDouce)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.surfaceCreuse, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

#Preview("Montants") {
    VStack(alignment: .leading, spacing: 24) {
        MontantView(montant: 13_695.45)
        MontantView(montant: 46_109.70, taille: 48, couleur: .orClair)
            .padding()
            .background(Color.espresso)
        MontantView(montant: 486.35, taille: 17, style: .body)
        ReferenceView(texte: "V-7K3F9Q")
    }
    .padding()
    .background(Color.fond)
}
