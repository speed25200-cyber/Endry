import SwiftUI
import EndryKit

/// Accès directeur (v1.12) : la même app, avec d'autres droits.
/// L'écran montre les montants (comme l'écran Argent du patron) et, en bas, « Poser une question » :
/// la conversation de l'app (écrire, dicter, photo, scan) et l'assistant vocal, servis en lecture seule par le PC.
/// Ni décisions, ni courrier, ni documents : le jeton de directeur ne les ouvre pas.
struct EspaceDirecteur: View {
    @Environment(ModeleApp.self) private var app
    @State private var deconnexion = false

    var body: some View {
        @Bindable var app = app
        ZStack {
            Color.fond.ignoresSafeArea()
            if let argent = app.argent {
                ArgentView(modele: argent).id(ObjectIdentifier(argent))
            } else {
                ProgressView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { barre }
        .toast($app.toast)
        .apercuDocuments()
        .fullScreenCover(isPresented: $app.conversationPresentee) {
            if let modele = app.conversation { ConversationView(modele: modele) }
        }
        .fullScreenCover(isPresented: $app.assistantPresente) {
            VueAssistantVocal().apercuDocuments()
        }
        .confirmationDialog("Se déconnecter de cet iPhone ?", isPresented: $deconnexion, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) { Task { await app.deconnecter() } }
            Button("Annuler", role: .cancel) {}
        }
    }

    /// « Poser une question » reste sous les montants, sur le même écran.
    private var barre: some View {
        HStack(spacing: Espace.s) {
            Button { app.conversationPresentee = true } label: {
                HStack(spacing: Espace.s) {
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.bronze)
                        .frame(width: 44, height: 44)
                        .background(Color.or.opacity(0.18), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Poser une question").styleTexte(16, graisse: .semibold).foregroundStyle(Color.encre)
                        Text("Entreprise, technique, photo d’une pièce")
                            .styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Espace.s)
                .surfaceCarte(rayon: 20)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("poser-une-question")

            Button { app.ouvrirAssistant() } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.bronze)
                    .frame(width: 52, height: 52)
                    .surfaceCarte(rayon: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Poser une question à la voix"))
            .accessibilityIdentifier("question-vocale")

            Button { deconnexion = true } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.encreDouce)
                    .frame(width: 44, height: 52)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Se déconnecter"))
        }
        .padding(.horizontal, Espace.bord)
        .padding(.top, Espace.s)
        .padding(.bottom, Espace.xs)
        .background(Color.fond)
    }
}
