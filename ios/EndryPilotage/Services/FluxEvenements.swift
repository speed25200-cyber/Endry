import EndryKit
import Foundation

/// Mises à jour poussées par le PC (`GET /evenements`, Server-Sent Events, v1.1).
///
/// Reconnexion automatique avec attente croissante ; si le serveur ne propose pas le flux (v1.0)
/// ou qu'il reste injoignable, repli sur une interrogation toutes les 60 s. Actif seulement au premier plan.
@MainActor
final class FluxEvenements {
    /// Appelé pour chaque sujet mis à jour (ou pour tous, en interrogation périodique).
    var surSujets: (@MainActor (Set<SujetMaj>) async -> Void)?

    private var tache: Task<Void, Never>?
    private static let intervalleInterrogation: Duration = .seconds(60)

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 24 * 3_600
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

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
            if fluxIndisponible || echecs >= 3 {
                // Repli : interrogation toutes les 60 s ; on retente le flux de temps en temps.
                try? await Task.sleep(for: Self.intervalleInterrogation)
                guard !Task.isCancelled else { return }
                await surSujets?(Set(SujetMaj.allCases))
                if echecs >= 3 { echecs = 1 }
            } else {
                try? await Task.sleep(for: .seconds([2, 5, 15][min(echecs, 2)]))
            }
        }
    }

    private enum Fin { case interrompu, indisponible, erreur }

    private func ecouter(client: ClientAPI) async -> Fin {
        guard let requete = try? client.requeteFlux() else { return .indisponible }
        do {
            let (octets, reponse) = try await session.bytes(for: requete)
            guard let http = reponse as? HTTPURLResponse else { return .erreur }
            if [404, 405, 501].contains(http.statusCode) { return .indisponible }
            guard (200..<300).contains(http.statusCode) else { return .erreur }

            var analyseur = AnalyseurSSE()
            var ligne: [UInt8] = []
            for try await octet in octets {
                if octet == UInt8(ascii: "\n") {
                    let texte = String(decoding: ligne, as: UTF8.self)
                    ligne.removeAll(keepingCapacity: true)
                    if let evenement = analyseur.lire(texte), let sujet = evenement.sujet {
                        await surSujets?([sujet])
                    }
                } else {
                    ligne.append(octet)
                }
            }
            return .interrompu
        } catch {
            return Task.isCancelled ? .interrompu : .erreur
        }
    }
}
