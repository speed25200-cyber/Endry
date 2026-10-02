import EndryKit
import PhotosUI
import SwiftUI
import UIKit

/// Outils de terrain : ouverts depuis la Saisie, un chantier, Siri ou une notification d'arrivée.
enum OutilTerrain: String, CaseIterable, Identifiable, Sendable {
    case regie
    case bonLivraison
    case releve

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .regie: "Bon de régie"
        case .bonLivraison: "Bon de livraison"
        case .releve: "Relevé 3D"
        }
    }

    var sousTitre: String {
        switch self {
        case .regie: "Dicté, signé sur place"
        case .bonLivraison: "Photographié, rattaché"
        case .releve: "Mesures de la pièce"
        }
    }

    /// Outils ouverts à un ouvrier (lien d'équipe) : relevé et bon de livraison. La régie, qui engage une facture,
    /// reste au patron.
    static let pourOuvrier: [OutilTerrain] = [.releve, .bonLivraison]

    var icone: String {
        switch self {
        case .regie: "signature"
        case .bonLivraison: "shippingbox.fill"
        case .releve: "cube.transparent"
        }
    }
}

/// Outil demandé, avec le chantier s'il est connu.
struct DemandeOutil: Identifiable, Equatable {
    let id = UUID()
    var outil: OutilTerrain
    var chantierId: String?
}

/// Chantier proposé dans les écrans de terrain : un dossier du patron, ou un chantier du jour d'un ouvrier.
/// L'ouvrier ne voit que ses chantiers du jour (`GET /equipe/jour`), jamais la liste du bureau.
struct ChantierPropose: Identifiable, Hashable {
    var id: String
    var titre: String
    var client: String?
    var lieu: String?

    var detail: String { [client, lieu].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
}

extension ModeleApp {
    func ouvrirOutil(_ outil: OutilTerrain, chantier: String? = nil) {
        if session.estOuvrier, !OutilTerrain.pourOuvrier.contains(outil) { return }
        outilTerrain = DemandeOutil(outil: outil, chantierId: chantier)
    }

    /// Chantiers proposés : ceux du jour d'abord, puis les chantiers en cours, puis les autres.
    /// Ouvrier : ses chantiers du jour seulement.
    var chantiersProposes: [ChantierPropose] {
        if session.estOuvrier {
            return (equipe?.chantiers ?? []).map { ChantierPropose(id: $0.id, titre: $0.titre, client: $0.client, lieu: $0.lieu) }
        }
        let tous = chantiers?.tous ?? []
        let semaine = Set((chantiers?.semaine ?? []).filter { s in
            guard let d = s.dateDebut else { return false }
            let f = s.dateFin ?? d
            return DateEndry.jours(de: d, a: Date()) >= 0 && DateEndry.jours(de: Date(), a: f) >= 0
        }.map(\.id))
        let actives: Set<String> = ["planifie", "en_cours", "commande", "realise"]
        func rang(_ d: Dossier) -> Int { semaine.contains(d.id) ? 0 : actives.contains(d.etape) ? 1 : 2 }
        return tous.sorted { (rang($0), $0.titre) < (rang($1), $1.titre) }
            .map { ChantierPropose(id: $0.id, titre: $0.titre, client: $0.client, lieu: $0.lieu) }
    }

    func chantierPropose(_ id: String?) -> ChantierPropose? {
        guard let id else { return nil }
        return chantiersProposes.first { $0.id == id }
    }

    func dossier(_ id: String?) -> Dossier? {
        guard let id else { return nil }
        return chantiers?.tous.first { $0.id == id }
    }

    /// Envoi terrain par la saisie (file hors ligne comprise), avec un message pour le patron.
    func transmettre(_ envoi: EnvoiTerrain) async -> ModeleSaisie.ResultatTerrain {
        guard let saisie else { return .refusee("Connectez d’abord l’app au bureau.") }
        let resultat = await saisie.transmettre(terrain: envoi)
        // Tout envoi entre dans le suivi : le patron voit ce que le bureau en fait.
        switch resultat {
        case .transmis(let r):
            suiviActions?.enregistrer(saisie: r.id, texte: envoi.resume, nature: .terrain, chantierId: envoi.chantierId,
                                      reponse: r.message, decisionPreparee: r.decisionReference)
            suivreApresGeste()
        case .gardee:
            suiviActions?.enregistrer(saisie: nil, texte: envoi.resume, nature: .terrain, chantierId: envoi.chantierId,
                                      reponse: "Gardé sur l’iPhone : partira au retour du réseau.")
        case .refusee:
            break
        }
        return resultat
    }
}

// MARK: - Rangée d'outils

/// Grandes tuiles : régie, bon de livraison, relevé 3D (relevé et bon seulement pour un ouvrier).
struct RangeeOutilsTerrain: View {
    @Environment(ModeleApp.self) private var app
    var chantierId: String?
    var outils: [OutilTerrain] = OutilTerrain.allCases

    /// Maison Endry : tuiles de verre en grille de deux, monogramme rond (RG, BL, 3D), titre et sous-titre.
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(outils) { outil in
                Button {
                    app.ouvrirOutil(outil, chantier: chantierId)
                } label: {
                    HStack(spacing: 12) {
                        Text(outil.monogramme)
                            .font(Police.mono(12))
                            .foregroundStyle(Color.encre)
                            .frame(width: 40, height: 40)
                            .background(Color.lentille, in: Circle())
                            .overlay(Circle().strokeBorder(Color.filet, lineWidth: Espace.filet))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(outil.titre)
                                .styleTexte(15, relativeTo: .subheadline)
                                .foregroundStyle(Color.encre)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(outil.sousTitre)
                                .styleTexte(12.5, relativeTo: .caption)
                                .foregroundStyle(Color.encreDouce)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .tuileMaison(rayon: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ActionPressee())
                .accessibilityIdentifier("outil-\(outil.rawValue)")
            }
        }
    }
}

extension OutilTerrain {
    /// Monogramme des tuiles « Sur place ».
    var monogramme: String {
        switch self {
        case .regie: "RG"
        case .bonLivraison: "BL"
        case .releve: "3D"
        }
    }
}

// MARK: - Choix du chantier

struct ChoixChantier: View {
    @Environment(ModeleApp.self) private var app
    @Binding var chantierId: String?
    /// Libellé libre quand le chantier n'est pas dans la liste (client de passage).
    @Binding var libre: String
    var suggestions: [String] = []
    @State private var presente = false

    private var choisi: ChantierPropose? { app.chantierPropose(chantierId) }

    var body: some View {
        Button { presente = true } label: {
            HStack(spacing: Espace.s) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.bronze)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choisi?.titre ?? (libre.isEmpty ? "Choisir le chantier" : libre))
                        .styleTexte(16, relativeTo: .body, graisse: .semibold)
                        .foregroundStyle(Color.encre)
                        .lineLimit(2)
                    if let choisi {
                        Text(choisi.detail)
                            .styleTexte(13, relativeTo: .footnote)
                            .foregroundStyle(Color.encreDouce)
                    } else if libre.isEmpty {
                        Text(app.session.estOuvrier ? "Un de vos chantiers du jour" : "Chantier du jour, ou client de passage")
                            .styleTexte(13, relativeTo: .footnote)
                            .foregroundStyle(Color.encrePale)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.bold)).foregroundStyle(Color.encrePale)
            }
            .padding(Espace.m)
            .surfaceCarte(rayon: 18)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("choix-chantier")
        .sheet(isPresented: $presente) {
            ListeChoixChantier(chantierId: $chantierId, libre: $libre, suggestions: suggestions)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct ListeChoixChantier: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @Binding var chantierId: String?
    @Binding var libre: String
    var suggestions: [String]
    @State private var recherche = ""

    var body: some View {
        NavigationStack {
            List {
                let proposes = filtrer(app.chantiersProposes)
                if !suggestions.isEmpty && recherche.isEmpty {
                    Section("Suggérés") {
                        ForEach(suggestions.compactMap { app.chantierPropose($0) }) { ligne($0) }
                    }
                }
                Section(recherche.isEmpty ? (app.session.estOuvrier ? "Mes chantiers du jour" : "Chantiers") : "Résultats") {
                    ForEach(proposes) { ligne($0) }
                    if proposes.isEmpty {
                        Text("Aucun chantier ne correspond.").foregroundStyle(Color.encrePale)
                    }
                }
                Section {
                    TextField("Client de passage (nom, lieu)", text: $libre)
                        .submitLabel(.done)
                        .onSubmit {
                            chantierId = nil
                            fermer()
                        }
                } header: {
                    Text("Hors liste")
                } footer: {
                    Text("Le bureau rattachera le document au bon client.")
                }
            }
            .searchable(text: $recherche, prompt: "Client, lieu ou chantier")
            .navigationTitle("Chantier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { fermer() } }
            }
        }
    }

    private func filtrer(_ liste: [ChantierPropose]) -> [ChantierPropose] {
        let q = recherche.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return liste }
        return liste.filter { d in [d.titre, d.client ?? "", d.lieu ?? ""].contains { $0.lowercased().contains(q) } }
    }

    private func ligne(_ d: ChantierPropose) -> some View {
        Button {
            chantierId = d.id
            libre = ""
            fermer()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.titre).foregroundStyle(Color.encre)
                    Text(d.detail)
                        .font(.footnote).foregroundStyle(Color.encreDouce)
                }
                Spacer()
                if d.id == chantierId { Image(systemName: "checkmark").foregroundStyle(Color.bronze) }
            }
        }
        .accessibilityIdentifier("choix-chantier-\(d.id)")
    }
}

// MARK: - Photos de terrain

/// Photos prises ou choisies, converties pour le PC (JPEG, 2560 px).
struct PhotosTerrain: View {
    @Binding var photos: [FormulaireMultipart.Fichier]
    var prefixe = "photo"
    @State private var selection: [PhotosPickerItem] = []
    @State private var bibliotheque = false
    @State private var camera = false

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            HStack(spacing: Espace.s) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    bouton("Photo", icone: "camera.fill") { camera = true }
                }
                bouton("Galerie", icone: "photo.on.rectangle") { bibliotheque = true }
            }
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Espace.s) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                            ZStack(alignment: .topTrailing) {
                                if let image = UIImage(data: photo.donnees) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .frame(width: 76, height: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                Button {
                                    withAnimation(.endry) { _ = photos.remove(at: index) }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.fond)
                                        .frame(width: 22, height: 22)
                                        .background(Color.encre.opacity(0.8), in: Circle())
                                }
                                .offset(x: 6, y: -6)
                                .accessibilityLabel(Text("Retirer la photo"))
                            }
                        }
                    }
                    .padding(.vertical, Espace.xxs)
                }
                .scrollClipDisabled()
            }
        }
        .photosPicker(isPresented: $bibliotheque, selection: $selection, maxSelectionCount: 10, matching: .images, photoLibrary: .shared())
        .onChange(of: selection) { _, elements in
            Task {
                for element in elements {
                    if let data = try? await element.loadTransferable(type: Data.self) { ajouter(data) }
                }
                selection = []
            }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPhoto { image in
                camera = false
                if let image, let brut = image.jpegData(compressionQuality: 1) { ajouter(brut) }
            }
            .ignoresSafeArea()
        }
    }

    private func ajouter(_ brut: Data) {
        guard let jpeg = ImagePourPC.jpeg(brut) else { return }
        let nom = "\(prefixe)-\(photos.count + 1).jpg"
        withAnimation(.endry) {
            photos.append(.init(champ: "pieces", nomFichier: nom, typeMIME: "image/jpeg", donnees: jpeg))
        }
    }

    private func bouton(_ titre: String, icone: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(titre, systemImage: icone)
                .styleTexte(14, relativeTo: .subheadline, graisse: .semibold)
                .foregroundStyle(Color.encre)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.surfaceCreuse.opacity(0.7), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.bordureOr, lineWidth: Espace.filet))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Résultat d'un envoi

/// Carte de fin : transmis (avec la décision préparée), gardé hors ligne, ou refusé.
struct ResultatEnvoiTerrain: View {
    @Environment(ModeleApp.self) private var app
    var resultat: ModeleSaisie.ResultatTerrain
    var fermer: () -> Void

    var body: some View {
        VStack(spacing: Espace.l) {
            ZStack {
                Circle().fill(couleur.opacity(0.12)).frame(width: 116, height: 116)
                Image(systemName: icone)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(couleur)
                    .symbolEffect(.bounce, value: titre)
            }
            Text(titre).styleTitre(30, relativeTo: .largeTitle).foregroundStyle(Color.encre)
            Text(message).styleTexte(16).foregroundStyle(Color.encreDouce).multilineTextAlignment(.center)
            // Un ouvrier ne voit pas les décisions : l'offre préparée attend le patron.
            if case .transmis(let r) = resultat, let reference = r.decisionReference, !app.session.estOuvrier {
                Button {
                    fermer()
                    app.ouvrir(reference: reference)
                } label: {
                    Label("Voir la décision préparée", systemImage: "checkmark.seal")
                }
                .buttonStyle(BoutonPrincipal())
            }
            Button("Terminer", action: fermer)
                .buttonStyle(BoutonSecondaire())
                .accessibilityIdentifier("terminer-terrain")
        }
        .padding(Espace.xl)
        .frame(maxWidth: .infinity)
        .surfaceCarte()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("resultat-terrain")
    }

    private var titre: String {
        switch resultat {
        case .transmis: "Transmis"
        case .gardee: "Gardé"
        case .refusee: "Non transmis"
        }
    }

    private var message: String {
        switch resultat {
        case .transmis(let r):
            (r.message ?? "Reçu au bureau.") + (r.parSaisie ? " (transmis comme saisie : le PC n’a pas encore la route terrain)" : "")
        case .gardee:
            "Pas de réseau : c’est gardé sur l’iPhone et partira tout seul dès le retour de la connexion."
        case .refusee(let m):
            m
        }
    }

    private var icone: String {
        switch resultat {
        case .transmis: "checkmark"
        case .gardee: "tray.and.arrow.up"
        case .refusee: "exclamationmark.triangle"
        }
    }

    private var couleur: Color {
        switch resultat {
        case .transmis: .vertControle
        case .gardee: .ambre
        case .refusee: .rouille
        }
    }
}

/// Carte de section des écrans de terrain.
struct SectionTerrain<Contenu: View>: View {
    var titre: String
    var icone: String
    @ViewBuilder var contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            Label(titre, systemImage: icone)
                .styleTexte(13, relativeTo: .footnote, graisse: .semibold)
                .foregroundStyle(Color.bronze)
                .textCase(.uppercase)
            contenu
        }
        .padding(Espace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte(rayon: 20)
    }
}

/// Micro compact des écrans de terrain : or au repos, espresso pendant l'écoute, halo qui suit la voix.
struct BoutonMicroCompact: View {
    var ecoute: Bool
    var niveau: Float
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.or.opacity(ecoute ? 0.28 : 0))
                    .frame(width: 76, height: 76)
                    .scaleEffect(1 + CGFloat(niveau) * 0.35)
                    .animation(.endryVif, value: niveau)
                Circle()
                    .fill(ecoute ? AnyShapeStyle(Color.espresso) : AnyShapeStyle(.degradeOr))
                    .frame(width: 62, height: 62)
                    .shadow(color: Color.bronzeMoyen.opacity(0.35), radius: 12, y: 6)
                Image(systemName: ecoute ? "stop.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ecoute ? Color.or : Color.espresso)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 80, height: 80)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: ecoute)
        .accessibilityLabel(Text(ecoute ? "Arrêter la dictée" : "Dicter"))
        .accessibilityIdentifier("micro-terrain")
    }
}

/// Ferme le clavier (pavé numérique compris, qui n'a pas de touche retour).
@MainActor
enum ClavierTerrain {
    static func fermer() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
