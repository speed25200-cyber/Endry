import EndryKit
import Foundation

/// Mises à jour poussées par le PC (`GET /evenements`, Server-Sent Events, v1.1).
///
/// Même session réseau que les requêtes (la connexion au PC reste chaude). Le flux est lu hors du fil principal ;
/// une réponse prête (`event: reponse`) est traitée à l'instant, sans attendre les rechargements en cours, et les
/// rechargements sont regroupés sans jamais bloquer la lecture du flux. Reconnexion rapide ; si le serveur ne
/// propose pas le flux (v1.0) ou reste injoignable, repli sur une interrogation toutes les 60 s.
/// Actif seulement au premier plan.
@MainActor
final class FluxEvenements {
    /// Appelé pour chaque sujet mis à jour (ou pour tous, en interrogation périodique).
    var surSujets: (@MainActor (Set<SujetMaj>) async -> Void)?
    /// Réponse prête (`event: reponse`) : identifiant de la question et, si le PC la joint, la réponse elle-même.
    var surReponse: (@MainActor (String, ReponseAgent?) async -> Void)?
    /// Réponse en train de s'écrire (`event: reponse_partielle`, v1.8) : identifiant et texte cumulé.
    var surPartiel: (@MainActor (String, String) -> Void)?

    private var tache: Task<Void, Never>?
    private var aRecharger: Set<SujetMaj> = []
    private var rechargement: Task<Void, Never>?
    private static let intervalleInterrogation: Duration = .seconds(60)
    /// Attente avant de rouvrir le flux : quasi immédiate après une coupure, puis plus espacée après des échecs.
    private static let attentesReconnexion: [Duration] = [.milliseconds(300), .seconds(2), .seconds(5), .seconds(15)]

    func demarrer(client: ClientAPI) {
        arreter()
        tache = Task { [weak self] in
            await self?.boucle(client: client)
        }
    }

    func arreter() {
        tache?.cancel()
        tache = nil
    }

    private func boucle(client: ClientAPI) async {
        var echecs = 0
        var fluxIndisponible = false
        while !Task.isCancelled {
            if !fluxIndisponible {
                switch await ecouter(client: client) {
                case .interrompu:
                    echecs = 0
                case .indisponible:
                    fluxIndisponible = true
                case .erreur:
                    echecs += 1
                }
            }
            guard !Task.isCancelled else { return }
            if fluxIndisponible || echecs >= 4 {
                // Repli : interrogation toutes les 60 s ; on retente le flux de temps en temps.
                try? await Task.sleep(for: Self.intervalleInterrogation)
                guard !Task.isCancelled else { return }
                signaler(Set(SujetMaj.allCases))
                if echecs >= 4 { echecs = 1 }
            } else {
                // Reconnexion quasi immédiate après une coupure (tunnel, changement de réseau), puis plus espacée.
                try? await Task.sleep(for: Self.attentesReconnexion[min(echecs, 3)])
                // Le flux revient : ce qui a pu changer pendant la coupure est relu.
                if echecs == 0 { signaler([.saisies, .agents]) }
            }
        }
    }

    private enum Fin: Sendable { case interrompu, indisponible, erreur }

    private func ecouter(client: ClientAPI) async -> Fin {
        guard let requete = try? client.requeteFlux() else { return .indisponible }
        let session = (client.transport as? TransportURLSession)?.session ?? TransportURLSession.partagee
        // Lecture octet par octet hors du fil principal ; seuls les événements complets y reviennent.
        let (evenements, suite) = AsyncStream<EvenementSSE>.makeStream()
        let lecture = Task.detached(priority: .userInitiated) { () -> Fin in
            defer { suite.finish() }
            do {
                let (octets, reponse) = try await session.bytes(for: requete)
                guard let http = reponse as? HTTPURLResponse else { return .erreur }
                if [404, 405, 501].contains(http.statusCode) { return .indisponible }
                guard (200..<300).contains(http.statusCode) else { return .erreur }
                var analyseur = AnalyseurSSE()
                var ligne: [UInt8] = []
                for try await octet in octets {
                    if octet == UInt8(ascii: "\n") {
                        if let evenement = analyseur.lire(String(decoding: ligne, as: UTF8.self)) { suite.yield(evenement) }
                        ligne.removeAll(keepingCapacity: true)
                    } else {
                        ligne.append(octet)
                    }
                }
                return .interrompu
            } catch {
                return Task.isCancelled ? .interrompu : .erreur
            }
        }
        await withTaskCancellationHandler {
            for await evenement in evenements { traiter(evenement) }
        } onCancel: {
            lecture.cancel()
        }
        return await lecture.value
    }

    /// Un événement du PC : réponse d'abord (à l'instant), puis rechargement ciblé (regroupé, en arrière-plan).
    private func traiter(_ evenement: EvenementSSE) {
        if let partiel = evenement.reponsePartielle {
            surPartiel?(partiel.questionId, partiel.texte)
            return
        }
        if let pret = evenement.reponsePrete, let surReponse {
            Task { await surReponse(pret.questionId, pret.reponse) }
        }
        if let sujet = evenement.sujet { signaler([sujet]) }
    }

    /// Rechargements regroupés : la lecture du flux n'attend jamais la fin d'un rechargement.
    private func signaler(_ sujets: Set<SujetMaj>) {
        aRecharger.formUnion(sujets)
        guard rechargement == nil else { return }
        rechargement = Task { [weak self] in
            while let self, !self.aRecharger.isEmpty {
                let lot = self.aRecharger
                self.aRecharger = []
                await self.surSujets?(lot)
            }
            self?.rechargement = nil
        }
    }
}
