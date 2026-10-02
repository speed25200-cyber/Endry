import Foundation
import Network

/// Surveille le réseau : au retour de la connexion, la file des saisies se vide.
@MainActor
final class SurveillanceReseau {
    var surRetour: (@MainActor () -> Void)?
    private(set) var disponible = true
    private let moniteur = NWPathMonitor()

    init() {
        moniteur.pathUpdateHandler = Self.gestionnaire { [weak self] ok in
            Task { @MainActor [weak self] in self?.changer(ok) }
        }
        moniteur.start(queue: DispatchQueue(label: "ch.endry.reseau"))
    }

    private func changer(_ ok: Bool) {
        let retour = ok && !disponible
        disponible = ok
        if retour { surRetour?() }
    }

    /// Fabriqué hors du MainActor : le moniteur appelle ce bloc sur sa propre file.
    nonisolated private static func gestionnaire(_ rappel: @escaping @Sendable (Bool) -> Void) -> @Sendable (NWPath) -> Void {
        { chemin in rappel(chemin.status == .satisfied) }
    }
}
