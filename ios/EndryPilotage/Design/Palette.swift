import SwiftUI
import UIKit

/// Palette « banque privée » : noir chaud et or signature en sombre, ivoire et bronze en clair.
/// Le thème clair n'est pas une inversion : ses surfaces sont du papier ivoire, ses accents du bronze
/// (l'or pur manque de contraste sur fond clair). Deux couleurs d'état seulement : sauge (« fait »)
/// et ambre (« attend ») ; la rouille est réservée aux gestes destructifs.
extension Color {
    // MARK: Fonds et surfaces

    /// Fond : noir chaud #0B0A09 (jamais #000 pur) ou ivoire.
    static let fond = Color(clair: 0xF4EFE6, sombre: 0x0B0A09)
    /// Surfaces des cartes, légèrement relevées.
    static let surface = Color(clair: 0xFBF8F2, sombre: 0x151311)
    /// Surface creusée (tuiles, champs, pistes).
    static let surfaceCreuse = Color(clair: 0xEAE3D6, sombre: 0x1F1C18)

    // MARK: Encres (contraste AA sur fond et surface)

    /// Texte principal : ivoire #F4EFE6 en sombre, brun presque noir en clair.
    static let encre = Color(clair: 0x1B1814, sombre: 0xF4EFE6)
    static let encreDouce = Color(clair: 0x5A5247, sombre: 0xB3AB9E)
    /// Légendes : 4.5:1 minimum sur le fond.
    static let encrePale = Color(clair: 0x6E6557, sombre: 0x8A8275)
    /// Filets et séparateurs.
    static let filet = Color(clair: 0xDDD3C2, sombre: 0x2A2621)

    // MARK: Or signature

    /// Or signature #C9A55C, lumière #E8D3A2, ombre #8C6E35.
    static let or = Color(hex: 0xC9A55C)
    static let orClair = Color(hex: 0xE8D3A2)
    static let orOmbre = Color(hex: 0x8C6E35)
    /// Accent lisible dans les deux thèmes : or en sombre, bronze profond en clair (texte, icônes).
    static let bronze = Color(clair: 0x7A5C28, sombre: 0xC9A55C)
    static let bronzeMoyen = Color(hex: 0xA8874A)
    /// Bordure fine des surfaces : or à 18 %, 0.5 pt.
    static let bordureOr = Color.or.opacity(0.18)

    // MARK: Matière sombre (cartes héros, curseur d'envoi) : identique dans les deux thèmes

    static let espresso = Color(hex: 0x14120F)
    static let espressoProfond = Color(hex: 0x070605)

    // MARK: États

    /// Sauge : « fait », « oui ».
    static let sauge = Color(clair: 0x4D6B4E, sombre: 0x9CB89A)
    /// Ambre : « attend ».
    static let ambre = Color(clair: 0x8A5A12, sombre: 0xE2AE55)
    /// Rouille : gestes destructifs et erreurs uniquement.
    static let rouille = Color(clair: 0xA2402A, sombre: 0xE8836C)
    /// Ancien nom de la couleur « fait » (conservé pour les écrans).
    static let vertControle = sauge

    /// Ombre portée : profonde en sombre, à peine perceptible sur le papier ivoire.
    static let ombre = Color(clair: 0x3A2E1A, sombre: 0x000000, opaciteClair: 0.10, opaciteSombre: 0.5)
    /// Reflet du haut des surfaces (lumière rasante).
    static let reflet = Color(clair: 0xFFFFFF, sombre: 0xFFFFFF, opaciteClair: 0.7, opaciteSombre: 0.045)

    init(hex: UInt32, opacite: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacite
        )
    }

    init(clair: UInt32, sombre: UInt32, opaciteClair: CGFloat = 1, opaciteSombre: CGFloat = 1) {
        self.init(uiColor: UIColor { trait in
            let sombreActif = trait.userInterfaceStyle == .dark
            let hex = sombreActif ? sombre : clair
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: sombreActif ? opaciteSombre : opaciteClair
            )
        })
    }
}

extension ShapeStyle where Self == LinearGradient {
    /// Or brossé : accents, bouton micro, curseur d'envoi.
    static var degradeOr: LinearGradient {
        LinearGradient(colors: [.orClair, .or, .orOmbre], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Or pour le texte : reflet plus lumineux au centre.
    static var texteOr: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xB8914A), .orClair, .or, Color(hex: 0x9E7B3C)],
                       startPoint: .leading, endPoint: .trailing)
    }
}

/// Grille d'espacement 4 / 8 pt.
enum Espace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    /// Marge latérale des écrans : 16 pt.
    static let bord: CGFloat = 16
    /// Rayon des cartes.
    static let rayon: CGFloat = 28
    static let rayonPetit: CGFloat = 16
    /// Épaisseur des filets dorés.
    static let filet: CGFloat = 0.5
}

// MARK: - Mouvement

extension Animation {
    /// Ressort maison : utilisé partout, aucune animation linéaire.
    static let endry = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Ressort plus vif (petits éléments, pressions).
    static let endryVif = Animation.spring(response: 0.28, dampingFraction: 0.8)
    /// Fondu utilisé à la place des déplacements quand « Réduire les animations » est actif.
    static let fonduDoux = Animation.easeInOut(duration: 0.22)

    /// Ressort, ou fondu si l'utilisateur a demandé moins d'animations.
    static func endry(reduire: Bool) -> Animation { reduire ? .fonduDoux : .endry }
}

// MARK: - Thème

/// Choix d'apparence dans les Réglages : suit le système par défaut.
enum ThemeApparence: String, CaseIterable, Identifiable {
    case systeme, clair, sombre

    static let cle = "apparence"

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .systeme: "Système"
        case .clair: "Clair"
        case .sombre: "Sombre"
        }
    }

    var schema: ColorScheme? {
        switch self {
        case .systeme: nil
        case .clair: .light
        case .sombre: .dark
        }
    }
}
