import EndryKit
import Foundation
import Observation

/// Une question posée à un agent depuis sa fiche, et sa réponse.
struct EchangeAgent: Identifiable, Hashable {
    enum Etat: Hashable { case enCours, enAttente, repondu, erreur }
    let id = UUID()
    var question: String
    var etat: Etat = .enCours
    var reponse: String?
    var sources: [SourceReponse] = []
    var decisionReference: String?
    /// Suivi côté PC, pour revérifier sur `maj saisies`.
    var suivi: SuiviQuestion?
}

/// Le bureau vu depuis l'app : agents de Claude sur le PC, leur état, leur journal, et les échanges du patron avec eux.
/// v1.2 : tout vient du PC (`GET /agents`, `/journal`, questions directes). Avant : agents de base, questions par la saisie.
@MainActor
@Observable
final class ModeleAgents {
    private(set) var etat: EtatBureau?
    private(set) var charge = false
    /// Échanges par agent (id), gardés le temps de la session.
    private(set) var echanges: [String: [EchangeAgent]] = [:]
    private(set) var journaux: [String: [EntreeJournal]] = [:]

    @ObservationIgnored private let bureau: BureauClaude
    @ObservationIgnored private let api: any EndryAPI
    @ObservationIgnored private let transmettre: @MainActor (String) async -> ModeleSaisie.ResultatDemande

    init(api: any EndryAPI, transmettre: @escaping @MainActor (String) async -> ModeleSaisie.ResultatDemande) {
        self.api = api
        self.bureau = BureauClaude(api: api)
        self.transmettre = transmettre
    }

    /// Le PC publie ses agents (v1.2) : état et journal en direct.
    var enDirect: Bool { !(etat?.agents.isEmpty ?? true) }
    var agents: [AgentPC] { enDirect ? (etat?.agents ?? []) : AgentPC.parDefaut }
    var journal: [EntreeJournal] { etat?.journal ?? [] }
    var libelle: String { etat?.libelleCourt ?? "Claude et ses agents" }

    func agent(_ id: String) -> AgentPC? { agents.first { $0.id == id } }

    func charger() async {
        if let nouveau = await bureau.etat() { etat = nouveau }
        charge = true
    }

    func chargerJournal(de agent: AgentPC) async {
        guard enDirect else { return }
        if let entrees = try? await api.journal(agent: agent.id, limite: 30) {
            journaux[agent.id] = entrees
        } else {
            journaux[agent.id] = journal.filter { $0.agent == agent.id }
        }
    }

    func journal(de agent: AgentPC) -> [EntreeJournal] {
        journaux[agent.id] ?? journal.filter { $0.agent == agent.id }
    }

    /// Question directe à un agent : réponse immédiate, ou suivie jusqu'à son arrivée.
    func demander(_ question: String, a agent: AgentPC) async {
        let texte = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty else { return }
        var echange = EchangeAgent(question: texte)
        echanges[agent.id, default: []].append(echange)
        func mettreAJour(_ modifier: (inout EchangeAgent) -> Void) {
            guard let index = echanges[agent.id]?.firstIndex(where: { $0.id == echange.id }) else { return }
            modifier(&echanges[agent.id]![index])
            echange = echanges[agent.id]![index]
        }
        do {
            let posee = try await bureau.poser(texte, agentId: enDirect ? agent.id : nil, nomAgent: agent.nom)
            let resultat: ReponseAgent?
            switch posee {
            case .reponse(let r): resultat = r
            case .enAttente(let suivi, let message):
                mettreAJour { $0.suivi = suivi }
                if let message {
                    // Hors horaires : on l'affiche et on ne sonde pas ; la réponse viendra au prochain passage.
                    mettreAJour { e in
                        e.etat = .enAttente
                        e.reponse = message
                    }
                    await charger()
                    return
                }
                await charger()
                resultat = await bureau.attendre(suivi)
            }
            mettreAJour { e in appliquer(resultat, a: &e) }
        } catch {
            mettreAJour { e in
                e.etat = .erreur
                e.reponse = error.message
            }
        }
        await charger()
    }

    /// Réponses arrivées depuis (appelé sur chaque `maj saisies` du PC).
    func verifierEnAttente() async {
        for (agentId, liste) in echanges {
            for echange in liste where echange.etat == .enAttente {
                guard let suivi = echange.suivi, let r = await bureau.verifier(suivi) else { continue }
                if let index = echanges[agentId]?.firstIndex(where: { $0.id == echange.id }) {
                    appliquer(r, a: &echanges[agentId]![index])
                }
            }
        }
    }

    private func appliquer(_ resultat: ReponseAgent?, a e: inout EchangeAgent) {
        if let resultat, resultat.statut == .repondu, let r = resultat.reponse {
            e.etat = .repondu
            e.reponse = r
            e.sources = resultat.sources
            e.decisionReference = resultat.decisionReference
        } else if let resultat, resultat.statut == .erreur {
            e.etat = .erreur
            e.reponse = resultat.message ?? "L’assistant n’a pas pu répondre."
        } else {
            e.etat = .enAttente
            e.reponse = "L’assistant répondra à son prochain passage ; la réponse s’affichera ici."
        }
    }

    /// Confier un travail à un agent : saisie « Pour l'agent … » (gardée sur l'iPhone sans réseau).
    func confier(_ travail: String, a agent: AgentPC) async -> ModeleSaisie.ResultatDemande {
        let texte = travail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty else { return .refusee("La demande est vide.") }
        let resultat = await transmettre("Pour l’agent \(agent.nom) : \(texte)")
        await charger()
        return resultat
    }
}
