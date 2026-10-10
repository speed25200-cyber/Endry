import SwiftUI
import UIKit

// MARK: - Palette {{ENTREPRISE}} (modèle)
//
// Tokens nommés, variante claire et sombre. Remplacer les valeurs hex par l'identité de l'entreprise :
// UNE couleur de signal, des neutres teintés (chauds ou froids), deux états (sain / alerte).
// Aucun écran n'utilise de couleur en dur.

extension Color {
    // Fonds et surfaces
    static let fond = Color(clair: 0xF6F5F2, sombre: 0x17110C)
    static let surface = Color(clair: 0xFDFCFA, sombre: 0x211A13)
    static let surfaceCreuse = Color(clair: 0xECE5D8, sombre: 0x2E241A)

    // Texte (contraste AA minimum dans les deux thèmes)
    static let encre = Color(clair: 0x211A13, sombre: 0xF6F0E6)
    static let encreDouce = Color(clair: 0x74695A, sombre: 0xB2A38B)
    static let encrePale = Color(clair: 0x6F6A63, sombre: 0x9C9282)

    // Filets
    static let filet = Color(clair: 0x211A13, sombre: 0xF9DBA3, opaciteClair: 0.1, opaciteSombre: 0.12)
    static let filetFort = Color(clair: 0x211A13, sombre: 0xF9DBA3, opaciteClair: 0.28, opaciteSombre: 0.3)

    // Signal de la marque (une seule couleur d'accent)
    static let signal = Color(clair: 0x9F722A, sombre: 0xF9DBA3)
    static let signalHalo = Color(clair: 0x9F722A, sombre: 0xF9DBA3, opaciteClair: 0.14, opaciteSombre: 0.16)
    static let etiquette = Color(clair: 0x8A6223, sombre: 0xD2A764)

    // Boutons pleins (curseur de validation, actions principales)
    static let bouton = Color(clair: 0x211A13, sombre: 0xF9DBA3)
    static let boutonTexte = Color(clair: 0xF9DBA3, sombre: 0x211A13)

    // Tuiles et verre
    static let tuileHaut = Color(clair: 0xFFFFFF, sombre: 0xF9DBA3, opaciteClair: 0.9, opaciteSombre: 0.085)
    static let tuileTeinte = Color(clair: 0xFFFFFF, sombre: 0xF9DBA3, opaciteClair: 0.72, opaciteSombre: 0.045)
    static let verreTeinte = Color(clair: 0xFFFFFF, sombre: 0xF9DBA3, opaciteClair: 0.6, opaciteSombre: 0.06)
    static let refletBord = Color(clair: 0xFFFFFF, sombre: 0xFFECC8, opaciteClair: 1, opaciteSombre: 0.22)
    static let ombre = Color(clair: 0x211A13, sombre: 0x000000, opaciteClair: 0.1, opaciteSombre: 0.5)

    // États
    static let sauge = Color(clair: 0x3D7046, sombre: 0x9CCB98)
    static let rouille = Color(clair: 0xA9462B, sombre: 0xE59474)

    init(hex: UInt32, opacite: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacite)
    }

    init(clair: UInt32, sombre: UInt32, opaciteClair: CGFloat = 1, opaciteSombre: CGFloat = 1) {
        self.init(uiColor: UIColor { trait in
            let sombreActif = trait.userInterfaceStyle == .dark
            let hex = sombreActif ? sombre : clair
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: sombreActif ? opaciteSombre : opaciteClair)
        })
    }
}

// MARK: - Espacements

enum Espace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    /// Filet d'un demi-point (un pixel physique sur les écrans @2x).
    static let filet: CGFloat = 0.5
}

// MARK: - Typographie

enum Police {
    /// Grands chiffres et titres : SF Pro, fin au-delà de 34 pt, chiffres tabulaires, Dynamic Type.
    static func serif(_ taille: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        let poids: Font.Weight = taille >= 34 ? .light : taille >= 22 ? .regular : .medium
        return .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: taille), weight: poids)
            .monospacedDigit()
    }

    /// Repères discrets (heures, « 4/7 ») : SF Pro medium, chiffres tabulaires.
    static func mono(_ taille: CGFloat = 11.5, relativeTo style: Font.TextStyle = .caption) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: taille + 1), weight: .medium)
            .monospacedDigit()
    }
}

extension Font.TextStyle {
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

// MARK: - Mouvement

extension Animation {
    /// Courbe unique de la maison.
    static let maison = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let fonduDoux = Animation.easeInOut(duration: 0.2)

    static func maison(reduire: Bool) -> Animation { reduire ? .fonduDoux : .maison }
}

// MARK: - Surfaces

extension View {
    /// Étiquette de section : petites capitales espacées (« À DÉCIDER »).
    func etiquetteMaison(_ taille: CGFloat = 11.5, couleur: Color = .etiquette) -> some View {
        font(.system(size: UIFontMetrics(forTextStyle: .caption1).scaledValue(for: taille), weight: .semibold))
            .textCase(.uppercase)
            .tracking(taille * 0.1)
            .foregroundStyle(couleur)
    }

    /// Tuile : dégradé teinté, filet fin, reflet sur le bord haut, ombre portée PAR LE REMPLISSAGE
    /// (aucune passe hors écran du contenu), sans flou d'arrière-plan : rien ne se recalcule au défilement.
    func tuileMaison(rayon: CGFloat = 24) -> some View {
        let forme = RoundedRectangle(cornerRadius: rayon, style: .continuous)
        return background {
            forme.fill(LinearGradient(colors: [Color.tuileHaut, Color.tuileTeinte],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
                .shadow(.drop(color: Color.ombre.opacity(0.55), radius: 22, y: 14)))
        }
        .overlay { forme.strokeBorder(Color.filet, lineWidth: Espace.filet) }
        .overlay {
            forme.strokeBorder(LinearGradient(colors: [Color.refletBord, .clear], startPoint: .top, endPoint: .center),
                               lineWidth: 1)
                .opacity(0.35)
        }
    }

    /// Verre pour ce qui flotte (boutons ronds, pastilles, barres) : Liquid Glass sur iOS 26, repli teinté.
    @ViewBuilder
    func verreMaison<S: InsettableShape>(_ forme: S, interactif: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(interactif ? Glass.regular.tint(Color.verreTeinte).interactive() : Glass.regular.tint(Color.verreTeinte),
                        in: forme)
                .overlay { forme.strokeBorder(Color.filet, lineWidth: Espace.filet) }
        } else {
            background { forme.fill(Color.verreTeinte) }
                .overlay { forme.strokeBorder(Color.filet, lineWidth: Espace.filet) }
        }
        #else
        background { forme.fill(Color.verreTeinte) }
            .overlay { forme.strokeBorder(Color.filet, lineWidth: Espace.filet) }
        #endif
    }
}

/// Pression : l'élément se tasse puis revient avec un léger ressort.
struct ActionPressee: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
