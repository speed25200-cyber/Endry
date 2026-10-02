import EndryKit
import SwiftUI

/// Assistant du bureau : état, file de travail, pause / reprise.
struct CarteAssistantBureau: View {
    var pilotage: ModelePilotage
    @State private var confirmationPause = false

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            HStack(spacing: Espace.s) {
                Circle()
                    .fill(pilotage.enPause ? Color.ambre : Color.sauge)
                    .frame(width: 8, height: 8)
                    .shadow(color: pilotage.enPause ? Color.ambre : Color.sauge, radius: 4)
                Text(pilotage.enPause ? "En pause" : "En marche")
                    .styleTexte(15, relativeTo: .subheadline, graisse: .semibold)
                    .foregroundStyle(Color.encre)
                    .contentTransition(.opacity)
                Spacer()
                if let etat = pilotage.etat, etat.file > 0 {
                    Pastille(texte: "\(etat.file) en file", couleur: .ambre, icone: "tray.full.fill")
                }
            }
            Text(pilotage.enPause
                 ? "L’assistant ne prépare plus rien. Vous pouvez tout consulter ; les décisions attendent la reprise."
                 : "L’assistant prépare les propositions ; rien ne part sans votre geste.")
                .styleTexte(13, relativeTo: .footnote)
                .foregroundStyle(Color.encreDouce)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if pilotage.enPause {
                    Task { await pilotage.basculer() }
                } else {
                    confirmationPause = true
                }
            } label: {
                Label(pilotage.enPause ? "Reprendre l’assistant" : "Mettre en pause",
                      systemImage: pilotage.enPause ? "play.fill" : "pause.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(BoutonSecondaire(couleur: pilotage.enPause ? .sauge : .ambre))
            .disabled(pilotage.enCours)
            .accessibilityIdentifier("pause-reprise")
        }
        .padding(Espace.m)
        .surfaceCarte(rayon: 22)
        .animation(.endry, value: pilotage.enPause)
        .sensoryFeedback(.success, trigger: pilotage.enPause)
        .confirmationDialog("Mettre l’assistant en pause ?", isPresented: $confirmationPause, titleVisibility: .visible) {
            Button("Mettre en pause") { Task { await pilotage.basculer() } }
        } message: {
            Text("Il cesse de préparer des propositions jusqu’à la reprise.")
        }
    }
}
