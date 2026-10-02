import EndryKit
import SwiftUI

/// Accueil Maison Endry : capsule de verre « en direct » sous l'en-tête — ce que fait le bureau maintenant
/// (« Secrétariat rédige la réponse à Mme Rey · 3 agents »). Toucher : Le bureau.
struct StatutBureau: View {
    var modele: ModeleAgents
    var ouvrir: () -> Void

    var body: some View {
        Button(action: ouvrir) {
            HStack(spacing: Espace.xs) {
                PointVeille(couleur: .sauge, actif: modele.enDirect)
                Text("\(Text(titre).foregroundStyle(Color.encre).fontWeight(.medium))\(Text(detail).foregroundStyle(Color.encreDouce))")
                    .styleTexte(12.5, relativeTo: .footnote)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Espace.xs)
                Text(compte)
                    .font(Police.mono(10.5))
                    .foregroundStyle(Color.encreDouce)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, Espace.s)
            .frame(maxWidth: .infinity, minHeight: 34)
            .verreMaison(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Ouvre Le bureau"))
        .accessibilityIdentifier("statut-bureau")
    }

    private var actif: AgentPC? {
        modele.agents.first { $0.etat == .occupe && $0.tache != nil }
    }

    private var titre: String {
        if let actif, modele.enDirect { return actif.nom }
        return modele.libelle
    }

    private var detail: String {
        guard let actif, modele.enDirect, let tache = actif.tache, let premiere = tache.first else { return "" }
        return " " + premiere.lowercased() + String(tache.dropFirst())
    }

    private var compte: String {
        let n = modele.agents.filter { $0.etat == .occupe }.count
        if n > 0 { return n == 1 ? "1 agent" : "\(n) agents" }
        return "\(modele.agents.count) agents"
    }
}
