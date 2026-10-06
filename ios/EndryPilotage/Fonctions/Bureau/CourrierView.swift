import EndryKit
import SwiftUI

/// Le courrier reçu au bureau, partagé par l'accueil, le bureau et la liste : chargé une fois, gardé en mémoire
/// (la dernière liste s'affiche tout de suite, même sans réseau), rechargé à chaque ouverture.
@MainActor
@Observable
final class ModeleCourrier {
    static let partage = ModeleCourrier()
    private static let cle = "courrier.derniere-liste"

    private(set) var mails: [MailRecu] = []
    /// Une liste est affichable (fraîche ou gardée en mémoire).
    private(set) var charge = false
    private(set) var chargement = false
    /// Le PC ne connaît pas encore le courrier (version antérieure à la v1.12).
    private(set) var indisponible = false
    /// Dernier échec, en clair ; `nil` dès qu'un chargement réussit.
    private(set) var erreur: String?
    private var relances = 0

    init() {
        if let donnees = UserDefaults.standard.data(forKey: Self.cle),
           let liste = try? JSONDecoder().decode(ListeMails.self, from: donnees) {
            mails = liste.mails
            charge = true
        }
    }

    func charger(api: (any EndryAPI)?) async {
        guard let api, !chargement else { return }
        chargement = true
        do throws(ErreurAPI) {
            let donnees = try await api.envoyer(.mails())
            mails = try api.decoder(ListeMails.self, depuis: donnees).mails
            UserDefaults.standard.set(donnees, forKey: Self.cle)
            charge = true
            indisponible = false
            erreur = nil
        } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
            indisponible = true
        } catch {
            erreur = error.message
        }
        chargement = false
        // Le PC complète les pièces jointes en arrière-plan : on repasse une ou deux fois les chercher.
        if erreur == nil, relances < 2, mails.contains(where: { $0.pieces == nil }) {
            relances += 1
            try? await Task.sleep(for: .seconds(3))
            await charger(api: api)
        } else {
            relances = 0
        }
    }
}

/// Courrier reçu, en évidence sur l'accueil et en tête du bureau : les trois derniers e-mails, toucher pour tout voir.
struct CarteCourrier: View {
    @Environment(ModeleApp.self) private var app
    @State private var ouvert = false
    private var modele: ModeleCourrier { .partage }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TitreSection(titre: "Courrier reçu", lien: "Tout voir", action: { ouvert = true })
            Button { ouvert = true } label: {
                VStack(spacing: 0) {
                    if modele.mails.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.signal)
                                .frame(width: 20)
                            Text(etatVide)
                                .styleTexte(15, relativeTo: .subheadline)
                                .foregroundStyle(Color.encreDouce)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 54)
                    } else {
                        let derniers = Array(modele.mails.prefix(3))
                        ForEach(Array(derniers.enumerated()), id: \.element.id) { index, mail in
                            ligne(mail)
                            if index < derniers.count - 1 {
                                Rectangle().fill(Color.filet).frame(height: Espace.filet)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tuileMaison(rayon: 22)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(ActionPressee())
            .accessibilityHint(Text("Ouvre les e-mails reçus et leurs pièces jointes"))
            .accessibilityIdentifier("carte-courrier")
        }
        .sheet(isPresented: $ouvert) { CourrierView() }
        .task { await modele.charger(api: app.session.api) }
    }

    private var etatVide: String {
        if modele.indisponible { return "Le courrier arrive avec la prochaine mise à jour du PC." }
        if let erreur = modele.erreur { return erreur }
        return modele.charge ? "Aucun e-mail reçu pour l’instant." : "Chargement du courrier…"
    }

    private func ligne(_ mail: MailRecu) -> some View {
        let avecPiece = !(mail.pieces ?? []).isEmpty
        return HStack(spacing: 10) {
            Image(systemName: avecPiece ? "paperclip" : "envelope")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(avecPiece ? Color.signal : Color.encrePale)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(mail.expediteur)
                    .styleTexte(15, relativeTo: .subheadline, graisse: .semibold)
                    .foregroundStyle(Color.encre)
                    .lineLimit(1)
                Text(mail.objet)
                    .styleTexte(13.5, relativeTo: .footnote)
                    .foregroundStyle(Color.encreDouce)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(mail.dateLisible)
                .font(Police.mono(11.5))
                .foregroundStyle(Color.encreDouce)
                .lineLimit(1)
        }
        .frame(minHeight: 56)
    }
}

/// Courrier reçu au bureau : les derniers e-mails, ce que l'assistant en a fait, et leurs pièces jointes à ouvrir
/// d'un toucher (PDF, plans, photos). Lecture seule : répondre reste une demande au bureau.
struct CourrierView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @State private var recherche = ""
    @State private var avecPieces = false
    @State private var documents = DocumentsConversation()
    private var modele: ModeleCourrier { .partage }

    private var affiches: [MailRecu] {
        modele.mails.filter { $0.correspond(recherche) && (!avecPieces || !($0.pieces ?? []).isEmpty) }
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

                    if let erreur = modele.erreur {
                        echec(erreur)
                    }
                    if modele.indisponible {
                        message("Le courrier n’est pas encore disponible : le PC du bureau doit être à jour et allumé.")
                    } else if !modele.charge {
                        if modele.erreur == nil {
                            HStack {
                                Spacer()
                                ProgressView().tint(Color.signal)
                                Spacer()
                            }
                            .padding(.top, Espace.xl)
                        }
                    } else if affiches.isEmpty {
                        message(modele.mails.isEmpty ? "Aucun e-mail reçu pour l’instant." : "Aucun e-mail ne correspond.")
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
            .refreshable { await modele.charger(api: app.session.api) }
            .navigationTitle("Courrier reçu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
            .navigationDestination(for: MailRecu.self) { DetailMailView(mail: $0) }
        }
        .environment(documents)
        .quickLookPreview(Binding(get: { documents.apercu }, set: { documents.apercu = $0 }))
        .task { await modele.charger(api: app.session.api) }
    }

    private func message(_ texte: String) -> some View {
        Text(texte)
            .styleTexte(15, relativeTo: .subheadline)
            .foregroundStyle(Color.encreDouce)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Espace.l)
    }

    /// Le chargement a échoué : on le dit, on garde la dernière liste connue et on propose de réessayer.
    private func echec(_ erreur: String) -> some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            Text(erreur)
                .styleTexte(14, relativeTo: .subheadline)
                .foregroundStyle(Color.rouille)
                .fixedSize(horizontal: false, vertical: true)
            if modele.charge {
                Text("Liste gardée en mémoire : elle peut dater.")
                    .styleTexte(13, relativeTo: .footnote)
                    .foregroundStyle(Color.encreDouce)
            }
            Button {
                Task { await modele.charger(api: app.session.api) }
            } label: {
                Label(modele.chargement ? "Nouvel essai…" : "Réessayer", systemImage: "arrow.clockwise")
                    .styleTexte(14, graisse: .semibold)
                    .foregroundStyle(Color.encre)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.surfaceCreuse, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(modele.chargement)
            .accessibilityIdentifier("reessayer-courrier")
        }
        .padding(Espace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileMaison(rayon: 16)
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
}

/// Un e-mail reçu : expéditeur, résumé du bureau, pièces jointes (aperçu, enregistrement), puis le texte.
struct DetailMailView: View {
    @Environment(ModeleApp.self) private var app
    @State private var mail: MailRecu
    @State private var chargement = false
    @State private var erreur: String?

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
                    HStack {
                        Spacer()
                        ProgressView().tint(Color.signal)
                        Spacer()
                    }
                } else if let erreur {
                    VStack(alignment: .leading, spacing: Espace.xs) {
                        Text(erreur)
                            .styleTexte(14, relativeTo: .subheadline)
                            .foregroundStyle(Color.rouille)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Réessayer") { Task { await charger() } }
                            .foregroundStyle(Color.encre)
                    }
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
        guard mail.contenu == nil, !chargement, let api = app.session.api else { return }
        chargement = true
        defer { chargement = false }
        do throws(ErreurAPI) {
            mail = try await api.mail(mail.id)
            erreur = nil
        } catch {
            erreur = error.message
        }
    }
}
