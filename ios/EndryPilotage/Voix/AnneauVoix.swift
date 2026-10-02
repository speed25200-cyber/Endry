import EndryKit
import SwiftUI

/// Relais vocal « Maison Endry » (maquette E-Voix) : autour d'un cercle fin, une couronne de rayons crème qui
/// s'allongent avec la voix (la vôtre à l'écoute, celle d'Endry quand il parle) ; au centre, le temps écoulé
/// et l'état. Les niveaux sont lissés par `LisseurOrbe` : la couronne réagit sans trembler.
struct AnneauVoix: View {
    var assistant: AssistantVocal?
    /// Début de la phase en cours (le chronomètre repart à chaque phase).
    var debut: Date
    @State private var lisseur = LisseurOrbe()
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    private static let rayons = 96

    var body: some View {
        GeometryReader { geo in
            let cote = min(geo.size.width, geo.size.height)
            ZStack {
                if Configuration.testsUI {
                    // Tests d'interface : couronne fixe, sans horloge ni lecture des niveaux audio.
                    couronne(cote: cote, temps: 1.3, niveau: 0.45)
                    centre(cote: cote, ecoule: 3)
                } else {
                    // Seule la couronne suit l'image (60 i/s) ; le chronomètre ne change qu'une fois par seconde.
                    TimelineView(.animation(minimumInterval: 1 / 60, paused: reduireAnimations)) { contexte in
                        let v = lisseur.avancer(contexte.date, assistant: assistant, lent: reduireAnimations)
                        let niveau = Double(max(v.micro, v.voix, v.reflexion * 0.35, 0.08))
                        couronne(cote: cote, temps: contexte.date.timeIntervalSinceReferenceDate, niveau: niveau)
                    }
                    TimelineView(.periodic(from: debut, by: 1)) { contexte in
                        centre(cote: cote, ecoule: max(contexte.date.timeIntervalSince(debut), 0))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Paliers d'intensité : les rayons sont regroupés en quelques tracés (un par palier) au lieu de 96.
    private static let paliers = 6

    /// La couronne : rayons répartis sur le cercle, longueur = fond lent + énergie de la voix.
    private func couronne(cote: CGFloat, temps: Double, niveau: Double) -> some View {
        Canvas { ctx, taille in
            let c = CGPoint(x: taille.width / 2, y: taille.height / 2)
            let r0 = cote * 0.37
            let longueurMax = cote * 0.14
            var traces = Array(repeating: Path(), count: Self.paliers)
            for i in 0..<Self.rayons {
                let a = Double(i) / Double(Self.rayons) * 2 * .pi
                // Deux ondes qui tournent en sens contraire : la couronne respire de façon organique.
                let onde = 0.5 + 0.3 * sin(a * 3 + temps * 1.7) + 0.2 * sin(a * 7 - temps * 2.3)
                let bruit = 0.5 + 0.5 * sin(Double(i) * 12.9898 + temps * 4.1)
                let e = min(max(0.12 + niveau * (0.55 * onde + 0.45 * bruit), 0.06), 1)
                let l = 4 + CGFloat(e) * longueurMax
                let (cosA, sinA) = (CGFloat(cos(a)), CGFloat(sin(a)))
                let palier = min(Int(e * Double(Self.paliers)), Self.paliers - 1)
                traces[palier].move(to: CGPoint(x: c.x + cosA * r0, y: c.y + sinA * r0))
                traces[palier].addLine(to: CGPoint(x: c.x + cosA * (r0 + l), y: c.y + sinA * (r0 + l)))
            }
            let style = StrokeStyle(lineWidth: 1.6, lineCap: .round)
            for (palier, trace) in traces.enumerated() where !trace.isEmpty {
                let e = (Double(palier) + 0.5) / Double(Self.paliers)
                ctx.stroke(trace, with: .color(Color.signal.opacity(0.25 + 0.75 * e)), style: style)
            }
            let cercle = Path(ellipseIn: CGRect(x: c.x - r0 + 6, y: c.y - r0 + 6, width: (r0 - 6) * 2, height: (r0 - 6) * 2))
            ctx.stroke(cercle, with: .color(Color.filetFort), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private func centre(cote: CGFloat, ecoule: TimeInterval) -> some View {
        VStack(spacing: 6) {
            Text(Self.chrono(ecoule))
                .font(Police.serif(cote * 0.2, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(Color.encre)
            Text(Self.libelle(assistant?.phase ?? .preparation))
                .font(Police.mono(12))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Color.encreDouce)
                .lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    static func chrono(_ secondes: TimeInterval) -> String {
        let s = Int(secondes)
        return "\(s / 60):" + (s % 60 < 10 ? "0" : "") + "\(s % 60)"
    }

    static func libelle(_ phase: PhaseVoix) -> String {
        switch phase {
        case .preparation: "Un instant"
        case .ecoute: "Écoute"
        case .reflexion: "Au bureau"
        case .parole: "Réponse"
        case .erreur: "Toucher pour reprendre"
        }
    }
}
