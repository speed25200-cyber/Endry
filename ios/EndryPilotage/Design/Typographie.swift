import SwiftUI
import UIKit

/// Échelle typographique fixe : 34 / 28 / 22 / 17 / 15 / 13 (plus 11 pour les étiquettes).
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

/// Typographie de la maison Endry :
/// - titres en Cormorant Garamond, serif classique proche du « ENDRY SA » du logo ;
/// - étiquettes en capitales Cinzel, comme la devise « SANITAIRE CHAUFFAGE VENTILATION » ;
/// - texte courant et chiffres en SF Pro (police du site), chiffres tabulaires.
/// Polices embarquées sous licence OFL ; toutes les tailles suivent Dynamic Type.
enum Police {
    /// Le serif a un petit œil : on l'agrandit d'un cran pour garder la même présence que le texte.
    static let facteurSerif: CGFloat = 1.18

    /// Titres : SF Pro Display (semi-gras), chiffres tabulaires.
    static func titre(_ taille: CGFloat, relativeTo style: Font.TextStyle = .title, graisse: GraisseTitre = .semibold) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: Echelle.palier(taille)),
                weight: graisse == .medium ? .medium : graisse == .italique ? .regular : .semibold)
    }

    static func texte(_ taille: CGFloat = 17, relativeTo style: Font.TextStyle = .body, graisse: GraisseTexte = .regular) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: Echelle.palier(taille)), weight: graisse.poids)
    }

    /// Texte hors échelle (proportions internes d'un montant) : jamais utilisé pour du texte courant.
    static func texteLibre(_ taille: CGFloat, relativeTo style: Font.TextStyle = .body, graisse: GraisseTexte = .semibold) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: taille), weight: graisse.poids)
    }

    /// Étiquettes en capitales (Cinzel), à la manière de la devise du logo.
    static func etiquette(_ taille: CGFloat = 11, relativeTo style: Font.TextStyle = .caption2) -> Font {
        .custom("Cinzel-SemiBold", size: taille, relativeTo: style)
    }

    /// Chiffres : SF Pro, chiffres tabulaires, mis à l'échelle avec Dynamic Type.
    static func chiffres(_ taille: CGFloat, relativeTo style: Font.TextStyle = .body, graisse: Font.Weight = .semibold) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: taille), weight: graisse).monospacedDigit()
    }

    /// Références (V-…, RE-…) : monospace système.
    static func reference(_ taille: CGFloat = 12, relativeTo style: Font.TextStyle = .caption) -> Font {
        .system(size: taille, weight: .medium, design: .monospaced)
    }

    enum GraisseTitre {
        case medium, semibold, italique
        var nom: String {
            switch self {
            case .medium: "CormorantGaramond-Medium"
            case .semibold: "CormorantGaramond-SemiBold"
            case .italique: "CormorantGaramond-MediumItalic"
            }
        }
    }

    enum GraisseTexte {
        case regular, medium, semibold
        var poids: Font.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            }
        }
    }
}

extension View {
    /// Titre en Cormorant Garamond, chiffres tabulaires.
    func styleTitre(_ taille: CGFloat, relativeTo style: Font.TextStyle = .title, graisse: Police.GraisseTitre = .semibold) -> some View {
        font(Police.titre(taille, relativeTo: style, graisse: graisse))
            .tracking(-0.015 * Echelle.palier(taille))
            .monospacedDigit()
    }

    /// Étiquette en capitales Cinzel, espacées comme la devise du logo.
    func styleSurtitre() -> some View {
        etiquetteMaison()
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
