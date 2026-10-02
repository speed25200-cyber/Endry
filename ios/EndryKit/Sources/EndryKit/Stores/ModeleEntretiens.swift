import Foundation
import Observation

/// Entretiens récurrents (v1.3) : liste du PC, propositions préparées par le bureau.
@MainActor
@Observable
public final class ModeleEntretiens {
    public private(set) var entretiens: [Entretien] = []
    public private(set) var etat: EtatChargement = .initial
    /// Faux si le PC ne connaît pas encore `/entretiens` (404) : l'écran l'explique et propose la saisie.
    public private(set) var disponible = true
    /// Entretien en cours de préparation (bouton occupé).
    public private(set) var enPreparation: String?

    @ObservationIgnored private let api: any EndryAPI

    public init(api: any EndryAPI) {
        self.api = api
    }

    public var groupes: [GroupesEntretiens.Groupe] { GroupesEntretiens.grouper(entretiens) }

    /// À planifier d'ici un mois (retards compris).
    public var aPlanifier: [Entretien] {
        entretiens.filter { e in
            guard e.peutProposer, let d = e.dateEcheance else { return false }
            return DateEndry.jours(de: Date(), a: d) <= 31
        }
    }

    public func charger() async {
        if entretiens.isEmpty { etat = .chargement }
        do {
            entretiens = try await api.entretiens()
            disponible = true
            etat = .pret
        } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
            disponible = false
            etat = .pret
        } catch {
            etat = entretiens.isEmpty ? .erreur(error) : .pret
        }
    }

    /// Le bureau prépare la proposition de rendez-vous ; elle attendra le Oui du patron.
    public func proposer(_ e: Entretien, consignes: String) async -> Result<ReponsePreparation, ErreurAPI> {
        enPreparation = e.id
        defer { enPreparation = nil }
        do {
            let r = try await api.proposerEntretien(e, consignes: consignes)
            if let i = entretiens.firstIndex(where: { $0.id == e.id }) {
                entretiens[i].statut = .propose
                entretiens[i].decisionReference = r.decisionReference
            }
            return .success(r)
        } catch {
            return .failure(error)
        }
    }
}
