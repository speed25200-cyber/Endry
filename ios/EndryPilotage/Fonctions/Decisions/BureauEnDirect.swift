import EndryKit
import SwiftUI

/// Poste de pilotage — « Bureau en direct » : chaque agent sur une ligne (point d'état, nom, ce qu'il fait,
/// charge du jour). Les agents au travail d'abord. Toucher : Le bureau.
struct BureauEnDirect: View {
    var modele: ModeleAgents
    var ouvrir: () -> Void

    var body: some View {
        let agents = Self.ordonnes(modele.agents, etat: modele.etatAffiche).prefix(4)
        VStack(alignment: .leading, spacing: 10) {
            TitreSection(titre: "Bureau en direct", lien: "Le bureau", action: ouvrir)
            Button(action: ouvrir) {
                VStack(spacing: 0) {
                    ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                        ligne(agent, etat: modele.etatAffiche(agent))
                        if index < agents.count - 1 {
                            Rectangle().fill(Color.filet).frame(height: Espace.filet)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .tuileMaison(rayon: 22)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(ActionPressee())
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Ouvre Le bureau"))
            .accessibilityIdentifier("bureau-en-direct")
        }
    }

    private func ligne(_ agent: AgentPC, etat: EtatAgent) -> some View {
        HStack(spacing: 10) {
            PointEtat(etat: modele.enDirect ? etat : nil, taille: 7)
                .frame(width: 10)
            Text(agent.nom)
                .font(.system(size: UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 15), weight: .medium))
                .foregroundStyle(Color.encre)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
            Text(activite(agent, etat: etat))
                .font(.system(size: UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 13.5)))
                .foregroundStyle(Color.encreDouce)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            let n = agent.traiteesJour + agent.file
            if n > 0 {
                Text("\(n)")
                    .font(Police.mono(11.5))
                    .foregroundStyle(Color.encreDouce)
                    .accessibilityLabel(Text(n == 1 ? "1 tâche" : "\(n) tâches"))
            }
        }
        .frame(minHeight: 46)
    }

    private func activite(_ agent: AgentPC, etat: EtatAgent) -> String {
        guard modele.enDirect else { return agent.role ?? "Domaine de l’assistant" }
        switch etat {
        case .occupe: return agent.tache ?? "Au travail"
        case .libre: return agent.resumeJour ?? "Au repos"
        case .pause: return "En pause"
        case .erreur: return "Bloqué : attend une intervention"
        case .horsHoraires: return "Hors horaires"
        }
    }

    /// Au travail, bloqués, puis les autres ; ordre du PC conservé à égalité.
    static func ordonnes(_ agents: [AgentPC], etat: (AgentPC) -> EtatAgent) -> [AgentPC] {
        func rang(_ e: EtatAgent) -> Int {
            switch e {
            case .occupe: 0
            case .erreur: 1
            case .libre: 2
            case .pause: 3
            case .horsHoraires: 4
            }
        }
        return agents.enumerated()
            .sorted { (rang(etat($0.element)), $0.offset) < (rang(etat($1.element)), $1.offset) }
            .map(\.element)
    }
}
