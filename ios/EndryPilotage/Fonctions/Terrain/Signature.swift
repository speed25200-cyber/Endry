import PencilKit
import SwiftUI
import UIKit

/// Zone de signature au doigt ou à l'Apple Pencil (PencilKit, encre noire, sensible à la pression).
struct ZoneSignature: UIViewRepresentable {
    @Binding var dessin: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let toile = PKCanvasView()
        toile.drawingPolicy = .anyInput
        toile.tool = PKInkingTool(.pen, color: .black, width: 3.2)
        toile.backgroundColor = .clear
        toile.isOpaque = false
        toile.overrideUserInterfaceStyle = .light
        toile.isScrollEnabled = false
        toile.delegate = context.coordinator
        toile.drawing = dessin
        toile.accessibilityLabel = "Zone de signature"
        toile.accessibilityIdentifier = "zone-signature"
        return toile
    }

    func updateUIView(_ toile: PKCanvasView, context: Context) {
        if toile.drawing != dessin { toile.drawing = dessin }
    }

    func makeCoordinator() -> Coordinateur { Coordinateur(dessin: $dessin) }

    final class Coordinateur: NSObject, PKCanvasViewDelegate {
        var dessin: Binding<PKDrawing>
        init(dessin: Binding<PKDrawing>) { self.dessin = dessin }

        func canvasViewDrawingDidChange(_ toile: PKCanvasView) {
            dessin.wrappedValue = toile.drawing
        }
    }
}

extension PKDrawing {
    /// Signature exploitable : au moins un trait d'une certaine longueur.
    var estSignature: Bool {
        !strokes.isEmpty && (bounds.width > 40 || bounds.height > 30)
    }

    /// Image PNG de la signature, recadrée, encre noire sur fond transparent.
    func png(echelle: CGFloat = 3) -> Data? {
        guard estSignature else { return nil }
        let cadre = bounds.insetBy(dx: -12, dy: -12)
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = self.image(from: cadre, scale: echelle)
        }
        return image?.pngData()
    }
}
