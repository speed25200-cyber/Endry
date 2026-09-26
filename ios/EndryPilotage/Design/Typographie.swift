import SwiftUI

/// Inter Tight (titres, montants) + Inter (texte), embarquées sous licence OFL.
/// Si une police manque, SwiftUI retombe sur SF Pro. Toutes les tailles suivent Dynamic Type.
enum Police {
    static func titre(_ taille: CGFloat, relativeTo style: Font.TextStyle = .title, graisse: GraisseTitre = .semibold) -> Font {
        .custom(graisse.nom, size: taille, relativeTo: style)
    }

    static func texte(_ taille: CGFloat = 16, relativeTo style: Font.TextStyle = .body, graisse: GraisseTexte = .regular) -> Font {
        .custom(graisse.nom, size: taille, relativeTo: style)
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
    /// Titre Inter Tight, interlettrage serré (−4 %), chiffres tabulaires.
    func styleTitre(_ taille: CGFloat, relativeTo style: Font.TextStyle = .title, graisse: Police.GraisseTitre = .semibold) -> some View {
        font(Police.titre(taille, relativeTo: style, graisse: graisse))
            .tracking(-0.04 * taille)
            .monospacedDigit()
    }

    /// Surtitre en petites capitales espacées.
    func styleSurtitre() -> some View {
        font(Police.texte(11, relativeTo: .caption2, graisse: .semibold))
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(Color.encrePale)
    }

    func styleTexte(_ taille: CGFloat = 16, relativeTo style: Font.TextStyle = .body, graisse: Police.GraisseTexte = .regular) -> some View {
        font(Police.texte(taille, relativeTo: style, graisse: graisse))
    }
}
