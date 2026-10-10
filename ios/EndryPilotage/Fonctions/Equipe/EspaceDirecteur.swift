import SwiftUI
import EndryKit

/// Accès directeur (v1.12) : la même app, avec d'autres droits.
/// En haut : les montants ou les chantiers en cours. En bas, toujours visibles : « Dicter une note » (consignée, puis
/// transformée en décisions par le secrétariat) et « Poser une question » (écrit, photo, scan, voix ; lecture seule).
/// Ni décisions, ni courrier, ni documents : le jeton de directeur ne les ouvre pas.
struct EspaceDirecteur: View {
    @Environment(ModeleApp.self) private var app
    @State private var ecran = Ecran.montants
    @State private var note = false
    @State private var deconnexion = false

    enum Ecran: Hashable { case montants, chantiers }

    var body: some View {
        @Bindable var app = app
        ZStack {
            Color.fond.ignoresSafeArea()
            switch ecran {
            case .montants:
                if let argent = app.argent {
                    ArgentView(modele: argent).id(ObjectIdentifier(argent))
                } else {
                    ProgressView()
                }
            case .chantiers:
                if let chantiers = app.chantiers {
                    ChantiersView(modele: chantiers).id(ObjectIdentifier(chantiers))
                } else {
                    ProgressView()
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { choixEcran }
        .safeAreaInset(edge: .bottom, spacing: 0) { barre }
        .toast($app.toast)
        .apercuDocuments()
        .sheet(isPresented: $note) { NoteDirecteurView() }
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

    private var choixEcran: some View {
        HStack(spacing: Espace.s) {
            Picker("Écran", selection: $ecran) {
                Text("Montants").tag(Ecran.montants)
                Text("Chantiers").tag(Ecran.chantiers)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("ecran-directeur")

            Button { deconnexion = true } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.encreDouce)
                    .frame(width: 40, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Se déconnecter"))
        }
        .padding(.horizontal, Espace.bord)
        .padding(.vertical, Espace.xs)
        .background(Color.fond)
    }

    /// Les deux gestes du directeur restent sous les chiffres, sur le même écran.
    private var barre: some View {
        VStack(spacing: Espace.xs) {
            Button { note = true } label: {
                HStack(spacing: Espace.s) {
                    Image(systemName: "mic.badge.plus").font(.system(size: 20, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Dicter une note").styleTexte(17, graisse: .semibold)
                        Text("Ce qui s’est dit ou décidé : le secrétariat s’en occupe")
                            .styleTexte(12.5, relativeTo: .footnote)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(BoutonPrincipal())
            .accessibilityIdentifier("dicter-une-note")

            HStack(spacing: Espace.s) {
                Button { app.conversationPresentee = true } label: {
                    HStack(spacing: Espace.s) {
                        Image(systemName: "questionmark.bubble.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.bronze)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Poser une question").styleTexte(16, graisse: .semibold).foregroundStyle(Color.encre)
                            Text("Entreprise, technique, photo d’une pièce")
                                .styleTexte(12.5, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Espace.s)
                    .surfaceCarte(rayon: 18)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("poser-une-question")

                Button { app.ouvrirAssistant() } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.bronze)
                        .frame(width: 52, height: 52)
                        .surfaceCarte(rayon: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Poser une question à la voix"))
                .accessibilityIdentifier("question-vocale")
            }
        }
        .padding(.horizontal, Espace.bord)
        .padding(.top, Espace.s)
        .padding(.bottom, Espace.xs)
        .background(Color.fond)
    }
}

/// Note vocale du directeur : il parle, le texte s'écrit, il relit et envoie.
/// Le PC consigne la note, puis le secrétariat prépare les décisions qui en découlent (accès principal).
struct NoteDirecteurView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @State private var dictee = Dictee()
    @State private var texte = ""
    @State private var base = ""
    @State private var envoi = false
    @State private var erreur: String?
    @State private var confirmation: String?
    @FocusState private var clavier: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.m) {
                    if let confirmation {
                        Label(confirmation, systemImage: "checkmark.circle.fill")
                            .styleTexte(16, graisse: .semibold)
                            .foregroundStyle(Color.encre)
                            .padding(.top, Espace.m)
                        Text("Vous n’avez rien d’autre à faire : les décisions à prendre apparaîtront dans l’accès du secrétariat.")
                            .styleTexte(14).foregroundStyle(Color.encreDouce)
                        Button("Dicter une autre note") {
                            self.confirmation = nil
                            texte = ""
                            base = ""
                        }
                        .buttonStyle(BoutonPrincipal())
                    } else {
                        MicroAnime(ecoute: dictee.ecoute, niveau: dictee.niveau, historique: dictee.historique) {
                            Task {
                                if !dictee.ecoute {
                                    clavier = false
                                    base = texte.isEmpty || texte.hasSuffix(" ") ? texte : texte + " "
                                }
                                await dictee.basculer()
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Group {
                            switch dictee.etat {
                            case .ecoute:
                                Text("J’écoute… Touchez le micro pour arrêter.")
                            case .refuse(let m), .indisponible(let m):
                                Text(m).foregroundStyle(Color.rouille)
                            case .repos:
                                Text("Touchez le micro et racontez : qui, quel chantier, ce qui a été dit ou décidé.")
                            }
                        }
                        .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                        .foregroundStyle(Color.encreDouce)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                        TextEditor(text: $texte)
                            .focused($clavier)
                            .styleTexte(16)
                            .frame(minHeight: 150)
                            .scrollContentBackground(.hidden)
                            .padding(Espace.s)
                            .surfaceCarte(rayon: 16)
                            .accessibilityIdentifier("texte-note")

                        if let erreur { Label(erreur, systemImage: "exclamationmark.triangle").foregroundStyle(Color.rouille) }

                        Button {
                            Task { await envoyer() }
                        } label: {
                            HStack(spacing: Espace.xs) {
                                if envoi { ProgressView().tint(Color.fond) }
                                Text(envoi ? "Envoi…" : "Consigner la note")
                            }
                        }
                        .buttonStyle(BoutonPrincipal())
                        .disabled(envoi || texte.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                        .accessibilityIdentifier("consigner-note")
                    }
                }
                .padding(Espace.bord)
                .verrouillerLargeur()
            }
            .background(FondAmbiant())
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { fermer() } } }
        }
        .onChange(of: dictee.transcription) { _, nouvelle in
            if !nouvelle.isEmpty { texte = base + nouvelle }
        }
        .onDisappear { dictee.arreter() }
    }

    private func envoyer() async {
        guard let api = app.session.api else { return }
        dictee.arreter()
        envoi = true
        erreur = nil
        do throws(ErreurAPI) {
            let reponse = try await api.consignerNoteDirecteur(texte.trimmingCharacters(in: .whitespacesAndNewlines))
            confirmation = reponse.message ?? "Note consignée."
        } catch {
            erreur = error.message
        }
        envoi = false
    }
}
