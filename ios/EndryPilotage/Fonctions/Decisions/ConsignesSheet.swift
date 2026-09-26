import EndryKit
import SwiftUI

/// Feuille « Corriger » ou « Répondre » : dictée fr-CH ou texte, envoyée comme `consignes`.
struct ConsignesSheet: View {
    enum Mode {
        case corriger, repondre

        var titre: String { self == .corriger ? "Corriger" : "Répondre" }
        var invite: String {
            self == .corriger ? "Que faut-il changer ? Ex. « Compter 6 h 30 au lieu de 7 h. »" : "Votre réponse, en quelques mots."
        }
        var bouton: String { self == .corriger ? "Envoyer les consignes" : "Envoyer la réponse" }
    }

    var mode: Mode
    var carte: Carte
    var envoyer: @MainActor (String) async -> Bool

    @Environment(\.dismiss) private var fermer
    @State private var texte = ""
    @State private var base = ""
    @State private var dictee = Dictee()
    @State private var enCours = false
    @FocusState private var focus: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Espace.m) {
                VStack(alignment: .leading, spacing: Espace.xs) {
                    GenreView(genre: carte.genre)
                    Text(carte.titre).styleTitre(20, relativeTo: .title3).foregroundStyle(Color.encre)
                    if mode == .repondre, !carte.motif.isEmpty {
                        Text(carte.motif).styleTexte(15, relativeTo: .subheadline).foregroundStyle(Color.encreDouce)
                    }
                }

                ZStack(alignment: .topLeading) {
                    if texte.isEmpty {
                        Text(mode.invite)
                            .styleTexte(16)
                            .foregroundStyle(Color.encrePale)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $texte)
                        .styleTexte(16)
                        .scrollContentBackground(.hidden)
                        .focused($focus)
                        .accessibilityIdentifier("champ-consignes")
                }
                .padding(Espace.s)
                .frame(minHeight: 140)
                .background(Color.surfaceCreuse.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: Espace.m) {
                    Button {
                        Task {
                            if !dictee.ecoute { base = texte.isEmpty ? "" : texte + " " }
                            await dictee.basculer()
                        }
                    } label: {
                        HStack(spacing: Espace.xs) {
                            Image(systemName: dictee.ecoute ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 28))
                                .symbolRenderingMode(.hierarchical)
                                .contentTransition(.symbolEffect(.replace))
                            Text(dictee.ecoute ? "Arrêter" : "Dicter")
                                .styleTexte(15, relativeTo: .subheadline, graisse: .semibold)
                        }
                        .foregroundStyle(Color.bronze)
                    }
                    .accessibilityIdentifier("dicter-consignes")

                    if dictee.ecoute {
                        FormeOnde(historique: Array(dictee.historique.suffix(16)), active: true)
                            .frame(height: 24)
                            .transition(.opacity)
                    }
                    Spacer()
                }

                if case .refuse(let message) = dictee.etat {
                    Text(message).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.rouille)
                } else if case .indisponible(let message) = dictee.etat {
                    Text(message).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.rouille)
                }

                Spacer(minLength: 0)

                Button {
                    Task {
                        dictee.arreter()
                        enCours = true
                        let ok = await envoyer(texte)
                        enCours = false
                        if ok { fermer() }
                    }
                } label: {
                    HStack {
                        if enCours { ProgressView().tint(Color.fond) }
                        Text(mode.bouton)
                    }
                }
                .buttonStyle(BoutonPrincipal())
                .disabled(texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || enCours)
                .accessibilityIdentifier("envoyer-consignes")
            }
            .padding(Espace.l)
            .background(Color.fond)
            .navigationTitle(mode.titre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dictee.arreter()
                        fermer()
                    }
                }
            }
            .onChange(of: dictee.transcription) { _, nouvelle in
                if !nouvelle.isEmpty { texte = base + nouvelle }
            }
            .onAppear { focus = true }
            .onDisappear { dictee.arreter() }
            .animation(.snappy, value: dictee.ecoute)
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Espace.rayon)
        .presentationBackground(Color.fond)
    }
}
