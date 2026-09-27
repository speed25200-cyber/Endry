import EndryKit
import SwiftUI

/// Appareils connectés (v1.1) : chaque iPhone ou iPad a son propre jeton, révocable à distance.
struct AppareilsView: View {
    @Environment(ModeleApp.self) private var app
    @State private var appareils: [Appareil] = []
    @State private var etat: Etat = .chargement
    @State private var aRetirer: Appareil?

    private enum Etat: Equatable { case chargement, pret, indisponible }

    var body: some View {
        List {
            Section {
                switch etat {
                case .chargement:
                    ForEach(0..<2, id: \.self) { _ in Squelette(hauteur: 44) }
                case .indisponible:
                    Text("Le serveur du bureau ne gère pas encore un jeton par appareil. Mettez l’assistant du PC à jour (API v1.1).")
                        .styleTexte(15, relativeTo: .subheadline)
                        .foregroundStyle(Color.encreDouce)
                case .pret:
                    ForEach(appareils) { appareil in
                        LigneAppareil(appareil: appareil)
                            .swipeActions {
                                if !appareil.actuel {
                                    Button("Déconnecter", role: .destructive) { aRetirer = appareil }
                                }
                            }
                            .accessibilityAction(named: Text("Déconnecter")) {
                                if !appareil.actuel { aRetirer = appareil }
                            }
                    }
                }
            } footer: {
                Text("Un appareil perdu ? Balayez-le vers la gauche : son jeton ne fonctionnera plus.")
            }
            .listRowBackground(Color.surface)

            Section {
                Button(role: .destructive) {
                    Task { await app.deconnecterCetAppareil() }
                } label: {
                    Label("Déconnecter cet iPhone", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .listRowBackground(Color.surface)
        }
        .scrollContentBackground(.hidden)
        .background(FondAmbiant())
        .navigationTitle("Appareils")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await charger() }
        .task { await charger() }
        .confirmationDialog("Déconnecter « \(aRetirer?.nom ?? "")» ?", isPresented: Binding(
            get: { aRetirer != nil }, set: { if !$0 { aRetirer = nil } }
        ), titleVisibility: .visible) {
            Button("Déconnecter", role: .destructive) {
                if let appareil = aRetirer { Task { await retirer(appareil) } }
            }
        } message: {
            Text("Cet appareil devra recevoir un nouveau lien d’accès pour se reconnecter.")
        }
        .sensoryFeedback(.success, trigger: appareils.count) { ancien, nouveau in nouveau < ancien }
    }

    private func charger() async {
        guard let api = app.session.api else { return }
        do {
            let liste = try await api.appareils()
            withAnimation(.endry) {
                appareils = liste
                etat = .pret
            }
        } catch {
            etat = .indisponible
        }
    }

    private func retirer(_ appareil: Appareil) async {
        guard let api = app.session.api else { return }
        do {
            try await api.supprimerAppareil(appareil.id)
            withAnimation(.endry) { appareils.removeAll { $0.id == appareil.id } }
            app.toast = Toast("« \(appareil.nom) » est déconnecté : son jeton est révoqué.")
        } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
            app.toast = Toast("Le PC ne permet pas encore de révoquer un appareil à distance.", style: .info)
        } catch {
            app.toast = Toast(error.message, style: .erreur)
        }
        aRetirer = nil
    }
}

struct LigneAppareil: View {
    var appareil: Appareil

    var body: some View {
        HStack(spacing: Espace.s) {
            Image(systemName: appareil.modele?.lowercased().contains("ipad") == true ? "ipad" : "iphone")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.bronze)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(appareil.nom).styleTexte(15, relativeTo: .body, graisse: .medium).foregroundStyle(Color.encre)
                Text([appareil.modele, appareil.dernierPassage.map { "vu \(DateEndry.ilYa($0))" }].compactMap { $0 }.joined(separator: " · "))
                    .styleTexte(13, relativeTo: .caption)
                    .foregroundStyle(Color.encrePale)
            }
            Spacer()
            if appareil.actuel {
                Pastille(texte: "Cet iPhone", couleur: .sauge)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
