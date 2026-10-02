import CoreGraphics
import Foundation
import Vision

/// Lecture des pages scannées, sur l'iPhone : iOS 26 lit la structure du document (tableaux d'articles) ;
/// avant, la reconnaissance de texte reconstruit les lignes du tableau à partir de leur position.
enum LectureDocument {
    static func lignes(_ pages: [CGImage]) async -> [String] {
        var toutes: [String] = []
        for page in pages {
            if #available(iOS 26.0, *), let structure = try? await lignesStructurees(page), !structure.isEmpty {
                toutes += structure
            } else {
                toutes += await Task.detached(priority: .userInitiated) { (try? lignesParPosition(page)) ?? [] }.value
            }
        }
        return toutes
    }

    /// iOS 26 : texte ligne à ligne, puis chaque rangée de tableau en une seule ligne (référence, désignation, quantité).
    @available(iOS 26.0, *)
    private static func lignesStructurees(_ image: CGImage) async throws -> [String] {
        let requete = RecognizeDocumentsRequest()
        let observations = try await requete.perform(on: image)
        guard let document = observations.first?.document else { return [] }
        var lignes = document.text.lines.map(\.transcript)
        for tableau in document.tables {
            for rangee in tableau.rows {
                let cellules = rangee.map { $0.content.text.transcript.replacingOccurrences(of: "\n", with: " ") }
                let ligne = cellules.filter { !$0.isEmpty }.joined(separator: " ")
                if !ligne.isEmpty { lignes.append(ligne) }
            }
        }
        return lignes
    }

    /// Reconnaissance de texte précise (français, allemand, italien), lignes regroupées par hauteur.
    private static func lignesParPosition(_ image: CGImage) throws -> [String] {
        let requete = VNRecognizeTextRequest()
        requete.recognitionLevel = .accurate
        requete.usesLanguageCorrection = true
        requete.recognitionLanguages = ["fr-FR", "de-DE", "it-IT"]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([requete])
        let morceaux = (requete.results ?? []).compactMap { o -> (CGRect, String)? in
            guard let texte = o.topCandidates(1).first?.string else { return nil }
            return (o.boundingBox, texte)
        }
        // Origine en bas à gauche : du haut de la page vers le bas.
        var rangees: [[(CGRect, String)]] = []
        for m in morceaux.sorted(by: { $0.0.midY > $1.0.midY }) {
            if let reference = rangees.last?.first, abs(reference.0.midY - m.0.midY) < max(reference.0.height, m.0.height) * 0.6 {
                rangees[rangees.count - 1].append(m)
            } else {
                rangees.append([m])
            }
        }
        return rangees.map { $0.sorted { $0.0.minX < $1.0.minX }.map(\.1).joined(separator: " ") }
    }
}
