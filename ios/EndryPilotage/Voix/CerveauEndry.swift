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
    /// Réponse qui s'écrit (texte cumulé) : le moteur la dit phrase par phrase, sans attendre la fin.
    func repondreEnFlux(_ question: String) -> AsyncThrowingStream<String, Error>
    /// Cartes demandées par les outils pendant le tour en cours.
    func effetsEnCours() -> [ExecuteurOutils.Effet]
    /// Un outil lit des données en ce moment (le moteur peut dire « Je regarde » si ça dure).
    var outilEnCours: Bool { get }
    /// Échange traité sans le modèle (réponse instantanée, réponse du bureau) : il le saura au tour suivant.
    func retenir(question: String, reponse: String)
    /// Nouvelle conversation, page blanche.
    func oublier()
    /// Charge le modèle en mémoire avant la première question.
    func prechauffer()
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
    static func creer(executeur: ExecuteurOutils?) -> (any CerveauVocal)? {
        // Tests d'interface : réponses locales, déterministes.
        guard !Configuration.testsUI else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let executeur, SystemLanguageModel.default.isAvailable {
            return CerveauAppleIntelligence(executeur: executeur)
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
    private let effets = CollecteurEffets()
    private var session: LanguageModelSession
    /// Derniers échanges (pour reprendre le fil dans une nouvelle session).
    private var historique: [(question: String, reponse: String)] = []
    /// Échanges que la session n'a pas vus (réponses instantanées, bureau) : ajoutés à la question suivante.
    private var aRappeler: [(question: String, reponse: String)] = []
    private var derniereActivite = Date()

    /// Réponses courtes et posées pour la voix.
    private static let options = GenerationOptions(temperature: 0.4, maximumResponseTokens: 320)

    init(executeur: ExecuteurOutils) {
        self.executeur = executeur
        session = Self.nouvelleSession(executeur: executeur, effets: effets, recap: nil)
        session.prewarm()
    }

    var outilEnCours: Bool { effets.outilEnCours }

    func effetsEnCours() -> [ExecuteurOutils.Effet] { effets.tous() }

    func prechauffer() {
        // Après 30 min de silence, on repart d'une page blanche (comme la conversation avec le bureau).
        if Date().timeIntervalSince(derniereActivite) > 30 * 60 { oublier() }
        session.prewarm()
    }

    func oublier() {
        historique.removeAll()
        aRappeler.removeAll()
        session = Self.nouvelleSession(executeur: executeur, effets: effets, recap: nil)
    }

    func retenir(question: String, reponse: String) {
        let r = TexteParle.nettoyer(reponse)
        guard !question.isEmpty, !r.isEmpty else { return }
        aRappeler.append((question, r))
        if aRappeler.count > 3 { aRappeler.removeFirst() }
        garder(question, r)
    }

    func repondre(_ question: String) async -> ReponseCerveau? {
        effets.vider()
        derniereActivite = Date()
        let invite = invite(question)
        do {
            return try await tour(invite, question: question)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Conversation trop longue : nouvelle session qui reprend le fil, et la question est reposée.
            session = Self.nouvelleSession(executeur: executeur, effets: effets, recap: recap)
            effets.vider()
            return try? await tour(invite, question: question)
        } catch {
            return nil
        }
    }

    func repondreEnFlux(_ question: String) -> AsyncThrowingStream<String, Error> {
        effets.vider()
        derniereActivite = Date()
        let invite = invite(question)
        return AsyncThrowingStream { continuation in
            let tache = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                do {
                    let final = try await self.flux(invite, continuation)
                    self.garder(question, final)
                    continuation.finish()
                } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                    self.session = Self.nouvelleSession(executeur: self.executeur, effets: self.effets, recap: self.recap)
                    do {
                        let final = try await self.flux(invite, continuation)
                        self.garder(question, final)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in tache.cancel() }
        }
    }

    private func flux(_ invite: String, _ continuation: AsyncThrowingStream<String, Error>.Continuation) async throws -> String {
        var dernier = ""
        for try await partiel in session.streamResponse(to: invite, options: Self.options) {
            try Task.checkCancellation()
            dernier = partiel.content
            continuation.yield(dernier)
        }
        return dernier
    }

    private func tour(_ invite: String, question: String) async throws -> ReponseCerveau? {
        let reponse = try await session.respond(to: invite, options: Self.options)
        let texte = TexteParle.nettoyer(reponse.content)
        guard !texte.isEmpty else { return nil }
        garder(question, texte)
        return ReponseCerveau(texte: texte, effets: effets.tous())
    }

    /// La question, précédée des échanges que la session n'a pas vus.
    private func invite(_ question: String) -> String {
        guard !aRappeler.isEmpty else { return question }
        let rappel = aRappeler.map { "Q : \($0.question)\nR : \($0.reponse)" }.joined(separator: "\n")
        aRappeler.removeAll()
        return "(Échanges juste avant, déjà traités :\n\(rappel))\n\n\(question)"
    }

    private func garder(_ question: String, _ reponse: String) {
        let r = TexteParle.nettoyer(reponse)
        guard !r.isEmpty else { return }
        historique.append((question, r))
        if historique.count > 6 { historique.removeFirst(historique.count - 6) }
    }

    private var recap: String? {
        guard !historique.isEmpty else { return nil }
        return historique.suffix(4).map { "Q : \($0.question)\nR : \($0.reponse)" }.joined(separator: "\n")
    }

    private static func nouvelleSession(executeur: ExecuteurOutils, effets: CollecteurEffets, recap: String?) -> LanguageModelSession {
        let outils: [any Tool] = [
            OutilLecture(name: "accueil", description: ConsignesCerveau.accueil, executeur: executeur, effets: effets),
            OutilLecture(name: "decisions", description: ConsignesCerveau.decisions, executeur: executeur, effets: effets),
            OutilLecture(name: "chantiers", description: ConsignesCerveau.chantiers, executeur: executeur, effets: effets),
            OutilLecture(name: "argent", description: ConsignesCerveau.argent, executeur: executeur, effets: effets),
            OutilLecture(name: "bureau", description: ConsignesCerveau.bureau, executeur: executeur, effets: effets),
            OutilDemanderClaude(executeur: executeur, effets: effets),
            OutilChantier(executeur: executeur, effets: effets),
            OutilProposerDecision(executeur: executeur, effets: effets),
            OutilSaisie(executeur: executeur, effets: effets),
            OutilOuvrir(executeur: executeur, effets: effets),
            OutilLecture(name: "briefing", description: ConsignesCerveau.briefing, executeur: executeur, effets: effets),
        ]
        return LanguageModelSession(tools: outils,
                                    instructions: ConsignesCerveau.texte(envoiDirect: ReglageVoix.envoiDirect, recap: recap))
    }
}

/// Cartes demandées par les outils pendant un tour (les outils tournent hors de l'acteur principal).
final class CollecteurEffets: @unchecked Sendable {
    private let verrou = NSLock()
    private var effets: [ExecuteurOutils.Effet] = []
    private var outilsEnCours = 0

    /// Un outil commence ou finit de lire des données.
    func debutOutil() { verrou.withLock { outilsEnCours += 1 } }
    func finOutil() { verrou.withLock { outilsEnCours = max(outilsEnCours - 1, 0) } }
    var outilEnCours: Bool { verrou.withLock { outilsEnCours > 0 } }

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
        effets.debutOutil()
        defer { effets.finOutil() }
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
        effets.debutOutil()
        defer { effets.finOutil() }
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
        effets.debutOutil()
        defer { effets.finOutil() }
        let r = await executeur.executer(nom: name, arguments: OutilChantier.json(["reference": arguments.reference]))
        effets.ajouter(r.effet)
        return r.sortie
    }
}

/// Question pour Claude, l'assistant du bureau sur le PC : la réponse arrive plus tard, affichée et dite.
@available(iOS 26.0, *)
struct OutilDemanderClaude: Tool {
    let name = "demander_assistant"
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
        effets.debutOutil()
        defer { effets.finOutil() }
        let r = await executeur.executer(nom: name, arguments: OutilChantier.json(["question": arguments.question, "agent": arguments.agent]))
        effets.ajouter(r.effet)
        return r.sortie
    }
}

/// Demande de travail pour l'assistant du bureau : seulement préparée. Elle s'affiche à l'écran,
/// le patron la relit et touche « Transmettre » ; l'outil ne transmet jamais rien lui-même.
@available(iOS 26.0, *)
struct OutilSaisie: Tool {
    let name = "saisie"
    let description = ConsignesCerveau.saisie
    let executeur: ExecuteurOutils
    let effets: CollecteurEffets

    @Generable
    struct Arguments {
        @Guide(description: "La demande du patron, complète, à l’infinitif ou telle qu’il l’a dite")
        var texte: String
    }

    func call(arguments: Arguments) async throws -> String {
        effets.debutOutil()
        defer { effets.finOutil() }
        let r = await executeur.executer(nom: name, arguments: OutilChantier.json(["texte": arguments.texte]))
        effets.ajouter(r.effet)
        return r.sortie
    }
}

/// Ouvre un outil de terrain (bon de régie, bon de livraison, relevé) : l'écran s'affiche, le patron fait le reste.
@available(iOS 26.0, *)
struct OutilOuvrir: Tool {
    let name = "ouvrir_outil"
    let description = ConsignesCerveau.ouvrirOutil
    let executeur: ExecuteurOutils
    let effets: CollecteurEffets

    @Generable
    struct Arguments {
        @Guide(description: "regie, bon_livraison ou releve")
        var outil: String
        @Guide(description: "Identifiant du chantier (outil chantiers, champ id), vide s’il n’est pas connu")
        var chantierId: String
    }

    func call(arguments: Arguments) async throws -> String {
        effets.debutOutil()
        defer { effets.finOutil() }
        let r = await executeur.executer(nom: name, arguments: OutilChantier.json(["outil": arguments.outil, "chantier_id": arguments.chantierId]))
        effets.ajouter(r.effet)
        return r.sortie
    }
}

#endif
