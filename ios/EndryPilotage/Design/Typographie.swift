import SwiftUI
import UIKit

/// Échelle typographique fixe : 34 / 28 / 22 / 17 / 15 / 13 (plus 11 pour les surtitres et badges).
/// Toute taille demandée est ramenée au palier le plus proche : le rythme reste le même sur tous les écrans.
enum Echelle {
    static let titre1: CGFloat = 34
    static let titre2: CGFloat = 28
    static let titre3: CGFloat = 22
    static let corps: CGFloat = 17
    static let secondaire: CGFloat = 15
    static let legende: CGFloat = 13
    static let micro: CGFloat = 11

    static func palier(_ taille: CGFloat) -> CGFloat {
        switch taille {
        case ..<12.5: micro
        case ..<14: legende
        case ..<16.5: secondaire
        case ..<19.5: corps
        case ..<25: titre3
        case ..<31: titre2
        default: titre1
        }
    }
}

/// Inter Tight (titres) + Inter (texte), embarquées sous licence OFL ; chiffres en SF Mono tabulaire.
/// Si une police manque, SwiftUI retombe sur SF Pro. Toutes les tailles suivent Dynamic Type.
enum Police {
    static func titre(_ taille: CGFloat, relativeTo style: Font.TextStyle = .title, graisse: GraisseTitre = .semibold) -> Font {
        .custom(graisse.nom, size: Echelle.palier(taille), relativeTo: style)
    }

    static func texte(_ taille: CGFloat = 17, relativeTo style: Font.TextStyle = .body, graisse: GraisseTexte = .regular) -> Font {
        .custom(graisse.nom, size: Echelle.palier(taille), relativeTo: style)
    }

    /// Texte hors échelle (proportions internes d'un montant) : jamais utilisé pour du texte courant.
    static func texteLibre(_ taille: CGFloat, relativeTo style: Font.TextStyle = .body, graisse: GraisseTexte = .semibold) -> Font {
        .custom(graisse.nom, size: taille, relativeTo: style)
    }

    /// Chiffres : SF Mono tabulaire, mis à l'échelle avec Dynamic Type.
    static func chiffres(_ taille: CGFloat, relativeTo style: Font.TextStyle = .body, graisse: Font.Weight = .semibold) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: taille), weight: graisse, design: .monospaced)
    }

    /// Références (V-…, RE-…) : monospace système.
    static func reference(_ taille: CGFloat = 12, relativeTo style: Font.TextStyle = .caption) -> Font {
        .system(size: taille, weight: .medium, design: .monospaced)
    }

    enum GraisseTitre {
        case medium, semibold
        var nom: String { self == .medium ? "InterTight-Medium" : "InterTight-SemiBold" }
    }

    enum GraisseTexte {
        case regular, medium, semibold
        var nom: String {
            switch self {
            case .regular: "Inter-Regular"
            case .medium: "Inter-Medium"
            case .semibold: "Inter-SemiBold"
            }
        }
    }
}

extension View {
    /// Titre Inter Tight Semibold, interlettrage serré (−2.5 %), chiffres tabulaires.
    func styleTitre(_ taille: CGFloat, relativeTo style: Font.TextStyle = .title, graisse: Police.GraisseTitre = .semibold) -> some View {
        font(Police.titre(taille, relativeTo: style, graisse: graisse))
            .tracking(-0.025 * Echelle.palier(taille))
            .monospacedDigit()
    }

    /// Surtitre en petites capitales espacées.
    func styleSurtitre() -> some View {
        font(Police.texte(Echelle.micro, relativeTo: .caption2, graisse: .semibold))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(Color.encrePale)
    }

    func styleTexte(_ taille: CGFloat = 17, relativeTo style: Font.TextStyle = .body, graisse: Police.GraisseTexte = .regular) -> some View {
        font(Police.texte(taille, relativeTo: style, graisse: graisse))
    }
}

extension Font.TextStyle {
    /// Équivalent UIKit, pour `UIFontMetrics`.
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
