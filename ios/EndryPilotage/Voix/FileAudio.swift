import AVFoundation
import Foundation

/// File unique, hors du fil principal, pour tout ce qui touche au son de l'iPhone : session audio, démarrage et
/// arrêt des moteurs. Ces appels bloquent (souvent 100 à 500 ms, parfois plus) ; faits sur le fil principal, ils
/// gelaient l'écran à l'ouverture et à la fermeture de l'assistant vocal. Une seule file, dans l'ordre : l'arrêt
/// d'une conversation est toujours terminé avant que la suivante ne démarre.
enum FileAudio {
    private static let file = DispatchQueue(label: "ch.endry.audio", qos: .userInitiated)

    /// Exécute `travail` sur la file audio et en attend le résultat (l'écran reste fluide pendant ce temps).
    static func executer<T: Sendable>(_ travail: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { suite in
            file.async {
                do {
                    suite.resume(returning: try travail())
                } catch {
                    suite.resume(throwing: error)
                }
            }
        }
    }

    /// Lance `travail` sur la file audio sans l'attendre (arrêts, désactivation de la session).
    static func lancer(_ travail: @escaping @Sendable () -> Void) {
        file.async(execute: travail)
    }

    /// Rend le son aux autres apps (musique, appel), sans bloquer l'écran.
    static func desactiverSession() {
        lancer { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}

/// Résultat de `operation`, ou `nil` si elle n'a pas abouti dans le délai : l'assistant ne reste jamais bloqué
/// sur « Un instant ». L'opération n'est pas annulée (un modèle qui se télécharge continue pour la fois suivante).
func dansLeDelai<T: Sendable>(_ delai: Duration, _ operation: @escaping @Sendable () async -> T?) async -> T? {
    let unique = ReponseUnique()
    return await withCheckedContinuation { (suite: CheckedContinuation<T?, Never>) in
        Task {
            let resultat = await operation()
            _ = unique.donner(resultat, a: suite)
        }
        Task {
            try? await Task.sleep(for: delai)
            _ = unique.donner(nil, a: suite)
        }
    }
}
