import EndryKit
import SwiftUI

/// Réglages : serveur, Face ID, notifications, démo, déconnexion.
struct ReglagesView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @State private var confirmationDeconnexion = false
    @State private var notificationsActives = false

    var body: some View {
        @Bindable var verrou = app.verrou
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Espace.m) {
                        LogoEndry(taille: 44)
                            .padding(6)
                            .background(Color.espresso, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.session.entreprise).styleTitre(18, relativeTo: .headline)
                            Text(app.session.hoteAffiche ?? "—")
                                .font(Police.reference(12))
                                .foregroundStyle(Color.encreDouce)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, Espace.xxs)

                    Button {
                        fermer()
                        app.connexionPresentee = true
                    } label: {
                        Label("Coller un nouveau lien", systemImage: "link.badge.plus")
                    }
                } header: {
                    Text("Serveur")
                } footer: {
                    Text("L’adresse du serveur vient du lien d’accès. Si elle change (tunnel provisoire, puis réseau privé), collez simplement le nouveau lien.")
                }

                Section("Sécurité") {
                    Toggle(isOn: $verrou.actif) {
                        Label("Verrouiller avec \(app.verrou.nomMethode)", systemImage: "faceid")
                    }
                    .tint(Color.vertControle)
                }

                if !app.session.estDemo {
                    Section {
                        if notificationsActives {
                            Label("Notifications activées", systemImage: "bell.badge")
                                .foregroundStyle(Color.vertControle)
                        } else {
                            Button {
                                Task {
                                    notificationsActives = await DelegueApp.demanderAutorisation()
                                }
                            } label: {
                                Label("Activer les notifications", systemImage: "bell")
                            }
                        }
                    } header: {
                        Text("Notifications")
                    } footer: {
                        Text("Une notification signale une nouvelle décision ; la toucher ouvre la carte.")
                    }
                }

                if app.session.estDemo {
                    Section {
                        Button {
                            Task {
                                await app.session.reinitialiserDemo()
                                await app.decisions?.charger()
                                fermer()
                            }
                        } label: {
                            Label("Recommencer la démo", systemImage: "arrow.counterclockwise")
                        }
                    } header: {
                        Text("Mode démo")
                    } footer: {
                        Text("Données fictives : rien n’est envoyé, aucun serveur n’est contacté.")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmationDeconnexion = true
                    } label: {
                        Label(app.session.estDemo ? "Quitter la démo" : "Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityIdentifier("se-deconnecter")
                }

                Section("À propos") {
                    LabeledContent("Version", value: version)
                    LabeledContent("Polices", value: "Inter, Inter Tight (OFL)")
                    Text("Aucun outil de suivi ni publicité. Le jeton est rangé uniquement dans le trousseau de cet iPhone.")
                        .styleTexte(13, relativeTo: .footnote)
                        .foregroundStyle(Color.encreDouce)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fond)
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { fermer() }
                }
            }
            .confirmationDialog(
                app.session.estDemo ? "Quitter la démo ?" : "Se déconnecter ?",
                isPresented: $confirmationDeconnexion,
                titleVisibility: .visible
            ) {
                Button(app.session.estDemo ? "Quitter" : "Se déconnecter", role: .destructive) {
                    Task {
                        fermer()
                        await app.deconnecter()
                    }
                }
            } message: {
                Text("Le jeton et les données en cache seront effacés de cet iPhone.")
            }
            .task {
                notificationsActives = await DelegueApp.autorisationDejaAccordee()
            }
        }
        .presentationCornerRadius(Espace.rayon)
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}
