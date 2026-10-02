import SwiftUI

/// « Mode devant le client » : masque les achats fournisseurs, les montants à payer et le matériel à refacturer,
/// pour montrer l'app à un client sans dévoiler les prix d'achat. Réglage gardé sur l'iPhone.
enum ModeDevantClient {
    static let cle = "mode-devant-le-client"
}

/// Bascule rapide (écran Entreprise, Réglages).
struct BasculeModeClient: View {
    @AppStorage(ModeDevantClient.cle) private var actif = false

    var body: some View {
        Toggle(isOn: $actif.animation(.endry)) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Mode devant le client", systemImage: actif ? "eye.slash.fill" : "eye")
                    .styleTexte(15, relativeTo: .subheadline, graisse: .semibold)
                    .foregroundStyle(Color.encre)
                Text("Masque les achats fournisseurs, les montants à payer et le matériel à refacturer.")
                    .styleTexte(12, relativeTo: .caption)
                    .foregroundStyle(Color.encreDouce)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.bronze)
        .padding(Espace.m)
        .surfaceCarte(rayon: 20)
        .sensoryFeedback(.selection, trigger: actif)
        .accessibilityIdentifier("bascule-mode-client")
    }
}

/// Rappel discret en haut de l'écran quand le mode est actif ; le toucher le désactive.
struct RappelModeClient: View {
    @AppStorage(ModeDevantClient.cle) private var actif = false

    var body: some View {
        if actif {
            Button {
                withAnimation(.endry) { actif = false }
            } label: {
                Label("Devant le client", systemImage: "eye.slash.fill")
                    .styleTexte(12, relativeTo: .caption, graisse: .semibold)
                    .foregroundStyle(Color.or)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color.espresso.opacity(0.85), in: Capsule())
                    .overlay(Capsule().stroke(Color.or.opacity(0.35), lineWidth: Espace.filet))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Mode devant le client actif"))
            .accessibilityHint(Text("Touchez pour réafficher les montants d’achat"))
            .accessibilityIdentifier("rappel-mode-client")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// À la place d'un bloc masqué.
struct BlocMasqueClient: View {
    var titre: String

    var body: some View {
        HStack(spacing: Espace.s) {
            Image(systemName: "eye.slash").foregroundStyle(Color.encrePale)
            Text("\(titre) : masqué devant le client")
                .styleTexte(13, relativeTo: .footnote)
                .foregroundStyle(Color.encrePale)
            Spacer(minLength: 0)
        }
        .padding(Espace.m)
        .background(Color.surfaceCreuse.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
