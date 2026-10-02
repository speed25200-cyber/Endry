import EndryKit
import SwiftUI

/// Accueil Maison Endry : capsule de verre « en direct » sous la barre du haut — ce que fait le bureau maintenant.
/// Toucher : Le bureau (onglet Entreprise).
struct StatutBureau: View {
    var modele: ModeleAgents
    var ouvrir: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations
    @State private var pulse = false

    var body: some View {
        Button(action: ouvrir) {
            HStack(spacing: Espace.xs) {
                Circle()
                    .fill(modele.enDirect ? Color.sauge : Color.encrePale)
                    .frame(width: 7, height: 7)
                    .opacity(pulse && modele.enDirect ? 0.35 : 1)
                HStack(spacing: 0) {
                    Text(titre).fontWeight(.semibold).foregroundStyle(Color.encre)
                    Text(detail).foregroundStyle(Color.encreDouce)
                }
                .styleTexte(12.5, relativeTo: .footnote)
                .lineLimit(1)
                Spacer(minLength: Espace.xs)
                Text(compte)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.encrePale)
            }
            .padding(.horizontal, Espace.s)
            .frame(height: 36)
            .verre(Capsule())
            .overlay(Capsule().strokeBorder(Color.bordureOr, lineWidth: Espace.filet))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Ouvre Le bureau"))
        .accessibilityIdentifier("statut-bureau")
        .onAppear {
            guard !reduireAnimations, !Configuration.testsUI else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var actif: AgentPC? {
        modele.agents.first { $0.etat == .occupe && $0.tache != nil }
    }

    private var titre: String {
        if let actif, modele.enDirect { return actif.nom }
        return modele.libelle
    }

    private var detail: String {
        if let actif, modele.enDirect, let tache = actif.tache { return " · " + tache.prefix(1).lowercased() + String(tache.dropFirst()) }
        return ""
    }

    private var compte: String {
        let n = modele.agents.filter { $0.etat == .occupe }.count
        return n > 0 ? "\(n) actif\(n > 1 ? "s" : "")" : "\(modele.agents.count) agents"
    }
}
