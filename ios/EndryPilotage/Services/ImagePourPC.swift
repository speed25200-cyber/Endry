import Foundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Photos envoyées au PC : toujours en JPEG (l'assistant ne lit pas le HEIC), qualité 0,85,
/// grand côté 2560 px au plus, orientation appliquée, métadonnées de localisation retirées.
/// Tout se calcule hors du fil principal (`horsEcran`) : l'écran ne gèle pas pendant la conversion.
enum ImagePourPC {
    static let grandCoteMax = 2_560
    static let qualite = 0.85

    static func jpeg(_ donnees: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(donnees as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: grandCoteMax,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let sortie = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(sortie as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: qualite] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return sortie as Data
    }

    /// Conversion JPEG hors du fil principal.
    static func jpegHorsEcran(_ donnees: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) { jpeg(donnees) }.value
    }

    /// Photo de l'appareil (caméra, scan) en JPEG pour le PC, hors du fil principal.
    static func jpegHorsEcran(_ image: UIImage) async -> Data? {
        await Task.detached(priority: .userInitiated) { image.jpegData(compressionQuality: 1).flatMap(jpeg) }.value
    }

    /// Pages scannées réunies en un seul PDF A4, hors du fil principal.
    static func pdfHorsEcran(_ pages: [UIImage]) async -> Data {
        await Task.detached(priority: .userInitiated) {
            let limites = CGRect(x: 0, y: 0, width: 595, height: 842)
            return UIGraphicsPDFRenderer(bounds: limites, format: UIGraphicsPDFRendererFormat()).pdfData { contexte in
                for page in pages {
                    contexte.beginPage()
                    let echelle = min(limites.width / page.size.width, limites.height / page.size.height)
                    let taille = CGSize(width: page.size.width * echelle, height: page.size.height * echelle)
                    page.draw(in: CGRect(x: (limites.width - taille.width) / 2, y: (limites.height - taille.height) / 2,
                                         width: taille.width, height: taille.height))
                }
            }
        }.value
    }

    /// Vignette (grand côté `cote` px), orientation appliquée.
    static func vignette(_ donnees: Data, cote: Int = 260) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(donnees as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: cote,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Vignettes des photos jointes : réduites une fois hors du fil principal et gardées en mémoire,
/// jamais la photo pleine résolution décodée à chaque affichage.
@MainActor
enum CacheVignettes {
    private static var cache: [String: UIImage] = [:]

    static func image(_ donnees: Data, cle: String) async -> UIImage? {
        if let deja = cache[cle] { return deja }
        let image = await Task.detached(priority: .userInitiated) { ImagePourPC.vignette(donnees) }.value
        if cache.count > 80 { cache.removeAll() }
        cache[cle] = image
        return image
    }
}

/// Vignette d'une photo jointe (fond creux pendant la réduction).
struct VignettePhoto: View {
    var donnees: Data
    /// Identifiant stable de la photo (nom de fichier, identifiant de la pièce).
    var cle: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.surfaceCreuse
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .task(id: cle) { image = await CacheVignettes.image(donnees, cle: cle) }
    }
}
