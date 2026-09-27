import SwiftUI
import UIKit

/// Palette « banque privée » : noir profond, verre, or champagne. L'app est volontairement sombre ;
/// les variantes claires ne servent qu'aux captures forcées (`-clair`).
extension Color {
    /// Fond : noir chaud, jamais #000 pur (évite l'effet « trou » sur OLED).
    static let fond = Color(clair: 0xF6F3EE, sombre: 0x08080A)
    /// Surfaces des cartes (posées sur le fond, légèrement relevées).
    static let surface = Color(clair: 0xFFFFFF, sombre: 0x131316)
    /// Surface relevée (tuiles, champs, pistes).
    static let surfaceCreuse = Color(clair: 0xEEEAE3, sombre: 0x1C1C21)
    /// Texte principal : ivoire.
    static let encre = Color(clair: 0x111114, sombre: 0xF4EFE6)
    /// Texte secondaire (contraste AA sur fond et surface).
    static let encreDouce = Color(clair: 0x55524D, sombre: 0xA9A39A)
    /// Texte tertiaire, légendes.
    static let encrePale = Color(clair: 0x7B766F, sombre: 0x75706A)
    /// Filets et séparateurs.
    static let filet = Color(clair: 0xE2DDD4, sombre: 0x26262C)

    /// Matière sombre des cartes héros.
    static let espresso = Color(hex: 0x111114)
    static let espressoProfond = Color(hex: 0x050506)
    /// Or champagne et ses nuances.
    static let or = Color(hex: 0xD9B872)
    static let orClair = Color(hex: 0xF3E2B8)
    static let bronze = Color(clair: 0x8A6420, sombre: 0xD9B872)
    static let bronzeMoyen = Color(hex: 0xA8803A)
    static let vertControle = Color(clair: 0x1F7A4F, sombre: 0x5ED39A)
    static let rouille = Color(clair: 0xB23A22, sombre: 0xFF7A63)
    static let ambre = Color(clair: 0x8A5A00, sombre: 0xF4BE63)

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
            let hex = trait.userInterfaceStyle == .light ? clair : sombre
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
    /// Or brossé : accents, bouton micro, montants héros.
    static var degradeOr: LinearGradient {
        LinearGradient(colors: [.orClair, .or, .bronzeMoyen], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Or pour le texte : reflet plus lumineux au centre.
    static var texteOr: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xC99E4E), .orClair, Color(hex: 0xE3C585), Color(hex: 0xB88A3E)],
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
    /// Marge latérale des écrans.
    static let bord: CGFloat = 20
    /// Rayon des cartes.
    static let rayon: CGFloat = 30
    static let rayonPetit: CGFloat = 18
}
