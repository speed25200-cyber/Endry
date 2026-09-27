import SwiftUI
import UIKit

/// Palette de la maison Endry SA, tirée du logo et du site :
/// brun du logo `#211A13`, crème dorée des lettres `#F9DBA3`, bronze du « Y » `#9F722A`, papier `#F6F5F2`.
/// Thème sombre (par défaut, « Galerie ») : fond brun, cartes papier crème. Thème clair : papier et encre brune.
/// Deux couleurs d'état : sauge (« fait ») et ambre (« attend ») ; la rouille est réservée aux gestes destructifs.
extension Color {
    // MARK: Fonds et surfaces

    /// Fond : brun du logo, ou papier du site.
    static let fond = Color(clair: 0xF6F5F2, sombre: 0x211A13)
    /// Surfaces posées sur le fond (panneaux, tuiles).
    static let surface = Color(clair: 0xFFFFFF, sombre: 0x2B2219)
    /// Surface creusée (champs, pistes, pastilles).
    static let surfaceCreuse = Color(clair: 0xECE5D8, sombre: 0x3A3024)

    // MARK: Encres (contraste AA sur fond et surface)

    static let encre = Color(clair: 0x241E17, sombre: 0xF7F2E9)
    static let encreDouce = Color(clair: 0x5F5850, sombre: 0xC1B7A7)
    static let encrePale = Color(clair: 0x6F6A63, sombre: 0x9C9282)
    static let filet = Color(clair: 0xDDD9D2, sombre: 0x443A2C)

    // MARK: Or de la maison

    /// Crème dorée des lettres du logo : accents, bouton micro, titres en italique.
    static let or = Color(hex: 0xF9DBA3)
    static let orClair = Color(hex: 0xFFF0D4)
    /// Bronze du « Y » du monogramme.
    static let orOmbre = Color(hex: 0x9F722A)
    /// Accent de texte lisible dans les deux thèmes : crème dorée en sombre, bronze profond en clair.
    static let bronze = Color(clair: 0x865D20, sombre: 0xF9DBA3)
    static let bronzeMoyen = Color(hex: 0x9F722A)
    /// Filet fin des surfaces.
    static let bordureOr = Color(clair: 0xDDD9D2, sombre: 0x443A2C)

    // MARK: Papier (cartes de décision, fiches) : identique dans les deux thèmes

    static let papier = Color(hex: 0xF6F5F2)
    static let papierCreuse = Color(hex: 0xECE5D8)
    static let encrePapier = Color(hex: 0x241E17)
    static let encrePapierDouce = Color(hex: 0x6F6A63)
    static let bronzePapier = Color(hex: 0x865D20)

    // MARK: Brun du logo (cartes héros, curseur d'envoi, dock) : identique dans les deux thèmes

    static let espresso = Color(hex: 0x211A13)
    static let espressoProfond = Color(hex: 0x17120D)

    // MARK: États

    static let sauge = Color(clair: 0x4F6B4A, sombre: 0x9DBB97)
    static let ambre = Color(clair: 0x8A5A12, sombre: 0xE2B25C)
    static let rouille = Color(clair: 0x8A4B3A, sombre: 0xE0907E)
    static let vertControle = sauge

    static let ombre = Color(clair: 0x3A2819, sombre: 0x000000, opaciteClair: 0.08, opaciteSombre: 0.45)
    static let reflet = Color(clair: 0xFFFFFF, sombre: 0xFFFFFF, opaciteClair: 0.6, opaciteSombre: 0.03)

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
        LinearGradient(colors: [.orClair, .or, Color(hex: 0xE6C88E)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Or pour le texte : reflet plus lumineux au centre.
    static var texteOr: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xE6C88E), .orClair, .or, Color(hex: 0xD9B878)],
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
    static let rayon: CGFloat = 22
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
