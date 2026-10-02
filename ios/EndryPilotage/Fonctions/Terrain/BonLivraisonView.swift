import EndryKit
import PhotosUI
import SwiftUI
import VisionKit

/// Bon de livraison : scanné (bords détectés, redressé), lu sur l'iPhone, rattaché au chantier.
/// Le bureau ajoute le matériel à « à refacturer » ; aucun montant n'est lu ni affiché.
struct BonLivraisonView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer

    @State private var pages: [UIImage] = []
    @State private var bon: BonLivraison?
    @State private var chantierId: String?
    @State private var libre = ""
    @State private var suggestions: [String] = []
    @State private var lecture = false
    @State private var scanner = false
    @State private var galerie = false
    @State private var selection: [PhotosPickerItem] = []
    @State private var envoi = false
    @State private var resultat: ModeleSaisie.ResultatTerrain?

    init(chantierId: String?) {
        _chantierId = State(initialValue: chantierId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.m) {
                    if let resultat {
                        ResultatEnvoiTerrain(resultat: resultat) { fermer() }
                            .padding(.top, Espace.l)
                    } else if lecture {
                        VStack(spacing: Espace.m) {
                            ProgressView().controlSize(.large)
                            Text(ExtractionIA.disponible ? "Lecture du bon avec Apple Intelligence…" : "Lecture du bon…")
                                .styleTexte(15, graisse: .medium)
                                .foregroundStyle(Color.encreDouce)
                        }
                        .frame(maxWidth: .infinity, minHeight: 320)
                    } else if bon == nil {
                        accueil
                    } else {
                        formulaire
                    }
                }
                .largeurLisible()
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, Espace.xxl)
                .animation(.endry, value: resultat)
                .animation(.endry, value: lecture)
                .verrouillerLargeur()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FondAmbiant())
            .navigationTitle("Bon de livraison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { fermer() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { ClavierTerrain.fermer() }.fontWeight(.semibold).accessibilityIdentifier("clavier-ok")
                }
            }
        }
        .fullScreenCover(isPresented: $scanner) {
            ScannerDocuments { images in
                scanner = false
                Task { await lire(images) }
            } annuler: {
                scanner = false
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $galerie, selection: $selection, maxSelectionCount: 4, matching: .images, photoLibrary: .shared())
        .onChange(of: selection) { _, elements in
            Task {
                var images: [UIImage] = []
                for e in elements {
                    if let d = try? await e.loadTransferable(type: Data.self), let i = UIImage(data: d) { images.append(i) }
                }
                selection = []
                if !images.isEmpty { await lire(images) }
            }
        }
        .task {
            // Direct au scanner : c'est le geste attendu sur le chantier.
            if pages.isEmpty, bon == nil, VNDocumentCameraViewController.isSupported, !Configuration.testsUI {
                scanner = true
            }
        }
    }

    // MARK: - Écrans

    private var accueil: some View {
        VStack(spacing: Espace.l) {
            EtatVide(titre: "Photographiez le bon",
                     message: "Les bords sont détectés et la page redressée. Le fournisseur, les numéros et les articles sont lus sur l’iPhone ; les prix sont ignorés.",
                     icone: "doc.viewfinder")
            if VNDocumentCameraViewController.isSupported {
                Button { scanner = true } label: { Label("Scanner le bon", systemImage: "doc.viewfinder") }
                    .buttonStyle(BoutonPrincipal())
            }
            Button { galerie = true } label: { Label("Choisir une photo", systemImage: "photo") }
                .buttonStyle(BoutonSecondaire())
            if app.session.estDemo {
                Button("Bon d’exemple (démo)") { Task { await lireExemple() } }
                    .styleTexte(14, graisse: .semibold)
                    .foregroundStyle(Color.bronze)
                    .accessibilityIdentifier("bon-exemple")
            }
        }
        .padding(.top, Espace.l)
    }

    @ViewBuilder
    private var formulaire: some View {
        let lie = Binding(get: { bon ?? BonLivraison() }, set: { bon = $0 })
        VStack(alignment: .leading, spacing: Espace.xxs) {
            Text("Bon de livraison").styleSurtitre()
            Text(bon?.fournisseur ?? "Fournisseur à préciser")
                .styleTitre(28, relativeTo: .largeTitle)
                .foregroundStyle(Color.encre)
        }
        .padding(.top, Espace.s)

        if !pages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Espace.s) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                        Image(uiImage: page).resizable().scaledToFill()
                            .frame(width: 84, height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.filet, lineWidth: 0.5))
                    }
                }
            }
            .scrollClipDisabled()
        }

        ChoixChantier(chantierId: $chantierId, libre: $libre, suggestions: suggestions)
        if let commission = bon?.commission {
            Label("Écrit sur le bon : « \(commission) »", systemImage: "text.viewfinder")
                .styleTexte(13, relativeTo: .footnote)
                .foregroundStyle(Color.encreDouce)
        }

        SectionTerrain(titre: "Bon", icone: "doc.text") {
            champ("Fournisseur", texte: Binding(get: { lie.wrappedValue.fournisseur ?? "" }, set: { lie.wrappedValue.fournisseur = $0.isEmpty ? nil : $0 }))
            champ("N° du bon", texte: Binding(get: { lie.wrappedValue.numero ?? "" }, set: { lie.wrappedValue.numero = $0.isEmpty ? nil : $0 }))
            champ("Commande", texte: Binding(get: { lie.wrappedValue.commande ?? "" }, set: { lie.wrappedValue.commande = $0.isEmpty ? nil : $0 }))
            if let date = bon?.date {
                LabeledContent("Date", value: DateEndry.courte(date)).styleTexte(15)
            }
        }

        SectionTerrain(titre: "Articles (\(bon?.articles.count ?? 0))", icone: "shippingbox") {
            ForEach(lie.articles) { $a in
                HStack(spacing: Espace.xs) {
                    TextField("Qté", value: Binding(get: { $a.wrappedValue.quantite ?? 1 }, set: { $a.wrappedValue.quantite = $0 }), format: .number)
                        .keyboardType(.decimalPad)
                        .frame(width: 48)
                        .styleTexte(15, graisse: .semibold)
                    Text(a.unite ?? "pce").styleTexte(13).foregroundStyle(Color.bronze)
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Désignation", text: $a.designation).styleTexte(15)
                        if let r = a.reference { Text(r).font(Police.reference()).foregroundStyle(Color.encrePale) }
                    }
                    Button {
                        withAnimation(.endry) { bon?.articles.removeAll { $0.id == a.id } }
                    } label: { Image(systemName: "minus.circle").foregroundStyle(Color.encrePale) }
                        .buttonStyle(.plain)
                }
            }
            Button {
                withAnimation(.endry) { bon?.articles.append(ArticleLivre(designation: "", quantite: 1, unite: "pce")) }
            } label: { Label("Ajouter un article", systemImage: "plus.circle.fill") }
                .styleTexte(14, graisse: .semibold)
                .foregroundStyle(Color.bronze)
            Text("Relisez : la lecture automatique peut se tromper sur une ligne froissée.")
                .styleTexte(12, relativeTo: .caption)
                .foregroundStyle(Color.encrePale)
        }

        let manques = bonComplet.manques
        ForEach(manques, id: \.self) { m in
            Label(m, systemImage: "circle.dashed").styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
        }
        Button {
            Task { await transmettre() }
        } label: {
            HStack(spacing: Espace.xs) {
                if envoi { ProgressView().tint(Color.fond) } else { Image(systemName: "link") }
                Text(envoi ? "Transmission…" : "Rattacher au chantier")
            }
        }
        .buttonStyle(BoutonPrincipal())
        .disabled(envoi || !manques.isEmpty)
        .accessibilityIdentifier("rattacher-bon")
        Button("Scanner à nouveau") {
            bon = nil
            pages = []
            scanner = VNDocumentCameraViewController.isSupported
        }
        .buttonStyle(BoutonSecondaire())
    }

    private func champ(_ titre: String, texte: Binding<String>) -> some View {
        HStack {
            Text(titre).styleTexte(14).foregroundStyle(Color.encreDouce).frame(width: 100, alignment: .leading)
            TextField(titre, text: texte).styleTexte(15, graisse: .medium)
        }
    }

    // MARK: - Lecture et envoi

    private var bonComplet: BonLivraison {
        var b = bon ?? BonLivraison()
        b.chantierId = chantierId
        if let d = app.chantierPropose(chantierId) { b.chantier = d.titre } else if !libre.isEmpty { b.chantier = libre }
        return b
    }

    private func lire(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        pages = images
        lecture = true
        let lignes = await LectureDocument.lignes(images.compactMap(\.cgImage))
        let lu = await ExtractionIA.bonLivraison(lignes)
        appliquer(lu)
        lecture = false
    }

    private func lireExemple() async {
        lecture = true
        try? await Task.sleep(for: .milliseconds(400))
        appliquer(LecteurBonLivraison.analyser(lignes: [
            "Meier Tobler SA", "Bulletin de livraison n° BL-2026-48817", "Date : 26.09.2026", "Votre commande : C-5521",
            "Commission : Morel Epalinges PAC", "35012 Raccord Mapress 22 mm 12 pce 4.80", "4 m Tube multicouche Alpex 16",
            "1 pce Vase d'expansion 25 l", "Total CHF 312.40",
        ]))
        lecture = false
    }

    private func appliquer(_ lu: BonLivraison) {
        let propositions = SuggestionChantier.classer(texte: [lu.commission ?? "", lu.texteLu].joined(separator: " "), chantiers: app.chantiers?.tous ?? [])
        suggestions = propositions.prefix(3).map(\.dossier.id)
        if chantierId == nil, let premier = propositions.first, premier.score >= 3 { chantierId = premier.dossier.id }
        withAnimation(.endry) { bon = lu }
    }

    private func transmettre() async {
        envoi = true
        let fichiers = pages.enumerated().compactMap { i, page -> FormulaireMultipart.Fichier? in
            guard let brut = page.jpegData(compressionQuality: 1), let jpeg = ImagePourPC.jpeg(brut) else { return nil }
            return .init(champ: "pieces", nomFichier: "bon-livraison-\(i + 1).jpg", typeMIME: "image/jpeg", donnees: jpeg)
        }
        let r = await app.transmettre(bonComplet.envoi(pages: fichiers))
        envoi = false
        withAnimation(.endry) { resultat = r }
    }
}
