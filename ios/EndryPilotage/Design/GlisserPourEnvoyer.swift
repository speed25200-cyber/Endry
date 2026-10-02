import SwiftUI

/// Curseur « Glisser pour envoyer » / « Glisser pour valider » : le seul geste qui dit « Oui » à une décision
/// (règle de la direction, 28.09.2026), qu'elle envoie quelque chose à un tiers ou non.
///
/// Le pouce rencontre une résistance physique (plus on approche du bout, plus il faut tirer),
/// un trait de signal suit le geste et le retour haptique monte en crescendo jusqu'au seuil.
struct GlisserPourEnvoyer: View {
    var libelle = "Glisser pour envoyer"
    /// Faux : validation sans envoi à un tiers (« Validation… », « Validé »).
    var envoi = true
    var identifiant = "glisser-pour-envoyer"
    var enCours = false
    var actif = true
    /// Conservé pour compatibilité : le rendu suit désormais le thème (Maison Endry).
    var surPapier = false
    var action: () -> Void

    @State private var decalage: CGFloat = 0
    @State private var palier = 0
    @State private var valide = false
    @State private var relache = 0
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    private let diametre: CGFloat = 44
    private let marge: CGFloat = 2
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

    /// Maison Endry : un filet, un trait de signal qui suit le pouce, le libellé discret à droite,
    /// le bouton rond à gauche (crème dorée en sombre, brun en clair).
    var body: some View {
        GeometryReader { geo in
            let course = max(geo.size.width - diametre - marge * 2, 1)
            let progression = min(max(decalage / course, 0), 1)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.filetFort)
                    .frame(height: Espace.filet)
                    .padding(.horizontal, diametre / 2)
                Capsule()
                    .fill(Color.signal)
                    .frame(width: max(decalage, 0), height: 2)
                    .padding(.leading, marge + diametre / 2)

                Text(enCours ? (envoi ? "Envoi…" : "Validation…") : valide ? (envoi ? "Envoyé" : "Validé") : libelle)
                    .font(Police.mono(12, relativeTo: .footnote))
                    .foregroundStyle(Color.encreDouce)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.leading, diametre + Espace.s)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .opacity(1 - progression * 0.85)

                Circle()
                    .fill(Color.bouton)
                    .frame(width: diametre, height: diametre)
                    .overlay {
                        if enCours {
                            ProgressView().tint(Color.boutonTexte)
                        } else {
                            Image(systemName: valide ? "checkmark" : (envoi ? "paperplane" : "arrow.right"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.boutonTexte)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: Espace.filet))
                    .shadow(color: Color.ombre, radius: 9, y: 6)
                    .scaleEffect(1 + 0.06 * progression)
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
        .accessibilityHint(Text(envoi ? "Envoie immédiatement au destinataire." : "Valide la décision."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(envoi ? "Envoyer" : "Valider")) {
            guard actif, !enCours else { return }
            valide = true
            action()
        }
        .accessibilityIdentifier(identifiant)
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
