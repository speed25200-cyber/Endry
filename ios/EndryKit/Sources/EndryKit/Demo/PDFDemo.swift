import Foundation

/// Génère un petit PDF A4 d'une page (mode démo uniquement), sans dépendance à UIKit.
public enum PDFDemo {
    public static func document(titre: String, lignes: [String]) -> Data {
        var contenu = "BT\n/F2 20 Tf\n56 780 Td\n(\(echapper("ENDRY SA"))) Tj\n"
        contenu += "/F1 9 Tf\n0 -16 Td\n(\(echapper("Sanitaire - Chauffage - Ventilation - Bussy FR"))) Tj\n"
        contenu += "/F2 15 Tf\n0 -48 Td\n(\(echapper(titre))) Tj\n/F1 11 Tf\n"
        for ligne in lignes {
            contenu += "0 -20 Td\n(\(echapper(ligne))) Tj\n"
        }
        contenu += "/F1 8 Tf\n0 -48 Td\n(\(echapper("Document de démonstration - données fictives."))) Tj\nET\n"
        contenu += "0.906 0.776 0.545 RG 1.5 w 56 760 m 539 760 l S\n"

        let objets = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
        ]
        let flux = latin1(contenu)

        var pdf = Data("%PDF-1.4\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8)
        var positions: [Int] = []
        for (i, objet) in objets.enumerated() {
            positions.append(pdf.count)
            pdf.append(Data("\(i + 1) 0 obj\n\(objet)\nendobj\n".utf8))
        }
        positions.append(pdf.count)
        pdf.append(Data("6 0 obj\n<< /Length \(flux.count) >>\nstream\n".utf8))
        pdf.append(flux)
        pdf.append(Data("\nendstream\nendobj\n".utf8))

        let debutXref = pdf.count
        var xref = "xref\n0 \(positions.count + 1)\n0000000000 65535 f \n"
        for p in positions {
            xref += String(repeating: "0", count: max(0, 10 - String(p).count)) + "\(p) 00000 n \n"
        }
        xref += "trailer\n<< /Size \(positions.count + 1) /Root 1 0 R >>\nstartxref\n\(debutXref)\n%%EOF\n"
        pdf.append(Data(xref.utf8))
        return pdf
    }

    private static func echapper(_ s: String) -> String {
        let remplacements: [String: String] = ["’": "'", "—": "-", "–": "-", "·": "-", "…": "..."]
        var r = s
        for (a, b) in remplacements { r = r.replacingOccurrences(of: a, with: b) }
        return r.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    /// Encodage WinAnsi (≈ Latin-1) pour les polices PDF standard.
    private static func latin1(_ s: String) -> Data {
        var d = Data()
        for scalaire in s.unicodeScalars {
            d.append(scalaire.value < 256 ? UInt8(scalaire.value) : UInt8(ascii: "?"))
        }
        return d
    }
}
