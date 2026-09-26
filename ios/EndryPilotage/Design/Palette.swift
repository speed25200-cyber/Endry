import SwiftUI
import UIKit

/// Palette Endry : cabinet d'artisan suisse de prestige. Clair et sombre automatiques.
extension Color {
    /// Fond crème / nuit chaude.
    static let fond = Color(clair: 0xF4EEE3, sombre: 0x120E0A)
    /// Surfaces des cartes.
    static let surface = Color(clair: 0xFFFCF6, sombre: 0x1B1611)
    /// Surface légèrement enfoncée (champs, pistes).
    static let surfaceCreuse = Color(clair: 0xEDE5D6, sombre: 0x241D16)
    /// Texte principal.
    static let encre = Color(clair: 0x1B1510, sombre: 0xF5EDE0)
    /// Texte secondaire (contraste AA sur fond et surface).
    static let encreDouce = Color(clair: 0x5E5347, sombre: 0xB9AC9A)
    /// Texte tertiaire, légendes.
    static let encrePale = Color(clair: 0x7A6E60, sombre: 0x94877A)
    /// Filets et séparateurs.
    static let filet = Color(clair: 0xE3D8C6, sombre: 0x2E261E)

    static let espresso = Color(hex: 0x241C15)
    static let espressoProfond = Color(hex: 0x140F0B)
    static let or = Color(hex: 0xE7C68B)
    static let orClair = Color(hex: 0xF3DCAE)
    /// Bronze : accent lisible sur fond clair ; devient or en sombre.
    static let bronze = Color(clair: 0x86591A, sombre: 0xE7C68B)
    static let bronzeMoyen = Color(hex: 0xB8873C)
    static let vertControle = Color(clair: 0x2B6649, sombre: 0x6FBF93)
    static let rouille = Color(clair: 0x9E3720, sombre: 0xE58A6F)
    static let ambre = Color(clair: 0x8A5A00, sombre: 0xF0B85A)

    init(hex: UInt32, opacite: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacite
        )
    }

    init(clair: UInt32, sombre: UInt32) {
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? sombre : clair
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension ShapeStyle where Self == LinearGradient {
    /// Dégradé or des accents (bouton micro, montants héros).
    static var degradeOr: LinearGradient {
        LinearGradient(colors: [.orClair, .or, .bronzeMoyen], startPoint: .topLeading, endPoint: .bottomTrailing)
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
    /// Marge latérale des écrans.
    static let bord: CGFloat = 20
    /// Rayon des cartes.
    static let rayon: CGFloat = 28
    static let rayonPetit: CGFloat = 16
}
