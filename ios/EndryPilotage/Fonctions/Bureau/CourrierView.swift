import EndryKit
import SwiftUI

/// Courrier reçu au bureau : les derniers e-mails, ce que l'assistant en a fait, et leurs pièces jointes à ouvrir
/// d'un toucher (PDF, plans, photos). Lecture seule : répondre reste une demande au bureau.
struct CourrierView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @State private var mails: [MailRecu] = []
    @State private var charge = false
    @State private var chargement = false
    @State private var indisponible = false
    @State private var recherche = ""
    @State private var avecPieces = false
    @State private var documents = DocumentsConversation()

    private var affiches: [MailRecu] {
        mails.filter { $0.correspond(recherche) && (!avecPieces || !($0.pieces ?? []).isEmpty) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Espace.s) {
                    Toggle(isOn: $avecPieces) {
                        Label("Avec pièce jointe seulement", systemImage: "paperclip")
                            .styleTexte(15, relativeTo: .subheadline)
                            .foregroundStyle(Color.encre)
                    }
                    .tint(Color.signal)
                    .padding(.vertical, Espace.xs)
                    .accessibilityIdentifier("filtre-pieces-courrier")

                    if indisponible {
                        message("Le courrier n’est pas encore disponible : le PC du bureau doit être à jour et allumé.")
                    } else if !charge {
                        HStack { Spacer(); ProgressView().tint(Color.signal); Spacer() }
                            .padding(.top, Espace.xl)
                    } else if affiches.isEmpty {
                        message(mails.isEmpty ? "Aucun e-mail reçu pour l’instant." : "Aucun e-mail ne correspond.")
                    } else {
                        ForEach(affiches) { mail in
                            NavigationLink(value: mail) { ligne(mail) }
                                .buttonStyle(ActionPressee())
                                .accessibilityIdentifier("mail-\(mail.id)")
                        }
                    }
                }
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, Espace.xl)
            }
            .background(FondAmbiant())
            .searchable(text: $recherche, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Expéditeur, objet, pièce jointe")
            .refreshable { await charger() }
            .navigationTitle("Courrier reçu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
            .navigationDestination(for: MailRecu.self) { DetailMailView(mail: $0) }
        }
        .environment(documents)
        .quickLookPreview(Binding(get: { documents.apercu }, set: { documents.apercu = $0 }))
        .task { await charger() }
    }

    private func message(_ texte: String) -> some View {
        Text(texte)
            .styleTexte(15, relativeTo: .subheadline)
            .foregroundStyle(Color.encreDouce)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Espace.l)
    }

    private func ligne(_ mail: MailRecu) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: Espace.xs) {
                Text(mail.expediteur)
                    .styleTexte(15, relativeTo: .subheadline, graisse: .semibold)
                    .foregroundStyle(Color.encre)
                    .lineLimit(1)
                Spacer(minLength: Espace.xs)
                Text(mail.dateLisible)
                    .font(Police.mono(11.5))
                    .foregroundStyle(Color.encreDouce)
                    .lineLimit(1)
            }
            Text(mail.objet)
                .styleTexte(15, relativeTo: .subheadline, graisse: .medium)
                .foregroundStyle(Color.encre)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let resume = mail.resume {
                Text(resume)
                    .styleTexte(13, relativeTo: .footnote)
                    .foregroundStyle(Color.encreDouce)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            if let pieces = mail.pieces, !pieces.isEmpty {
                Label(pieces.count == 1 ? pieces[0].nom : "\(pieces.count) pièces jointes", systemImage: "paperclip")
                    .font(Police.mono(11.5))
                    .foregroundStyle(Color.signal)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .padding(Espace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileMaison(rayon: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func charger() async {
        guard let api = app.session.api, !chargement else { return }
        chargement = true
        defer { chargement = false }
        do throws(ErreurAPI) {
            mails = try await api.mails()
            indisponible = false
            charge = true
        } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
            indisponible = true
        } catch {
            charge = true
            app.toast = Toast(error.message, style: .erreur)
        }
    }
}

/// Un e-mail reçu : expéditeur, résumé du bureau, pièces jointes (aperçu, enregistrement), puis le texte.
struct DetailMailView: View {
    @Environment(ModeleApp.self) private var app
    @State private var mail: MailRecu
    @State private var chargement = false

    init(mail: MailRecu) {
        _mail = State(initialValue: mail)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espace.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mail.objet)
                        .styleTitre(22, relativeTo: .title2)
                        .foregroundStyle(Color.encre)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(mail.deNom.map { "\($0) · \(mail.de)" } ?? mail.de)
                        .styleTexte(14, relativeTo: .subheadline)
                        .foregroundStyle(Color.encreDouce)
                        .textSelection(.enabled)
                    Text([mail.dateLisible, mail.categorieLisible ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Police.mono(11.5))
                        .foregroundStyle(Color.encreDouce)
                }
                .padding(.top, Espace.s)

                if let resume = mail.resume {
                    VStack(alignment: .leading, spacing: Espace.xs) {
                        Text("Ce que le bureau en a fait").etiquetteMaison()
                        Text(resume)
                            .styleTexte(15, relativeTo: .subheadline)
                            .foregroundStyle(Color.encre)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let pieces = mail.pieces, !pieces.isEmpty {
                    VStack(alignment: .leading, spacing: Espace.xs) {
                        Text(pieces.count == 1 ? "Pièce jointe" : "Pièces jointes").etiquetteMaison()
                        CartesDocuments(pieces: pieces)
                    }
                    .accessibilityIdentifier("pieces-mail")
                }

                if let contenu = mail.contenu, !contenu.isEmpty {
                    VStack(alignment: .leading, spacing: Espace.xs) {
                        Text("Message").etiquetteMaison()
                        Text(contenu)
                            .styleTexte(15, relativeTo: .subheadline)
                            .foregroundStyle(Color.encre)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if chargement {
                    HStack { Spacer(); ProgressView().tint(Color.signal); Spacer() }
                }
            }
            .padding(.horizontal, Espace.bord)
            .padding(.bottom, Espace.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(FondAmbiant())
        .navigationTitle("E-mail")
        .navigationBarTitleDisplayMode(.inline)
        .task { await charger() }
    }

    private func charger() async {
        guard mail.contenu == nil, let api = app.session.api else { return }
        chargement = true
        defer { chargement = false }
        do throws(ErreurAPI) {
            mail = try await api.mail(mail.id)
        } catch {
            app.toast = Toast(error.message, style: .erreur)
        }
    }
}
