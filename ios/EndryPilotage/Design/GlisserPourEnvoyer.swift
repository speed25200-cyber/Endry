import SwiftUI

/// Curseur « Glisser pour envoyer » : geste de confirmation obligatoire quand « Oui » fait partir
/// un e-mail ou un document chez un client. Retour haptique au seuil et à la validation.
struct GlisserPourEnvoyer: View {
    var libelle = "Glisser pour envoyer"
    var enCours = false
    var actif = true
    var action: () -> Void

    @State private var decalage: CGFloat = 0
    @State private var seuilAtteint = false
    @State private var valide = false
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    private let diametre: CGFloat = 52
    private let marge: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let course = max(geo.size.width - diametre - marge * 2, 1)
            let progression = min(max(decalage / course, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.espresso)
                // Traînée dorée qui suit le pouce.
                Capsule()
                    .fill(LinearGradient(colors: [Color.or.opacity(0.0), Color.or.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: decalage + diametre + marge * 2)

                HStack(spacing: Espace.xs) {
                    Text(enCours ? "Envoi…" : libelle)
                        .styleTexte(15, relativeTo: .body, graisse: .semibold)
                    if !enCours {
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 13, weight: .bold))
                            .phaseAnimator(reduireAnimations ? [0.0] : [0.0, 6.0]) { contenu, phase in
                                contenu.offset(x: phase)
                            } animation: { _ in .easeInOut(duration: 0.9) }
                    }
                }
                .foregroundStyle(Color.orClair.opacity(0.9 - progression * 0.8))
                .frame(maxWidth: .infinity)
                .padding(.leading, diametre * 0.6)

                Circle()
                    .fill(.degradeOr)
                    .frame(width: diametre, height: diametre)
                    .overlay {
                        if enCours {
                            ProgressView().tint(Color.espresso)
                        } else {
                            Image(systemName: valide ? "checkmark" : "paperplane.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.espresso)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .shadow(color: Color.black.opacity(0.3), radius: 6, y: 3)
                    .offset(x: marge + decalage)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { valeur in
                                guard actif, !enCours, !valide else { return }
                                decalage = min(max(valeur.translation.width, 0), course)
                                seuilAtteint = decalage >= course * 0.92
                            }
                            .onEnded { _ in
                                guard actif, !enCours, !valide else { return }
                                if decalage >= course * 0.92 {
                                    withAnimation(.snappy) { decalage = course; valide = true }
                                    action()
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.62)) { decalage = 0 }
                                    seuilAtteint = false
                                }
                            }
                    )
            }
        }
        .frame(height: diametre + marge * 2)
        .opacity(actif ? 1 : 0.45)
        .sensoryFeedback(.impact(weight: .medium), trigger: seuilAtteint) { _, nouveau in nouveau }
        .sensoryFeedback(.success, trigger: valide) { _, nouveau in nouveau }
        .onChange(of: enCours) { _, nouveau in
            // Échec de l'envoi : le curseur revient au départ.
            if !nouveau, valide {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                        decalage = 0
                        valide = false
                        seuilAtteint = false
                    }
                }
            }
        }
        // VoiceOver : une action explicite remplace le glissement.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(libelle))
        .accessibilityHint(Text("Envoie immédiatement au destinataire."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Envoyer")) {
            guard actif, !enCours else { return }
            valide = true
            action()
        }
        .accessibilityIdentifier("glisser-pour-envoyer")
    }
}

#Preview {
    VStack(spacing: 24) {
        GlisserPourEnvoyer {}
        GlisserPourEnvoyer(enCours: true) {}
    }
    .padding()
    .background(Color.fond)
}
