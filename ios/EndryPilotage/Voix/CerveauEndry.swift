import EndryKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Ce que le cerveau veut dire, et les cartes à faire surgir pendant qu'il parle.
struct ReponseCerveau: Sendable {
    var texte: String
    var effets: [ExecuteurOutils.Effet]
}

/// Cerveau de la conversation vocale quand le PC ne fournit pas de session temps réel.
@MainActor
protocol CerveauVocal: AnyObject, Sendable {
    /// `nil` : le cerveau n'a pas su répondre, le moteur retombe sur les réponses locales.
    func repondre(_ question: String) async -> ReponseCerveau?
}

extension CerveauVocal {
    /// Réponse dans le délai, sinon `nil` : le moteur répond localement plutôt que de laisser le patron attendre.
    func repondre(_ question: String, delai: Duration) async -> ReponseCerveau? {
        await withTaskGroup(of: ReponseCerveau?.self) { groupe in
            groupe.addTask { await self.repondre(question) }
            groupe.addTask {
                try? await Task.sleep(for: delai)
                return nil
            }
            let premiere = await groupe.next() ?? nil
            groupe.cancelAll()
            return premiere
        }
    }
}

enum FabriqueCerveau {
    /// Modèle de langage d'Apple, sur l'iPhone (iOS 26, Apple Intelligence activé) ; sinon rien.
    @MainActor
    static func creer(executeur: ExecuteurOutils?,
                      transmettre: @escaping @MainActor @Sendable (String) async -> ModeleSaisie.ResultatDemande) -> (any CerveauVocal)? {
        // Tests d'interface : réponses locales, déterministes.
        guard !Configuration.testsUI else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let executeur, SystemLanguageModel.default.isAvailable {
            return CerveauAppleIntelligence(executeur: executeur, transmettre: transmettre)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)

/// Conversation avec le modèle d'Apple, entièrement sur l'iPhone : aucune clé, aucune donnée envoyée ailleurs.
/// Le modèle lit les données par les mêmes outils que le moteur temps réel ; il ne peut rien envoyer ni valider.
@available(iOS 26.0, *)
@MainActor
final class CerveauAppleIntelligence: CerveauVocal {
    private let executeur: ExecuteurOutils
    private let transmettre: @MainActor @Sendable (String) async -> ModeleSaisie.ResultatDemande
    private let effets = CollecteurEffets()
    private var session: LanguageModelSession

    init(executeur: ExecuteurOutils, transmettre: @escaping @MainActor @Sendable (String) async -> ModeleSaisie.ResultatDemande) {
        self.executeur = executeur
        self.transmettre = transmettre
        session = Self.nouvelleSession(executeur: executeur, transmettre: transmettre, effets: effets)
        session.prewarm()
    }

    func repondre(_ question: String) async -> ReponseCerveau? {
        effets.vider()
        do {
            return try await tour(question)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Conversation trop longue : on repart d'une page blanche et on repose la question.
            session = Self.nouvelleSession(executeur: executeur, transmettre: transmettre, effets: effets)
            effets.vider()
            return try? await tour(question)
        } catch {
            return nil
        }
    }

    private func tour(_ question: String) async throws -> ReponseCerveau? {
        let reponse = try await session.respond(to: question)
        let texte = TexteParle.nettoyer(reponse.content)
        guard !texte.isEmpty else { return nil }
        return ReponseCerveau(texte: texte, effets: effets.tous())
    }

    private static func nouvelleSession(executeur: ExecuteurOutils,
                                        transmettre: @escaping @MainActor @Sendable (String) async -> ModeleSaisie.ResultatDemande,
                                        effets: CollecteurEffets) -> LanguageModelSession {
        let outils: [any Tool] = [
            OutilLecture(name: "accueil", description: ConsignesCerveau.accueil, executeur: executeur, effets: effets),
            OutilLecture(name: "decisions", description: ConsignesCerveau.decisions, executeur: executeur, effets: effets),
            OutilLecture(name: "chantiers", description: ConsignesCerveau.chantiers, executeur: executeur, effets: effets),
            OutilLecture(name: "argent", description: ConsignesCerveau.argent, executeur: executeur, effets: effets),
            OutilLecture(name: "bureau", description: ConsignesCerveau.bureau, executeur: executeur, effets: effets),
            OutilDemanderClaude(executeur: executeur, effets: effets),
            OutilChantier(executeur: executeur, effets: effets),
            OutilProposerDecision(executeur: executeur, effets: effets),
            OutilSaisie(transmettre: transmettre),
        ]
        return LanguageModelSession(tools: outils, instructions: ConsignesCerveau.texte())
    }
}

/// Cartes demandées par les outils pendant un tour (les outils tournent hors de l'acteur principal).
final class CollecteurEffets: @unchecked Sendable {
    private let verrou = NSLock()
    private var effets: [ExecuteurOutils.Effet] = []

    func ajouter(_ effet: ExecuteurOutils.Effet) {
        guard effet != .aucun else { return }
        verrou.withLock { if !effets.contains(effet) { effets.append(effet) } }
    }

    func tous() -> [ExecuteurOutils.Effet] { verrou.withLock { effets } }
    func vider() { verrou.withLock { effets.removeAll() } }
}

/// Outil de lecture sans paramètre utile (accueil, décisions, chantiers, argent).
@available(iOS 26.0, *)
struct OutilLecture: Tool {
    let name: String
    let description: String
    let executeur: ExecuteurOutils
    let effets: CollecteurEffets

    @Generable
    struct Arguments {
        @Guide(description: "Ce que le patron cherche, en quelques mots")
        var sujet: String
    }

    func call(arguments: Arguments) async throws -> String {
        let r = await executeur.executer(nom: name, arguments: "{}")
        effets.ajouter(r.effet)
        // Le modèle embarqué a une petite mémoire : on garde l'essentiel.
        return r.sortie.count > 3_000 ? String(r.sortie.prefix(3_000)) + "…" : r.sortie
    }
}

@available(iOS 26.0, *)
struct OutilChantier: Tool {
    let name = "chantier"
    let description = ConsignesCerveau.chantier
    let executeur: ExecuteurOutils
    let effets: CollecteurEffets

    @Generable
    struct Arguments {
        @Guide(description: "Identifiant du chantier, tel que donné par l’outil chantiers (champ id)")
        var id: String
    }

    func call(arguments: Arguments) async throws -> String {
        let r = await executeur.executer(nom: name, arguments: Self.json(["id": arguments.id]))
        effets.ajouter(r.effet)
        return r.sortie
    }

    static func json(_ objet: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: objet) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Affiche la carte d'une décision : le patron valide lui-même, d'un geste à l'écran.
@available(iOS 26.0, *)
struct OutilProposerDecision: Tool {
    let name = "proposer_decision"
    let description = ConsignesCerveau.proposerDecision
    let executeur: ExecuteurOutils
    let effets: CollecteurEffets

    @Generable
    struct Arguments {
        @Guide(description: "Référence de la décision, par exemple V-2026-031")
        var reference: String
    }

    func call(arguments: Arguments) async throws -> String {
        let r = await executeur.executer(nom: name, arguments: OutilChantier.json(["reference": arguments.reference]))
        effets.ajouter(r.effet)
        return r.sortie
    }
}

/// Question pour Claude, l'assistant du bureau sur le PC : la réponse arrive plus tard, affichée et dite.
@available(iOS 26.0, *)
struct OutilDemanderClaude: Tool {
    let name = "demander_claude"
    let description = ConsignesCerveau.demanderClaude
    let executeur: ExecuteurOutils
    let effets: CollecteurEffets

    @Generable
    struct Arguments {
        @Guide(description: "La question du patron, complète, telle qu’il l’a posée")
        var question: String
        @Guide(description: "Agent de Claude concerné : secretariat, comptabilite, chantiers, offres, achats ; vide si aucun n’est évident")
        var agent: String
    }

    func call(arguments: Arguments) async throws -> String {
        let r = await executeur.executer(nom: name, arguments: OutilChantier.json(["question": arguments.question, "agent": arguments.agent]))
        effets.ajouter(r.effet)
        return r.sortie
    }
}

/// Demande de travail pour l'assistant du bureau : passe par la file de saisie (gardée hors ligne).
@available(iOS 26.0, *)
struct OutilSaisie: Tool {
    let name = "saisie"
    let description = ConsignesCerveau.saisie
    let transmettre: @MainActor @Sendable (String) async -> ModeleSaisie.ResultatDemande

    @Generable
    struct Arguments {
        @Guide(description: "La demande du patron, complète, à l’infinitif ou telle qu’il l’a dite")
        var texte: String
    }

    func call(arguments: Arguments) async throws -> String {
        switch await transmettre(arguments.texte) {
        case .transmise: "Transmis à l’assistant du bureau : la proposition arrivera dans les décisions. Rien n’est parti chez un tiers."
        case .gardee: "Pas de réseau : la demande est gardée sur l’iPhone et partira toute seule."
        case .refusee(let raison): "Demande non transmise : \(raison)"
        }
    }
}

#endif
