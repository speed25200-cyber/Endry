import SwiftUI
import UIKit

/// Palette de la maison Endry SA, tirée du logo et du site :
/// brun du logo `#211A13`, crème dorée des lettres `#F9DBA3`, bronze du « Y » `#9F722A`, papier `#F6F5F2`.
/// Thème sombre (par défaut, « Galerie ») : fond brun, cartes papier crème. Thème clair : papier et encre brune.
/// Deux couleurs d'état : sauge (« fait ») et ambre (« attend ») ; la rouille est réservée aux gestes destructifs.
extension Color {
    // MARK: Fonds et surfaces

    /// Fond : brun du logo, ou papier du site.
    static let fond = Color(clair: 0xF6F5F2, sombre: 0x17110C)
    /// Surfaces posées sur le fond (panneaux, tuiles).
    static let surface = Color(clair: 0xFDFCFA, sombre: 0x211A13)
    /// Surface creusée (champs, pistes, pastilles).
    static let surfaceCreuse = Color(clair: 0xECE5D8, sombre: 0x2E241A)

    // MARK: Encres (contraste AA sur fond et surface)

    static let encre = Color(clair: 0x211A13, sombre: 0xF6F0E6)
    static let encreDouce = Color(clair: 0x74695A, sombre: 0xB2A38B)
    static let encrePale = Color(clair: 0x6F6A63, sombre: 0x9C9282)
    static let filet = Color(clair: 0x211A13, sombre: 0xF9DBA3, opaciteClair: 0.1, opaciteSombre: 0.12)
    /// Filet appuyé : frises, pistes de glissement.
    static let filetFort = Color(clair: 0x211A13, sombre: 0xF9DBA3, opaciteClair: 0.28, opaciteSombre: 0.3)

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
    static let bordureOr = Color(clair: 0x211A13, sombre: 0xF9DBA3, opaciteClair: 0.1, opaciteSombre: 0.12)

    // MARK: Maison Endry (maquette E)

    /// Étiquettes Cinzel (« À DÉCIDER », « FINANCES »).
    static let etiquette = Color(clair: 0x8A6223, sombre: 0xD2A764)
    /// Signal : trait du geste, repère « maintenant », barres d'avancement.
    static let signal = Color(clair: 0x9F722A, sombre: 0xF9DBA3)
    static let signalHalo = Color(clair: 0x9F722A, sombre: 0xF9DBA3, opaciteClair: 0.14, opaciteSombre: 0.16)
    /// Bouton principal : crème dorée sur brun (sombre), brun sur papier (clair).
    static let bouton = Color(clair: 0x211A13, sombre: 0xF9DBA3)
    static let boutonTexte = Color(clair: 0xF9DBA3, sombre: 0x211A13)
    /// Verre et tuiles : crème dorée à peine posée (sombre), blanc laiteux (clair).
    static let verreTeinte = Color(clair: 0xFFFFFF, sombre: 0xF9DBA3, opaciteClair: 0.6, opaciteSombre: 0.06)
    static let tuileTeinte = Color(clair: 0xFFFFFF, sombre: 0xF9DBA3, opaciteClair: 0.72, opaciteSombre: 0.045)
    /// Pastille de genre (« Offre », « E-mail »).
    static let puce = Color(clair: 0xF9DBA3, sombre: 0xF9DBA3, opaciteClair: 0.55, opaciteSombre: 0.12)
    /// Loupe de la barre d'onglets.
    static let lentille = Color(clair: 0x211A13, sombre: 0xF9DBA3, opaciteClair: 0.06, opaciteSombre: 0.1)
    /// Reflet du bord haut des tuiles et du verre.
    static let refletBord = Color(clair: 0xFFFFFF, sombre: 0xFFECC8, opaciteClair: 1, opaciteSombre: 0.22)

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

    static let sauge = Color(clair: 0x3D7046, sombre: 0x9CCB98)
    static let ambre = Color(clair: 0x8A5A12, sombre: 0xE2B25C)
    static let rouille = Color(clair: 0xA9462B, sombre: 0xE59474)
    static let vertControle = sauge

    static let ombre = Color(clair: 0x211A13, sombre: 0x000000, opaciteClair: 0.1, opaciteSombre: 0.5)
    static let reflet = Color(clair: 0xFFFFFF, sombre: 0xFFECC8, opaciteClair: 0.6, opaciteSombre: 0.05)

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
        // Maison Endry : crème dorée presque unie (plus de reflet brillant).
        LinearGradient(colors: [Color(hex: 0xFBE2B2), .or], startPoint: .top, endPoint: .bottom)
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
