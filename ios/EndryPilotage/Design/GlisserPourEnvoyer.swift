import SwiftUI

/// Curseur « Glisser pour envoyer » : geste de confirmation obligatoire quand « Oui » fait partir
/// un e-mail ou un document chez un tiers.
///
/// Le pouce rencontre une résistance physique (plus on approche du bout, plus il faut tirer),
/// la piste se remplit d'or au fil du geste et le retour haptique monte en crescendo jusqu'au seuil.
struct GlisserPourEnvoyer: View {
    var libelle = "Glisser pour envoyer"
    var enCours = false
    var actif = true
    var action: () -> Void

    @State private var decalage: CGFloat = 0
    @State private var palier = 0
    @State private var valide = false
    @State private var relache = 0
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    private let diametre: CGFloat = 52
    private let marge: CGFloat = 4
    /// Nombre de crans haptiques avant le seuil.
    private static let crans = 5
    private static let seuil: CGFloat = 0.94

    /// Résistance : le déplacement du curseur ralentit en approchant du bout de la piste.
    static func resistance(_ tire: CGFloat, course: CGFloat) -> CGFloat {
        guard course > 0 else { return 0 }
        let x = max(tire, 0) / course
        let k: CGFloat = 1.35
        return course * min((1 - exp(-k * x)) / (1 - exp(-k)), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let course = max(geo.size.width - diametre - marge * 2, 1)
            let progression = min(max(decalage / course, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.espresso)
                    .overlay(Capsule().strokeBorder(Color.bordureOr, lineWidth: Espace.filet))

                // Remplissage or : s'épaissit et s'éclaire avec le geste.
                Capsule()
                    .fill(LinearGradient(colors: [Color.orOmbre.opacity(0.25 + 0.35 * progression),
                                                  Color.or.opacity(0.35 + 0.55 * progression)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: decalage + diametre + marge * 2)
                    .shadow(color: Color.or.opacity(0.45 * progression), radius: 12 * progression)

                HStack(spacing: Espace.xs) {
                    Text(enCours ? "Envoi…" : valide ? "Envoyé" : libelle)
                        .styleTexte(15, relativeTo: .body, graisse: .semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if !enCours, !valide {
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 13, weight: .bold))
                            .phaseAnimator(reduireAnimations ? [0.0] : [0.0, 6.0]) { contenu, phase in
                                contenu.offset(x: phase)
                            } animation: { _ in .easeInOut(duration: 0.9) }
                    }
                }
                .foregroundStyle(Color.orClair.opacity(0.92 - progression * 0.8))
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
                    .scaleEffect(1 + 0.06 * progression)
                    .shadow(color: Color.black.opacity(0.3), radius: 6, y: 3)
                    .offset(x: marge + decalage)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { valeur in
                                guard actif, !enCours, !valide else { return }
                                decalage = Self.resistance(valeur.translation.width, course: course)
                                palier = Int((decalage / course) / Self.seuil * CGFloat(Self.crans))
                            }
                            .onEnded { _ in
                                guard actif, !enCours, !valide else { return }
                                if decalage >= course * Self.seuil {
                                    withAnimation(.endry(reduire: reduireAnimations)) { decalage = course; valide = true }
                                    action()
                                } else {
                                    relache += 1
                                    withAnimation(reduireAnimations ? .fonduDoux : .spring(response: 0.42, dampingFraction: 0.62)) {
                                        decalage = 0
                                    }
                                    palier = 0
                                }
                            }
                    )
            }
        }
        .frame(height: diametre + marge * 2)
        .opacity(actif ? 1 : 0.45)
        // Crescendo : chaque cran frappe un peu plus fort, le seuil claque.
        .sensoryFeedback(trigger: palier) { ancien, nouveau in
            guard nouveau > ancien else { return nil }
            if nouveau >= Self.crans { return .impact(weight: .heavy, intensity: 1) }
            return .impact(flexibility: .soft, intensity: 0.25 + 0.6 * Double(nouveau) / Double(Self.crans))
        }
        .sensoryFeedback(.success, trigger: valide) { _, nouveau in nouveau }
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.4), trigger: relache)
        .onChange(of: enCours) { _, nouveau in
            // Échec de l'envoi : le curseur revient au départ.
            if !nouveau, valide {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    withAnimation(.endry(reduire: reduireAnimations)) {
                        decalage = 0
                        valide = false
                        palier = 0
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
