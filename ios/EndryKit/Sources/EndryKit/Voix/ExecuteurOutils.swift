import Foundation

/// Exécute les outils appelés par le modèle vocal, avec le jeton de l'appareil, et renvoie un résumé JSON compact.
/// `proposer_decision` n'exécute rien : il affiche la carte et attend le geste du patron.
public struct ExecuteurOutils: Sendable {
    public enum Effet: Equatable, Sendable {
        case aucun
        /// Afficher une carte contextuelle pendant la conversation.
        case afficherDecision(String)
        case afficherChantier(String)
        case afficherFacture(String)
    }

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
                    "a_payer_7_jours": a.payer.totalSemaine,
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
                r["documents"] = d.elements.map { ["type": $0.type.rawValue, "numero": $0.numeroAffiche ?? "", "libelle": $0.libelle, "montant": $0.montant ?? 0, "statut": $0.statut ?? ""] }
                return (json(r), .afficherChantier(d.id))
            case "argent":
                let a = try await api.argent()
                return (json([
                    "a_encaisser": a.encaisser.total,
                    "par_client": a.encaisser.parClient.map { ["client": $0.client, "montant": $0.montant, "retard_max_jours": $0.retardMax] },
                    "a_payer": a.payer.total, "offres_en_attente": a.offres.total, "a_refacturer": a.aRefacturer.total,
                    "suivi": "Suivi seulement : aucune relance sans demande du patron.",
                ]), .aucun)
            case "saisie":
                let texte = (args["texte"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !texte.isEmpty else { return (json(["ok": false, "message": "Texte vide."]), .aucun) }
                let r = try await api.saisie(texte: texte, fichiers: [])
                return (json(["ok": r.ok, "message": r.message ?? "Transmis à l’assistant du bureau."]), .aucun)
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
