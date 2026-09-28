import Foundation
import Observation

/// Offres signées : ce que le bureau a reçu (e-mail, courrier, Bexio), classé par ce qu'il reste à faire.
/// PC v1.5 : `GET /offres/signees` ; sinon repli sur les chantiers à l'étape « acceptée » ou « planifiée ».
@MainActor
@Observable
public final class ModeleOffresSignees {
    public private(set) var offres: [OffreSignee] = []
    public private(set) var etat: EtatChargement = .initial
    /// Faux tant que le PC n'expose pas `/offres/signees` : la liste est déduite des chantiers.
    public private(set) var parLePC = true

    @ObservationIgnored private let api: any EndryAPI

    public init(api: any EndryAPI) {
        self.api = api
    }

    /// Groupes dans l'ordre de ce qu'il reste à faire.
    public var groupes: [(suite: OffreSignee.Suite, offres: [OffreSignee])] {
        OffreSignee.Suite.allCases.compactMap { suite in
            let liste = offres.filter { $0.suite == suite }
            return liste.isEmpty ? nil : (suite, liste)
        }
    }

    public var aPlanifier: Int { offres.filter { $0.suite == .aPlanifier }.count }

    public func charger(chantiers: [Dossier]) async {
        if offres.isEmpty { etat = .chargement }
        do throws(ErreurAPI) {
            offres = Self.trier(try await api.offresSignees())
            parLePC = true
            etat = .pret
        } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
            parLePC = false
            offres = Self.trier(chantiers.filter { ["acceptee", "planifie"].contains($0.etape) }.map(OffreSignee.deduite))
            etat = .pret
        } catch {
            etat = offres.isEmpty ? .erreur(error) : .pret
        }
    }

    nonisolated static func trier(_ liste: [OffreSignee]) -> [OffreSignee] {
        liste.sorted { ($0.date ?? .distantPast, $0.client) > ($1.date ?? .distantPast, $1.client) }
    }
}
