import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Photos envoyées au PC : toujours en JPEG (l'assistant ne lit pas le HEIC), qualité 0,85,
/// grand côté 2560 px au plus, orientation appliquée, métadonnées de localisation retirées.
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
}
