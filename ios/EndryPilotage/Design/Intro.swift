import SwiftUI

// MARK: - Seuil de l'app
//
// L'ouverture, le verrou Face ID et le masquage dans le sélecteur d'apps s'enchaînaient avec trois fonds différents
// (brun uni, halo doré flou, puis l'éclipse de l'accueil) et un monogramme qui changeait de taille et de place à
// chaque fois, agrandi au-delà de sa résolution (flou). Désormais : une seule composition, le même fond que
// l'accueil, le monogramme à une taille où l'image reste nette, toujours au même endroit. D'un écran à l'autre,
// rien ne saute ; seul le pied (bouton de déverrouillage) apparaît ou disparaît.

/// Composition commune du seuil : fond de l'accueil en sombre, monogramme, filet d'or, « ENDRY SA ».
/// Le pied est posé à part, en bas : il ne déplace jamais le monogramme.
struct SeuilMaison<Pied: View>: View {
    /// Ouverture : 0 rien, 1 fond et monogramme, 2 filet et nom. Partout ailleurs : 2.
    var etape = 2
    @ViewBuilder var pied: Pied

    /// L'image du monogramme fait 211 px de haut : nette jusqu'à ~70 pt sur un écran @3x.
    static var hauteurMonogramme: CGFloat { 64 }
    private static var approche: CGFloat { 5.5 }

    var body: some View {
        ZStack {
            Color(hex: 0x0B0907).ignoresSafeArea()
            FondMaison()
                .opacity(etape >= 1 ? 1 : 0)

            VStack(spacing: 0) {
                LogoEndry(taille: Self.hauteurMonogramme)
                    .opacity(etape >= 1 ? 1 : 0)
                    .blur(radius: etape >= 1 ? 0 : 8)
                Capsule()
                    .fill(LinearGradient(colors: [Color.or.opacity(0), Color.or.opacity(0.85), Color.or.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: etape >= 2 ? 112 : 0, height: 0.75)
                    .padding(.top, 28)
                Text("Endry SA")
                    .font(.custom("Cinzel-SemiBold", fixedSize: 11.5))
                    .textCase(.uppercase)
                    .tracking(Self.approche)
                    // L'approche ajoute un blanc après la dernière lettre : compensé pour un centrage exact.
                    .padding(.leading, Self.approche)
                    .foregroundStyle(Color.or.opacity(0.9))
                    .padding(.top, 16)
                    .opacity(etape >= 2 ? 1 : 0)
            }
            // Centre optique, un peu au-dessus du centre géométrique.
            .offset(y: -28)
            .accessibilityHidden(true)

            VStack {
                Spacer()
                pied
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

extension SeuilMaison where Pied == EmptyView {
    init(etape: Int = 2) {
        self.init(etape: etape) { EmptyView() }
    }
}

/// Ouverture de l'app : le fond et le monogramme sortent du noir du lancement, le filet se trace, le nom apparaît,
/// puis l'ensemble s'efface. Sous lui, le verrou montre exactement la même composition : rien ne bouge.
/// Raccourcie si « Réduire les animations » ; jamais pendant les tests.
struct IntroMaison: View {
    var terminer: () -> Void
    @State private var etape = 0
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        SeuilMaison(etape: min(etape, 2))
            .opacity(etape >= 3 ? 0 : 1)
            .allowsHitTesting(etape < 3)
            .accessibilityHidden(true)
            .task {
                let rythme = reduireAnimations ? 0.5 : 1.0
                withAnimation(.easeOut(duration: 0.7 * rythme)) { etape = 1 }
                try? await Task.sleep(for: .seconds(0.5 * rythme))
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.8 * rythme)) { etape = 2 }
                try? await Task.sleep(for: .seconds(0.9 * rythme))
                withAnimation(.easeInOut(duration: 0.5)) { etape = 3 }
                try? await Task.sleep(for: .seconds(0.5))
                terminer()
            }
    }
}

/// Verrou Face ID : le seuil, et en bas un bouton de verre discret. Il n'apparaît pas pendant que Face ID regarde
/// (l'animation du système suffit), seulement si la reconnaissance a été annulée ou tarde.
struct EcranVerrou: View {
    @Environment(ModeleApp.self) private var modele
    @State private var proposer = false

    var body: some View {
        let verrou = modele.verrou
        let visible = !verrou.enCours && (proposer || verrou.erreur != nil)
        SeuilMaison {
            VStack(spacing: 14) {
                if let erreur = verrou.erreur {
                    Text(erreur)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.or.opacity(0.6))
                }
                Button {
                    Task { await verrou.deverrouiller() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: verrou.symboleMethode)
                            .font(.system(size: 17, weight: .regular))
                        Text("Déverrouiller")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(Color.orClair)
                    .padding(.horizontal, 24)
                    .frame(height: 50)
                    .verreMaison(Capsule(), interactif: true)
                    .contentShape(Capsule())
                }
                .buttonStyle(ActionPressee())
                .accessibilityLabel(Text("Déverrouiller avec \(verrou.nomMethode)"))
                .accessibilityIdentifier("bouton-deverrouiller")
            }
            .padding(.bottom, 36)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .animation(.easeInOut(duration: 0.3), value: visible)
        }
        .task {
            // Laisse à Face ID le temps de se lancer : pas de bouton qui clignote à l'ouverture.
            try? await Task.sleep(for: .seconds(1.2))
            proposer = true
        }
    }
}

/// Écran affiché quand l'app n'est plus au premier plan : aucun montant visible dans le sélecteur d'apps.
/// Même composition que le verrou et l'ouverture.
struct EcranConfidentialite: View {
    var body: some View {
        SeuilMaison()
            .accessibilityHidden(true)
    }
}
