import SwiftUI
import EndryKit

/// Accès directeur (v1.12) : la même app, avec d'autres droits.
/// Trois écrans sous un dock de verre : l'accueil (les chiffres du jour, les deux gestes du directeur, un aperçu des
/// chantiers et de ses dernières notes), les montants, les chantiers.
/// « Dicter une note » : consignée, puis transformée en décisions par le secrétariat (accès principal).
/// « Poser une question » : écrit, photo, scan ou voix ; le PC répond en lecture seule.
/// Ni décisions, ni courrier, ni documents : le jeton de directeur ne les ouvre pas.
struct EspaceDirecteur: View {
    @Environment(ModeleApp.self) private var app
    @State private var ecran = Ecran.accueil
    @State private var note = false
    @State private var deconnexion = false
    @State private var notes: [NoteDirecteur] = []

    enum Ecran: Hashable { case accueil, montants, chantiers }

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .bottom) {
            Color.fond.ignoresSafeArea()
            ZStack {
                switch ecran {
                case .accueil:
                    accueil
                case .montants:
                    if let argent = app.argent { ArgentView(modele: argent).id(ObjectIdentifier(argent)) }
                case .chantiers:
                    if let chantiers = app.chantiers { ChantiersView(modele: chantiers).id(ObjectIdentifier(chantiers)) }
                }
            }
            .transition(.opacity)

            dock
                .frame(maxWidth: 520)
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, 4)
                .ignoresSafeArea(.keyboard)
        }
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
        .task { await chargerNotes() }
        .onChange(of: note) { _, ouverte in
            if !ouverte { Task { await chargerNotes() } }
        }
    }

    // MARK: - Accueil

    private var accueil: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espace.l) {
                enTete
                chiffres
                gestes
                if !dossiers.isEmpty { apercuChantiers }
                if !notes.isEmpty { journal }
            }
            .padding(.horizontal, Espace.bord)
            .padding(.top, Espace.m)
            .padding(.bottom, 120)
            .verrouillerLargeur()
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await app.rafraichirTout()
            await chargerNotes()
        }
        .background(FondMaison())
    }

    private var enTete: some View {
        HStack(alignment: .top, spacing: Espace.s) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Endry SA · Direction").etiquetteMaison()
                TitreAdaptatif(texte: salut, grand: 42, lignes: 2)
                Text(dateDuJour)
                    .styleTexte(14, relativeTo: .subheadline)
                    .foregroundStyle(Color.encreDouce)
            }
            Spacer(minLength: 0)
            BoutonRondVerre(libelle: "Se déconnecter", identifiant: "deconnexion-directeur") {
                deconnexion = true
            } contenu: {
                Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 15, weight: .medium))
            }
        }
        .padding(.top, Espace.s)
    }

    /// Le chiffre qui compte en premier, puis trois repères sur une ligne.
    @ViewBuilder private var chiffres: some View {
        if let argent = app.argent?.argent {
            VStack(alignment: .leading, spacing: Espace.s) {
                Button { changer(.montants) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("À encaisser").etiquetteMaison()
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.encreDouce)
                        }
                        ChiffreInstrument(valeur: FormatSuisse.francs(argent.encaisser.total), prefixe: "CHF", taille: 54)
                        Text(factures(argent.encaisser.factures.count))
                            .styleTexte(14, relativeTo: .subheadline)
                            .foregroundStyle(Color.encreDouce)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .tuileMaison(rayon: 28)
                }
                .buttonStyle(ActionPressee())
                .accessibilityIdentifier("directeur-a-encaisser")

                BandeChiffres(elements: [
                    .init(valeur: FormatSuisse.francs(argent.payer.total), libelle: "À payer"),
                    .init(valeur: FormatSuisse.francs(argent.offres.total), libelle: "Offres en attente"),
                    .init(valeur: String(app.chantiers?.tous.count ?? 0), libelle: "Chantiers"),
                ])
            }
        } else {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, Espace.xl)
            .tuileMaison(rayon: 28)
        }
    }

    /// Les deux gestes du directeur : parler pour consigner, ou demander.
    private var gestes: some View {
        VStack(spacing: Espace.s) {
            Button { note = true } label: {
                HStack(spacing: Espace.m) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.encrePapier)
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.38), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dicter une note")
                            .font(Police.serif(27, relativeTo: .title2))
                            .foregroundStyle(Color.encrePapier)
                        Text("Ce qui s’est dit ou décidé sur le terrain. Le secrétariat en tire les décisions.")
                            .styleTexte(13.5, relativeTo: .footnote)
                            .foregroundStyle(Color.encrePapierDouce)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [Color.orClair, Color.or], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .buttonStyle(ActionPressee())
            .accessibilityIdentifier("dicter-une-note")

            HStack(spacing: Espace.s) {
                Button { app.conversationPresentee = true } label: {
                    HStack(spacing: Espace.s) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Color.bronze)
                            .frame(width: 44, height: 44)
                            .background(Color.or.opacity(0.16), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Poser une question")
                                .styleTexte(17, graisse: .semibold)
                                .foregroundStyle(Color.encre)
                            Text("Entreprise, technique, photo ou scan d’une pièce")
                                .styleTexte(13, relativeTo: .footnote)
                                .foregroundStyle(Color.encreDouce)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                    .tuileMaison(rayon: 26)
                }
                .buttonStyle(ActionPressee())
                .accessibilityIdentifier("poser-une-question")

                Button { app.ouvrirAssistant() } label: {
                    VStack(spacing: 6) {
                        OrbeSiri(diametre: 40)
                        Text("À la voix")
                            .styleTexte(12, relativeTo: .caption, graisse: .medium)
                            .foregroundStyle(Color.encreDouce)
                    }
                    .frame(width: 84)
                    .frame(minHeight: 84)
                    .tuileMaison(rayon: 26)
                }
                .buttonStyle(ActionPressee())
                .accessibilityLabel(Text("Poser une question à la voix"))
                .accessibilityIdentifier("question-vocale")
            }
        }
    }

    private var apercuChantiers: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            TitreSection(titre: "Chantiers", lien: "Tout voir", action: { changer(.chantiers) })
            VStack(spacing: 0) {
                ForEach(Array(dossiers.enumerated()), id: \.element.id) { index, dossier in
                    if index > 0 {
                        Rectangle().fill(Color.filet).frame(height: Espace.filet).padding(.leading, 16)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Espace.s) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dossier.titre)
                                .styleTexte(15.5, graisse: .medium)
                                .foregroundStyle(Color.encre)
                                .lineLimit(1)
                            Text(sousTitre(dossier))
                                .styleTexte(13, relativeTo: .footnote)
                                .foregroundStyle(Color.encreDouce)
                                .lineLimit(1)
                        }
                        Spacer(minLength: Espace.s)
                        Text(dossier.etapeLibelle)
                            .styleTexte(12, relativeTo: .caption, graisse: .medium)
                            .foregroundStyle(Color.bronze)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
            }
            .tuileMaison(rayon: 24)
        }
    }

    private var journal: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            TitreSection(titre: "Vos dernières notes", repere: String(notes.count))
            VStack(spacing: Espace.s) {
                ForEach(Array(notes.prefix(3))) { ligne in
                    VStack(alignment: .leading, spacing: 6) {
                        if let date = ligne.date {
                            Text(date).font(Police.mono(11.5)).foregroundStyle(Color.encreDouce)
                        }
                        Text(ligne.texte)
                            .styleTexte(14.5)
                            .foregroundStyle(Color.encre)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .tuileMaison(rayon: 22)
                }
            }
        }
    }

    // MARK: - Dock

    /// Un seul élément flottant : les trois écrans, et le micro de la note quand on n'est plus sur l'accueil.
    private var dock: some View {
        HStack(spacing: Espace.s) {
            SelecteurSegments(options: [
                OptionSegment(valeur: Ecran.accueil, titre: "Accueil"),
                OptionSegment(valeur: Ecran.montants, titre: "Montants"),
                OptionSegment(valeur: Ecran.chantiers, titre: "Chantiers"),
            ], selection: $ecran)
            .accessibilityIdentifier("ecran-directeur")

            if ecran != .accueil {
                Button { note = true } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.encrePapier)
                        .frame(width: 46, height: 46)
                        .background(
                            LinearGradient(colors: [Color.orClair, Color.or], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Circle())
                }
                .buttonStyle(ActionPressee())
                .accessibilityLabel(Text("Dicter une note"))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: ecran)
    }

    // MARK: - Données

    /// Les chantiers datés d'abord (ceux qui bougent), trois au plus.
    private var dossiers: [Dossier] {
        let tous = app.chantiers?.tous ?? []
        let dates = tous.filter { $0.dateDebut != nil }
        return Array((dates.isEmpty ? tous : dates).prefix(3))
    }

    private func sousTitre(_ dossier: Dossier) -> String {
        [dossier.client, dossier.lieu ?? "", dossier.dates ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var salut: String {
        let heure = Calendar.current.component(.hour, from: Date())
        let mot = (5..<18).contains(heure) ? "Bonjour" : "Bonsoir"
        if let nom = app.session.nomOuvrier, !nom.isEmpty { return "\(mot), \(nom)" }
        return mot
    }

    private var dateDuJour: String {
        let texte = Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH")))
        return texte.prefix(1).uppercased() + String(texte.dropFirst())
    }

    private func factures(_ nombre: Int) -> String {
        switch nombre {
        case 0: "Aucune facture ouverte"
        case 1: "1 facture ouverte"
        default: "\(nombre) factures ouvertes"
        }
    }

    private func changer(_ nouvel: Ecran) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { ecran = nouvel }
    }

    private func chargerNotes() async {
        guard let api = app.session.api else { return }
        if let liste = try? await api.notesDirecteur() { notes = liste }
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
