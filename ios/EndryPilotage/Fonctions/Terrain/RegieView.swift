import EndryKit
import PencilKit
import SwiftUI

/// Bon de régie rempli sur place : dictée structurée (Apple Intelligence ou analyse locale), heures, matériel,
/// photos, signature du client, PDF. Rien n'est facturé ici : le bureau prépare la facture, le patron la valide.
struct RegieView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @AppStorage(Salutation.clePrenom) private var prenom = ""

    @State private var bon: BonRegie
    @State private var libre = ""
    @State private var dictee = Dictee()
    @State private var texteDicte = ""
    @State private var analyse = false
    @State private var photos: [FormulaireMultipart.Fichier] = []
    @State private var signature: Data?
    @State private var signaturePresentee = false
    @State private var envoi = false
    @State private var resultat: ModeleSaisie.ResultatTerrain?
    @State private var pdf: URL?
    @FocusState private var saisieActive: Bool

    init(chantier: Dossier?) {
        _bon = State(initialValue: BrouillonRegie.lire(pour: chantier) ?? BonRegie.nouveau(pour: chantier))
    }

    private var moi: String { prenom.isEmpty ? "Patron" : prenom }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.m) {
                    if let resultat {
                        ResultatEnvoiTerrain(resultat: resultat) { fermer() }
                            .padding(.top, Espace.l)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    } else {
                        formulaire
                    }
                }
                .largeurLisible()
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, Espace.xxl)
                .animation(.endry, value: resultat)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FondAmbiant())
            .navigationTitle("Bon de régie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dictee.arreter(); fermer() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { saisieActive = false }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("clavier-ok")
                }
                if resultat == nil, bon.estSigne {
                    ToolbarItem(placement: .primaryAction) {
                        if let pdf {
                            ShareLink(item: pdf) { Label("Copie PDF", systemImage: "square.and.arrow.up") }
                        }
                    }
                }
            }
        }
        .onChange(of: dictee.ecoute) { _, ecoute in
            if !ecoute, !dictee.transcription.isEmpty {
                texteDicte = dictee.transcription
                Task { await remplir(depuis: texteDicte) }
            }
        }
        .onChange(of: bon) { _, nouveau in
            if resultat == nil { BrouillonRegie.enregistrer(nouveau) }
        }
        .fullScreenCover(isPresented: $signaturePresentee) {
            SignatureClientView(bon: bon) { nom, png in
                bon.signer(par: nom)
                signature = png
                signaturePresentee = false
                preparerPDF()
            } annuler: {
                signaturePresentee = false
            }
        }
        .onDisappear { dictee.arreter() }
        .sensoryFeedback(.success, trigger: bon.estSigne)
    }

    // MARK: - Formulaire

    @ViewBuilder
    private var formulaire: some View {
        VStack(alignment: .leading, spacing: Espace.xxs) {
            Text("Régie · \(bon.numero)").styleSurtitre()
            Text(bon.chantier.isEmpty ? "Nouveau bon" : bon.chantier)
                .styleTitre(28, relativeTo: .largeTitle)
                .foregroundStyle(Color.encre)
                .lineLimit(2)
        }
        .padding(.top, Espace.s)

        ChoixChantier(chantierId: Binding(get: { bon.chantierId }, set: { choisir($0) }), libre: $libre)
            .disabled(bon.estSigne)
            .onChange(of: libre) { _, nom in
                if bon.chantierId == nil { bon.client = nom; bon.chantier = "" }
            }

        dicteeCarte
            .disabled(bon.estSigne)

        SectionTerrain(titre: "Travaux", icone: "wrench.adjustable") {
            TextField("Ce qui a été fait", text: $bon.travaux, axis: .vertical)
                .styleTexte(16)
                .lineLimit(3...8)
                .focused($saisieActive)
                .accessibilityIdentifier("regie-travaux")
        }
        .disabled(bon.estSigne)

        SectionTerrain(titre: "Heures", icone: "clock") {
            ForEach($bon.heures) { $ligne in
                HStack(spacing: Espace.s) {
                    TextField("Qui", text: $ligne.intervenant)
                        .styleTexte(16, graisse: .medium)
                    Spacer(minLength: 0)
                    Text(FormatSuisse.heures(ligne.heures))
                        .styleTexte(16, graisse: .semibold)
                        .monospacedDigit()
                        .frame(minWidth: 64, alignment: .trailing)
                    Stepper("", value: $ligne.heures, in: 0.25...24, step: 0.25).labelsHidden()
                }
                .swipeActions { Button("Retirer", role: .destructive) { bon.heures.removeAll { $0.id == ligne.id } } }
                .contextMenu { Button("Retirer", role: .destructive) { bon.heures.removeAll { $0.id == ligne.id } } }
            }
            HStack {
                Button {
                    withAnimation(.endry) { bon.heures.append(LigneHeures(intervenant: bon.heures.isEmpty ? moi : "", heures: 1)) }
                } label: { Label("Ajouter une personne", systemImage: "plus.circle.fill") }
                    .styleTexte(14, graisse: .semibold)
                    .foregroundStyle(Color.bronze)
                Spacer()
                if !bon.heures.isEmpty {
                    Text("Total \(FormatSuisse.heures(bon.totalHeures))")
                        .styleTexte(14, graisse: .semibold)
                        .foregroundStyle(Color.encreDouce)
                }
            }
        }
        .disabled(bon.estSigne)

        SectionTerrain(titre: "Matériel", icone: "shippingbox") {
            ForEach($bon.materiel) { $ligne in
                HStack(spacing: Espace.xs) {
                    TextField("Qté", value: $ligne.quantite, format: .number)
                        .keyboardType(.decimalPad)
                        .frame(width: 48)
                        .styleTexte(16, graisse: .semibold)
                    Menu(ligne.unite) {
                        ForEach(["pce", "m", "kg", "l", "rouleau", "sac", "boîte", "jeu"], id: \.self) { u in
                            Button(u) { ligne.unite = u }
                        }
                    }
                    .styleTexte(14, graisse: .medium)
                    .foregroundStyle(Color.bronze)
                    TextField("Désignation", text: $ligne.designation)
                        .styleTexte(16)
                    Button {
                        withAnimation(.endry) { bon.materiel.removeAll { $0.id == ligne.id } }
                    } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Color.encrePale)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Retirer \(ligne.designation)"))
                }
            }
            Button {
                withAnimation(.endry) { bon.materiel.append(LigneMateriel(designation: "")) }
            } label: { Label("Ajouter du matériel", systemImage: "plus.circle.fill") }
                .styleTexte(14, graisse: .semibold)
                .foregroundStyle(Color.bronze)
            Text("Sans prix : le bureau facture aux tarifs de l’entreprise.")
                .styleTexte(12, relativeTo: .caption)
                .foregroundStyle(Color.encrePale)
        }
        .disabled(bon.estSigne)

        SectionTerrain(titre: "Divers", icone: "car") {
            Toggle("Déplacement", isOn: $bon.deplacement)
                .styleTexte(16)
                .tint(Color.bronzeMoyen)
            TextField("Remarques (facultatif)", text: $bon.remarques, axis: .vertical)
                .styleTexte(15)
                .lineLimit(1...4)
                .focused($saisieActive)
        }
        .disabled(bon.estSigne)

        SectionTerrain(titre: "Photos", icone: "camera") {
            PhotosTerrain(photos: $photos, prefixe: bon.numero)
        }

        actions
    }

    private var dicteeCarte: some View {
        SectionTerrain(titre: "Dictée", icone: "waveform") {
            HStack(alignment: .center, spacing: Espace.m) {
                BoutonMicroCompact(ecoute: dictee.ecoute, niveau: dictee.niveau) {
                    Task { await dictee.basculer() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    if analyse {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Je remplis le bon…").styleTexte(14, graisse: .medium)
                        }
                    } else if dictee.ecoute {
                        Text(dictee.transcription.isEmpty ? "J’écoute…" : dictee.transcription)
                            .styleTexte(14)
                            .lineLimit(4)
                    } else {
                        Text("Dites les travaux, qui a travaillé combien de temps, et le matériel posé.")
                            .styleTexte(14)
                            .foregroundStyle(Color.encreDouce)
                        Text(ExtractionIA.disponible ? "Rempli par Apple Intelligence, sur l’iPhone." : "Rempli sur l’iPhone, sans réseau.")
                            .styleTexte(11, relativeTo: .caption2)
                            .foregroundStyle(Color.encrePale)
                    }
                }
                .animation(.fonduDoux, value: analyse)
            }
            if !texteDicte.isEmpty && !dictee.ecoute {
                Button {
                    Task { await remplir(depuis: texteDicte) }
                } label: { Label("Relire la dictée et remplir à nouveau", systemImage: "arrow.clockwise") }
                    .styleTexte(12, relativeTo: .caption, graisse: .semibold)
                    .foregroundStyle(Color.bronze)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if bon.estSigne {
            VStack(alignment: .leading, spacing: Espace.s) {
                HStack(spacing: Espace.s) {
                    if let signature, let image = UIImage(data: signature) {
                        Image(uiImage: image).resizable().scaledToFit().frame(height: 54)
                            .padding(6)
                            .background(Color.papier, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Signé par \(bon.signataire ?? "")", systemImage: "checkmark.seal.fill")
                            .styleTexte(15, graisse: .semibold)
                            .foregroundStyle(Color.vertControle)
                        Text("Le bon est verrouillé.").styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
                    }
                }
                Button {
                    Task { await transmettre() }
                } label: {
                    HStack(spacing: Espace.xs) {
                        if envoi { ProgressView().tint(Color.fond) } else { Image(systemName: "paperplane.fill") }
                        Text(envoi ? "Transmission…" : "Transmettre au bureau")
                    }
                }
                .buttonStyle(BoutonPrincipal())
                .disabled(envoi)
                .accessibilityIdentifier("transmettre-regie")
                Text("Le bureau prépare la facture ; elle n’ira au client qu’après votre Oui.")
                    .styleTexte(12, relativeTo: .caption)
                    .foregroundStyle(Color.encrePale)
            }
            .padding(.top, Espace.s)
        } else {
            VStack(alignment: .leading, spacing: Espace.xs) {
                ForEach(bon.manques, id: \.self) { m in
                    Label(m, systemImage: "circle.dashed").styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
                }
                Button {
                    dictee.arreter()
                    // Le clavier ne revient pas sur le formulaire au retour de la signature.
                    saisieActive = false
                    signaturePresentee = true
                } label: {
                    Label("Faire signer le client", systemImage: "signature")
                }
                .buttonStyle(BoutonPrincipal())
                .disabled(!bon.manques.isEmpty)
                .accessibilityIdentifier("faire-signer")
            }
            .padding(.top, Espace.s)
        }
    }

    // MARK: - Actions

    private func choisir(_ id: String?) {
        bon.chantierId = id
        if let d = app.dossier(id) {
            bon.chantier = d.titre
            bon.client = d.client
            bon.lieu = d.lieu
        }
    }

    private func remplir(depuis texte: String) async {
        analyse = true
        let r = await ExtractionIA.regie(texte, moi: moi)
        analyse = false
        withAnimation(.endry) {
            if !r.travaux.isEmpty {
                bon.travaux = bon.travaux.isEmpty ? r.travaux : bon.travaux + "\n" + r.travaux
            }
            for h in r.lignesHeures {
                if let i = bon.heures.firstIndex(where: { $0.intervenant.lowercased() == h.intervenant.lowercased() }) {
                    bon.heures[i].heures = h.heures
                } else {
                    bon.heures.append(h)
                }
            }
            bon.materiel += r.lignesMateriel
            if let d = r.deplacement { bon.deplacement = d }
        }
    }

    private func preparerPDF() {
        let data = PDFTerrain.regie(bon, signature: signature, entreprise: app.session.entreprise)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(bon.numero).pdf")
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
        pdf = url
    }

    private func transmettre() async {
        envoi = true
        let pdfData = pdf.flatMap { try? Data(contentsOf: $0) } ?? PDFTerrain.regie(bon, signature: signature, entreprise: app.session.entreprise)
        let r = await app.transmettre(bon.envoi(pdf: pdfData, signature: signature, photos: photos))
        envoi = false
        if case .refusee = r {} else { BrouillonRegie.effacer() }
        withAnimation(.endry) { resultat = r }
    }
}

// MARK: - Signature du client

/// Écran tourné vers le client : ce qu'il signe, sur papier clair, sans aucun prix.
struct SignatureClientView: View {
    var bon: BonRegie
    var signer: (String, Data) -> Void
    var annuler: () -> Void

    @State private var dessin = PKDrawing()
    @State private var nom = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.m) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BON DE RÉGIE · \(bon.numero)")
                            .font(Police.etiquette(11)).tracking(2).foregroundStyle(Color.bronzePapier)
                        Text(bon.chantier.isEmpty ? bon.client : bon.chantier)
                            .font(Police.titre(26, relativeTo: .title)).foregroundStyle(Color.encrePapier)
                        Text(DateEndry.courte(bon.date)).font(.subheadline).foregroundStyle(Color.encrePapierDouce)
                    }
                    Text(bon.travaux).font(.body).foregroundStyle(Color.encrePapier)
                    if !bon.heures.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(bon.heures) { h in
                                HStack {
                                    Text(h.intervenant)
                                    Spacer()
                                    Text(FormatSuisse.heures(h.heures)).fontWeight(.semibold).monospacedDigit()
                                }
                            }
                            Divider()
                            HStack {
                                Text("Total").fontWeight(.semibold)
                                Spacer()
                                Text(FormatSuisse.heures(bon.totalHeures)).fontWeight(.semibold).monospacedDigit()
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(Color.encrePapier)
                    }
                    if !bon.materiel.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(bon.materiel) { m in Text("• " + m.libelle) }
                        }
                        .font(.callout)
                        .foregroundStyle(Color.encrePapier)
                    }
                    Text(bon.deplacement ? "Déplacement compté." : "Sans déplacement.")
                        .font(.footnote).foregroundStyle(Color.encrePapierDouce)

                    TextField("Nom du signataire", text: $nom)
                        .textContentType(.name)
                        .font(.body.weight(.medium))
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.papierCreuse))
                        .accessibilityIdentifier("nom-signataire")

                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white)
                        Rectangle().fill(Color.papierCreuse).frame(height: 1).padding(.horizontal, 20).padding(.bottom, 44)
                        Text("Signez ici").font(.caption).foregroundStyle(Color.encrePapierDouce).padding(.leading, 20).padding(.bottom, 20)
                        ZoneSignature(dessin: $dessin)
                    }
                    .frame(height: 210)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.papierCreuse))

                    HStack {
                        Button("Effacer") { dessin = PKDrawing() }
                            .foregroundStyle(Color.bronzePapier)
                        Spacer()
                        Text("Aucun prix sur ce bon : la facture suivra.").font(.caption).foregroundStyle(Color.encrePapierDouce)
                    }

                    Button {
                        if let png = dessin.png() { signer(nom.trimmingCharacters(in: .whitespaces), png) }
                    } label: {
                        Label("Je confirme et je signe", systemImage: "signature")
                    }
                    .buttonStyle(BoutonPrincipal())
                    .disabled(!dessin.estSignature || nom.trimmingCharacters(in: .whitespaces).count < 2)
                    .accessibilityIdentifier("signer")
                }
                .padding(Espace.l)
            }
            .scrollDisabled(false)
            .background(Color.papier.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Retour", action: annuler).foregroundStyle(Color.bronzePapier) }
            }
        }
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Brouillon

/// Le bon en cours survit à un appel, à la fermeture de l'app ou à un redémarrage (le jour même).
enum BrouillonRegie {
    private static let cle = "brouillon-regie"

    static func enregistrer(_ bon: BonRegie) {
        guard !bon.estSigne, let data = try? JSONEncoder().encode(bon) else { return }
        UserDefaults.standard.set(data, forKey: cle)
    }

    /// Brouillon du jour, pour le même chantier (ou sans chantier demandé).
    static func lire(pour chantier: Dossier?) -> BonRegie? {
        guard !Configuration.testsUI, let data = UserDefaults.standard.data(forKey: cle),
              let bon = try? JSONDecoder().decode(BonRegie.self, from: data),
              bon.date == DateEndry.iso(Date()), !bon.estSigne else { return nil }
        if let chantier, bon.chantierId != chantier.id { return nil }
        return bon
    }

    static func effacer() {
        UserDefaults.standard.removeObject(forKey: cle)
    }
}
