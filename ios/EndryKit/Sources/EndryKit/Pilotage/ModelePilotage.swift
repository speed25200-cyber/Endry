import Foundation
import Observation

/// Pause / reprise de l'assistant du PC (v1.1 `/assistant/*`).
/// Avec un serveur v1.0 (route absente), la commande est simplement masquée.
@MainActor
@Observable
public final class ModelePilotage {
    public private(set) var etat: EtatAssistant?
    /// Faux si le serveur ne connaît pas `/assistant/etat` (v1.0).
    public private(set) var disponible = true
    public private(set) var enCours = false
    public var toast: Toast?

    @ObservationIgnored private let api: any EndryAPI
    /// Prévient l'écran Aujourd'hui (bandeau de pause, actions bloquées).
    @ObservationIgnored public var surChangement: (@MainActor (Bool) -> Void)?

    public init(api: any EndryAPI) {
        self.api = api
    }

    public var enPause: Bool { etat?.pause ?? false }

    public func charger() async {
        do {
            etat = try await api.etatAssistant()
            disponible = true
        } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
            disponible = false
        } catch {
            // Hors ligne : on garde le dernier état connu.
        }
    }

    /// Met l'assistant en pause ou le reprend. Renvoie vrai si la commande est passée.
    @discardableResult
    public func basculer() async -> Bool {
        guard !enCours else { return false }
        let cible = !enPause
        enCours = true
        defer { enCours = false }
        do {
            try await api.mettreEnPause(cible)
            etat = EtatAssistant(pause: cible, file: etat?.file ?? 0, derniereActivite: etat?.derniereActivite)
            surChangement?(cible)
            toast = Toast(cible ? "Assistant en pause : il ne prépare plus rien." : "Assistant repris.", style: .succes)
            return true
        } catch {
            toast = Toast(error.message, style: .erreur)
            return false
        }
    }
}
