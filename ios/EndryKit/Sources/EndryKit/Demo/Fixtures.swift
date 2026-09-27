import Foundation

/// Fichiers JSON d'exemple (données fictives) pour le mode démo, les aperçus SwiftUI et les tests.
public enum Fixtures {
    public enum Nom: String, CaseIterable, Sendable {
        // Serveur v1.1 (mode démo)
        case accueil, decisions, chantiers, argent, session, appareils, saisies
        case chantiersDetails = "chantiers-details"
        case etatAssistant = "assistant-etat"
        case sessionVoix = "voix-session"
        case erreur401 = "erreur-401"
        case erreurLienInvalide = "erreur-lien-invalide"
        case erreurBexio = "erreur-bexio"
        // Serveur v1.0 (tests de contrat : réponses exactes, sans les champs v1.1)
        case accueilV10 = "accueil-v10"
        case decisionsV10 = "decisions-v10"
        case chantiersV10 = "chantiers-v10"
        case chantierV10 = "chantier-v10"
        case argentV10 = "argent-v10"
        case sessionV10 = "session-v10"
    }

    public static func donnees(_ nom: Nom) -> Data {
        let url = Bundle.module.url(forResource: nom.rawValue, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: nom.rawValue, withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else {
            assertionFailure("Fixture introuvable : \(nom.rawValue)")
            return Data("{}".utf8)
        }
        return data
    }

    public static func decoder<T: Decodable>(_ type: T.Type, _ nom: Nom) throws -> T {
        try JSONDecoder().decode(T.self, from: donnees(nom))
    }

    // Raccourcis pour les aperçus SwiftUI.
    public static var accueil: Accueil { (try? decoder(Accueil.self, .accueil))! }
    public static var chantiers: ReponseChantiers { (try? decoder(ReponseChantiers.self, .chantiers))! }
    public static var argent: Argent { (try? decoder(Argent.self, .argent))! }
    public static var cartes: [Carte] { accueil.decisions }

    public static var dossierDetaille: Dossier {
        let details = (try? decoder([String: Dossier].self, .chantiersDetails)) ?? [:]
        return details["18"] ?? chantiers.chantiers[0]
    }
}
