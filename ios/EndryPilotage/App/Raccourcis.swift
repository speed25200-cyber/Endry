import AppIntents
import Observation

/// Demandes venues de Siri, de Spotlight ou du bouton Action, en attente que l'app soit déverrouillée.
@MainActor
@Observable
final class DemandesRaccourcis {
    static let partage = DemandesRaccourcis()
    var assistantDemande = false
}

/// « Dis Siri, parler à Endry » : ouvre l'app sur l'assistant vocal, prêt à écouter.
/// L'assistant ne s'ouvre qu'après Face ID : rien n'est lu à voix haute sur un iPhone verrouillé.
struct ParlerAEndry: AppIntent {
    static let title: LocalizedStringResource = "Parler à Endry"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DemandesRaccourcis.partage.assistantDemande = true
        return .result()
    }
}

struct RaccourcisEndry: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ParlerAEndry(),
            phrases: [
                "Parler à \(.applicationName)",
                "Demander à \(.applicationName)",
                "Ouvrir l’assistant \(.applicationName)",
            ],
            shortTitle: "Parler à Endry",
            systemImageName: "waveform"
        )
    }
}
