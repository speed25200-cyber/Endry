import EndryKit
import SwiftUI

/// Recherche globale : décisions, chantiers, factures, offres, fournisseurs et conversation, instantanément,
/// dans ce que l'iPhone connaît déjà (rien ne part au réseau pendant la frappe).
struct RechercheView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @AppStorage(ModeDevantClient.cle) private var devantClient = false
    @State private var requete = ""
    @FocusState private var focus: Bool

    private var resultats: [ResultatRecherche] {
        RechercheGlobale.chercher(
            requete,
            cartes: app.decisions?.cartes ?? [],
            chantiers: app.chantiers?.tous ?? [],
            argent: app.argent?.argent,
            messages: app.conversation?.messages ?? [],
            // Devant le client : ni fournisseurs ni achats.
            fournisseurs: !devantClient
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if requete.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        Label("Un client, un chantier, un numéro de facture ou d’offre, un mot de la conversation…",
                              systemImage: "magnifyingglass")
                            .styleTexte(14).foregroundStyle(Color.encreDouce)
                    }
                } else if resultats.isEmpty {
                    ContentUnavailableView.search(text: requete)
                } else {
                    let liste = resultats
                    ForEach(ResultatRecherche.Genre.allCases, id: \.self) { genre in
                        let duGenre = liste.filter { $0.genre == genre }
                        if !duGenre.isEmpty {
                            Section(genre.libelle) {
                                ForEach(duGenre) { resultat in
                                    Button { ouvrir(resultat) } label: { LigneResultat(resultat: resultat) }
                                        .buttonStyle(.plain)
                                        .disabled(resultat.cible == .aucune)
                                        .accessibilityIdentifier("resultat-\(resultat.id)")
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FondAmbiant())
            .searchable(text: $requete, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Rechercher"))
            .searchFocused($focus)
            .navigationTitle("Rechercher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { fermer() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .onAppear { focus = true }
        .accessibilityIdentifier("recherche")
    }

    private func ouvrir(_ resultat: ResultatRecherche) {
        switch resultat.cible {
        case .decision(let reference):
            fermer()
            app.ouvrir(reference: reference)
        case .chantier(let id):
            fermer()
            app.ouvrirChantier(id)
        case .document(let chemin, let nom):
            Task { await app.documents.ouvrir(chemin, nom: nom, api: app.session.api) }
        case .conversation:
            fermer()
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                app.ouvrirConversation()
            }
        case .aucune:
            break
        }
    }
}

private struct LigneResultat: View {
    var resultat: ResultatRecherche

    var body: some View {
        HStack(spacing: Espace.s) {
            Image(systemName: icone)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.bronze)
                .frame(width: 34, height: 34)
                .background(Color.or.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(resultat.titre).styleTexte(15, relativeTo: .subheadline, graisse: .semibold)
                    .foregroundStyle(Color.encre).lineLimit(2)
                Text(resultat.detail).styleTexte(12, relativeTo: .caption)
                    .foregroundStyle(Color.encrePale).lineLimit(1)
            }
            Spacer(minLength: 0)
            if resultat.cible != .aucune {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.encrePale)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var icone: String {
        switch resultat.genre {
        case .decision: "checkmark.seal"
        case .chantier: "hammer"
        case .facture: "doc.text"
        case .offre: "doc.richtext"
        case .fournisseur: "shippingbox"
        case .message: "text.bubble"
        }
    }
}
