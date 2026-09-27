import Foundation

/// Exécute les outils appelés par le modèle vocal, avec le jeton de l'appareil, et renvoie un résumé JSON compact.
/// `proposer_decision` n'exécute rien : il affiche la carte et attend le geste du patron.
public struct ExecuteurOutils: Sendable {
    public enum Effet: Hashable, Sendable {
        case aucun
        /// Afficher une carte contextuelle pendant la conversation.
        case afficherDecision(String)
        case afficherChantier(String)
        case afficherFacture(String)
        /// Question posée à Claude sur le PC : sa réponse arrivera dans le résumé de la saisie.
        case questionClaude(suivi: SuiviQuestion, question: String, agent: String?, message: String?)
        /// Question préparée par la voix : le patron la voit et touche « Envoyer » ; rien ne part avant.
        case questionAConfirmer(question: String, agent: String?, agentId: String?)
        /// Demande de travail préparée par la voix : le patron la voit et touche « Transmettre » ; rien ne part avant.
        case saisieAConfirmer(texte: String)
        /// Réponse de Claude (et de l'agent qui a répondu), à afficher et à dire.
        case reponseClaude(question: String, reponse: String, agent: String?)
        /// Outil de terrain à ouvrir (`regie`, `bon_livraison`, `releve`), éventuellement pour un chantier.
        case ouvrirOutil(outil: String, chantierId: String?)
    }

    /// Outils de terrain connus de la voix.
    public static let outilsTerrain = ["regie", "bon_livraison", "releve"]

    public let api: any EndryAPI

    public init(api: any EndryAPI) {
        self.api = api
    }

    public func executer(nom: String, arguments: String) async -> (sortie: String, effet: Effet) {
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
        do {
            switch nom {
            case "accueil":
                let a = try await api.accueil()
                return (json([
                    "salut": a.salut, "date": a.date, "pause": a.pause,
                    "decisions": a.decisions.map { ["reference": $0.reference, "genre": $0.genre, "titre": $0.titre, "envoi_tiers": $0.exigeGlisser] },
                    "a_encaisser": a.encaisser.total, "en_retard_plus_30_jours": a.encaisser.anciennete.plus30,
                    // Achats fournisseurs : nombre seulement, jamais de montant (à ne pas dire à voix haute).
                    "factures_fournisseurs_7_jours": a.payer.cetteSemaine.count,
                    "chantiers_7_jours": a.chantiers7Jours.map { ["titre": $0.titre, "client": $0.client ?? "", "lieu": $0.lieu ?? "", "dates": $0.dates ?? ""] },
                ]), .aucun)
            case "decisions":
                let d = try await api.decisions()
                return (json(d.decisions.map { ["reference": $0.reference, "titre": $0.titre, "motif": $0.motif, "envoi_tiers": $0.exigeGlisser] }), .aucun)
            case "chantiers":
                let c = try await api.chantiers()
                return (json(c.chantiers.map { chantierResume($0) }), .aucun)
            case "chantier":
                let id = (args["id"] as? String) ?? (args["id"] as? Int).map(String.init) ?? ""
                let d = try await api.chantier(id: id)
                var r = chantierResume(d)
                // Achats fournisseurs : sans montant (prix d'achat jamais dits à voix haute).
                r["documents"] = d.elements.map { e -> [String: Any] in
                    var o: [String: Any] = ["type": e.type.rawValue, "numero": e.numeroAffiche ?? "", "libelle": e.libelle, "statut": e.statut ?? ""]
                    if e.type != .achat { o["montant"] = e.montant ?? 0 }
                    return o
                }
                return (json(r), .afficherChantier(d.id))
            case "argent":
                let a = try await api.argent()
                return (json([
                    "a_encaisser": a.encaisser.total,
                    "par_client": a.encaisser.parClient.map { ["client": $0.client, "montant": $0.montant, "retard_max_jours": $0.retardMax] },
                    "factures_fournisseurs_a_payer": a.payer.factures.count, "offres_en_attente": a.offres.total,
                    "achats_a_refacturer": a.aRefacturer.achats.count,
                    "prix_achat": "Montants d’achat fournisseurs masqués : ne jamais les dire à voix haute ; le détail est dans Finances.",
                    "suivi": "Suivi seulement : aucune relance sans demande du patron.",
                ]), .aucun)
            case "saisie":
                // Jamais transmis d'ici : la demande s'affiche, le patron la relit et touche « Transmettre ».
                let texte = (args["texte"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !texte.isEmpty else { return (json(["ok": false, "message": "Texte vide."]), .aucun) }
                return (json(["preparee": true, "transmise": false,
                              "message": "Demande affichée à l’écran. Le patron la relit et touche Transmettre ; rien n’est parti."]),
                        .saisieAConfirmer(texte: texte))
            case "bureau":
                guard let etat = await BureauClaude(api: api).etat() else {
                    return (json(["erreur": "Le PC ne publie pas son activité (serveur v1.0)."]), .aucun)
                }
                if let demande = args["agent"] as? String, !demande.isEmpty,
                   let agent = etat.agent(cite: demande) ?? etat.agents.first(where: { $0.connu == AgentBureau(nom: demande) }) {
                    return (json(["resume": etat.phrase(agent: agent), "agent": agent.nom, "etat": agent.etat.rawValue,
                                  "tache": agent.tache ?? "", "journal": etat.journal.filter { $0.agent == agent.id }.prefix(5).map(\.titre)]), .aucun)
                }
                return (json([
                    "resume": etat.phrase, "pause": etat.enPause, "file": etat.etat?.file ?? 0,
                    "agents": etat.agents.map { ["id": $0.id, "nom": $0.nom, "etat": $0.etat.rawValue, "tache": $0.tache ?? "",
                                                 "aujourd_hui": $0.resumeJour ?? ""] },
                    "journal": etat.journal.prefix(6).map { ["agent": $0.agent ?? "", "titre": $0.titre, "detail": $0.detail ?? ""] },
                    "en_cours": etat.enCours.prefix(5).map { BureauClaude.questionSeule($0.texte) },
                    "derniers_travaux": etat.traitees.prefix(5).map { ["demande": BureauClaude.questionSeule($0.texte), "resultat": $0.resume ?? "",
                                                                      "decision_a_valider": $0.decisionReference ?? ""] },
                ]), .aucun)
            case "demander_assistant", "demander_claude":
                // Préparée seulement : le patron voit la question et touche « Envoyer » (puis `POST /assistant/question`).
                let question = (args["question"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !question.isEmpty else { return (json(["ok": false, "message": "Question vide."]), .aucun) }
                let (agentId, nomAgent) = await BureauClaude(api: api).resoudreAgent(question: question, demande: args["agent"] as? String)
                return (json(["preparee": true, "envoyee": false, "domaine": nomAgent ?? "",
                              "message": "Question affichée à l’écran. Le patron la relit et touche Envoyer ; l’assistant du PC répond à son prochain passage. N’invente pas la réponse."]),
                        .questionAConfirmer(question: question, agent: nomAgent, agentId: agentId))
            case "ouvrir_outil":
                // Ouvre l'écran ; le patron remplit, relit, fait signer et transmet lui-même.
                let outil = (args["outil"] as? String ?? "").lowercased()
                guard Self.outilsTerrain.contains(outil) else {
                    return (json(["ok": false, "message": "Outil inconnu : regie, bon_livraison ou releve."]), .aucun)
                }
                let chantier = (args["chantier_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return (json(["affiche": true, "message": "L’écran s’ouvre dès que le patron touche Ouvrir. Rien n’est transmis."]),
                        .ouvrirOutil(outil: outil, chantierId: chantier))
            case "briefing":
                async let a = try? api.accueil()
                async let c = try? api.chantiers()
                async let g = try? api.argent()
                let (accueil, chantiers, argent) = await (a, c, g)
                let b = Briefing.composer(accueil: accueil, semaine: chantiers?.semaine ?? [], argent: argent,
                                          offresASuivre: SuiviOffres.aSuivre(argent?.offres.offres ?? []))
                return (json(["briefing": b.texteParle]), .aucun)
            case "proposer_decision":
                let reference = args["reference"] as? String ?? ""
                return (json(["affichee": true, "message": "La carte est affichée ; le patron doit valider lui-même par un geste à l’écran."]),
                        .afficherDecision(reference))
            default:
                return (json(["erreur": "Outil inconnu : \(nom)"]), .aucun)
            }
        } catch {
            return (json(["erreur": error.message]), .aucun)
        }
    }

    private func chantierResume(_ d: Dossier) -> [String: Any] {
        ["id": d.id, "titre": d.titre, "client": d.client, "lieu": d.lieu ?? "", "etape": d.etapeLibelle,
         "montant": d.montant ?? 0, "dates": Planning.libelleDates(d) ?? "", "decision_en_attente": d.decisionEnAttente, "note": d.note ?? ""]
    }

    private func json(_ objet: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: objet, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
