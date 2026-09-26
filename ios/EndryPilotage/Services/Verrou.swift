import Foundation
import LocalAuthentication
import Observation

/// Verrouillage Face ID / Touch ID / code de l'appareil à l'ouverture (réglable).
@MainActor
@Observable
final class Verrou {
    private static let cleActif = "verrou-biometrique"

    var actif: Bool {
        didSet { UserDefaults.standard.set(actif, forKey: Self.cleActif) }
    }

    private(set) var deverrouille = false
    private(set) var enCours = false
    private(set) var erreur: String?

    init() {
        actif = UserDefaults.standard.object(forKey: Self.cleActif) as? Bool ?? true
        deverrouille = !actif
    }

    var nomMethode: String {
        let contexte = LAContext()
        _ = contexte.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch contexte.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "le code de l’iPhone"
        }
    }

    var doitAfficherEcran: Bool { actif && !deverrouille }

    /// Le lien d'accès vient d'être collé (ou la démo lancée) : inutile de redemander Face ID.
    func marquerDeverrouille() {
        deverrouille = true
        erreur = nil
    }

    func verrouiller() {
        guard actif else { return }
        deverrouille = false
    }

    func deverrouiller() async {
        guard actif, !deverrouille, !enCours else { return }
        enCours = true
        defer { enCours = false }
        let contexte = LAContext()
        contexte.localizedCancelTitle = "Annuler"
        var erreurPolitique: NSError?
        guard contexte.canEvaluatePolicy(.deviceOwnerAuthentication, error: &erreurPolitique) else {
            // Aucun code ni biométrie configurés : on ne bloque pas l'accès.
            deverrouille = true
            return
        }
        do {
            let ok = try await contexte.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Déverrouiller Endry Pilotage")
            deverrouille = ok
            erreur = nil
        } catch {
            erreur = "Déverrouillage annulé."
        }
    }
}
