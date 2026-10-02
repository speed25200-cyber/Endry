import EndryKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// Saisie terrain : dictée, scanner de documents, photos, envoi au bureau.
struct SaisieView: View {
    @Environment(ModeleApp.self) private var app
    @Bindable var modele: ModeleSaisie

    @State private var dictee = Dictee()
    @State private var base = ""
    @State private var selectionPhotos: [PhotosPickerItem] = []
    @State private var scannerPresente = false
    @State private var cameraPresentee = false
    @State private var photosPresentees = false
    @FocusState private var focusTexte: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.l) {
                    VStack(alignment: .leading, spacing: Espace.xxs) {
                        Text("Saisie terrain").styleSurtitre()
                        Text("Dites-le, c’est transmis.")
                            .font(Police.serif(36, relativeTo: .largeTitle))
                            .foregroundStyle(Color.encre)
                    }
                    .padding(.top, Espace.m)

                    RangeeOutilsTerrain()

                    if case .transmis(let message) = modele.etat {
                        confirmation(message)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else if modele.etat == .enAttente {
                        confirmation("Pas de réseau : la saisie est gardée sur l’iPhone et partira toute seule dès le retour de la connexion.",
                                     titre: "Gardé", icone: "tray.and.arrow.up", couleur: .ambre)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        editeur
                    }

                    HistoriqueSaisies(modele: modele)
                }
                .largeurLisible()
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, 130)
                .verrouillerLargeur()
                .animation(.endry, value: modele.etat)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .background(FondAmbiant())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: dictee.transcription) { _, nouvelle in
            if !nouvelle.isEmpty { modele.texte = base + nouvelle }
        }
        .photosPicker(isPresented: $photosPresentees, selection: $selectionPhotos, maxSelectionCount: 10, matching: .images, photoLibrary: .shared())
        .onChange(of: selectionPhotos) { _, elements in
            Task { await importer(elements) }
        }
        .fullScreenCover(isPresented: $scannerPresente) {
            ScannerDocuments { pages in
                scannerPresente = false
                ajouterScan(pages)
            } annuler: {
                scannerPresente = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $cameraPresentee) {
            CameraPhoto { image in
                cameraPresentee = false
                guard let image else { return }
                Task {
                    guard let data = await ImagePourPC.jpegHorsEcran(image) else { return }
                    modele.ajouter(PieceSaisie(nom: "photo-\(horodatage()).jpg", typeMIME: "image/jpeg", donnees: data, origine: .photo))
                }
            }
            .ignoresSafeArea()
        }
        .onDisappear { dictee.arreter() }
        .task { await modele.chargerHistorique() }
        .sensoryFeedback(.success, trigger: modele.etat) { _, nouveau in
            if case .transmis = nouveau { return true }
            return false
        }
    }

    // MARK: - Éditeur

    private var editeur: some View {
        VStack(alignment: .leading, spacing: Espace.l) {
            MicroAnime(ecoute: dictee.ecoute, niveau: dictee.niveau, historique: dictee.historique) {
                Task {
                    if !dictee.ecoute {
                        focusTexte = false
                        let t = modele.texte
                        base = t.isEmpty || t.hasSuffix(" ") ? t : t + " "
                    }
                    await dictee.basculer()
                }
            }
            .frame(maxWidth: .infinity)

            Group {
                switch dictee.etat {
                case .ecoute:
                    Text("J’écoute… (français de Suisse)")
                case .refuse(let m), .indisponible(let m):
                    Text(m).foregroundStyle(Color.rouille)
                case .repos:
                    Text("Touchez le micro et parlez : bons, heures, matériel, remarques de chantier.")
                }
            }
            .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
            .foregroundStyle(Color.encreDouce)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            ZStack(alignment: .topLeading) {
                if modele.texte.isEmpty {
                    Text("Ou écrivez ici…")
                        .styleTexte(16)
                        .foregroundStyle(Color.encrePale)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $modele.texte)
                    .styleTexte(16)
                    .scrollContentBackground(.hidden)
                    .focused($focusTexte)
                    .frame(minHeight: 120)
                    .accessibilityIdentifier("texte-saisie")
            }
            .padding(Espace.s)
            .verreMaison(RoundedRectangle(cornerRadius: 24, style: .continuous))

            HStack(spacing: Espace.s) {
                if VNDocumentCameraViewController.isSupported {
                    boutonAjout("Scanner", icone: "doc.viewfinder") { scannerPresente = true }
                }
                boutonAjout("Photos", icone: "photo.on.rectangle") { photosPresentees = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    boutonAjout("Caméra", icone: "camera") { cameraPresentee = true }
                }
            }

            if !modele.pieces.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Espace.s) {
                        ForEach(modele.pieces) { piece in
                            VignettePiece(piece: piece) {
                                withAnimation(.endry) { modele.retirer(piece) }
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, Espace.xxs)
                }
                .scrollClipDisabled()
                .animation(.endry, value: modele.pieces.map(\.id))
            }

            if case .erreur(let message) = modele.etat {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                    .foregroundStyle(Color.rouille)
            }

            Button {
                dictee.arreter()
                focusTexte = false
                Task { await modele.envoyer() }
            } label: {
                HStack(spacing: Espace.xs) {
                    if modele.etat == .envoi {
                        ProgressView().tint(Color.fond)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(modele.etat == .envoi ? "Transmission…" : "Transmettre au bureau")
                }
            }
            .buttonStyle(BoutonPrincipal())
            .disabled(!modele.peutEnvoyer || app.session.api == nil)
            .accessibilityIdentifier("transmettre")
        }
    }

    private func confirmation(_ message: String, titre: String = "Transmis", icone: String = "checkmark", couleur: Color = .vertControle) -> some View {
        VStack(spacing: Espace.l) {
            ZStack {
                Circle().fill(couleur.opacity(0.12)).frame(width: 120, height: 120)
                Image(systemName: icone)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(couleur)
                    .symbolEffect(.bounce, value: message)
            }
            Text(titre).styleTitre(32, relativeTo: .largeTitle).foregroundStyle(Color.encre)
            Text(message).styleTexte(16).foregroundStyle(Color.encreDouce).multilineTextAlignment(.center)
            Button("Nouvelle saisie") {
                withAnimation(.endry) { modele.recommencer() }
                selectionPhotos = []
            }
            .buttonStyle(BoutonSecondaire())
            .accessibilityIdentifier("nouvelle-saisie")
        }
        .padding(Espace.xl)
        .frame(maxWidth: .infinity)
        .surfaceCarte()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("confirmation-transmis")
    }

    private func boutonAjout(_ titre: String, icone: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { etiquetteAjout(titre, icone: icone) }
            .buttonStyle(.plain)
    }

    private func etiquetteAjout(_ titre: String, icone: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icone).font(.system(size: 20, weight: .medium))
            Text(titre).styleTexte(12, relativeTo: .caption, graisse: .semibold)
        }
        .foregroundStyle(Color.encre)
        .frame(maxWidth: .infinity, minHeight: 72)
        .surfaceCarte(rayon: 18)
    }

    // MARK: - Pièces

    private func importer(_ elements: [PhotosPickerItem]) async {
        guard !elements.isEmpty else { return }
        for element in elements {
            guard let data = try? await element.loadTransferable(type: Data.self) else { continue }
            // HEIC, PNG ou JPEG : toujours converti en JPEG 0,85, 2560 px au plus (lisible par le PC).
            guard let donnees = await ImagePourPC.jpegHorsEcran(data) else { continue }
            let ext = "jpg"
            let mime = "image/jpeg"
            modele.ajouter(PieceSaisie(nom: "photo-\(horodatage())-\(modele.pieces.count + 1).\(ext)", typeMIME: mime, donnees: donnees, origine: .photo))
        }
        selectionPhotos = []
    }

    private func ajouterScan(_ pages: [UIImage]) {
        guard !pages.isEmpty else { return }
        // Un scan de plusieurs pages devient un seul PDF (rendu hors du fil principal).
        Task {
            let pdf = await ImagePourPC.pdfHorsEcran(pages)
            modele.ajouter(PieceSaisie(nom: "scan-\(horodatage()).pdf", typeMIME: "application/pdf", donnees: pdf, origine: .scan))
        }
    }

    private func horodatage() -> String { Self.formatHorodatage.string(from: Date()) }

    private static let formatHorodatage: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}

private struct VignettePiece: View {
    var piece: PieceSaisie
    var retirer: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if piece.typeMIME.hasPrefix("image/") {
                    VignettePhoto(donnees: piece.donnees, cle: piece.id.uuidString)
                } else {
                    ZStack {
                        Color.surfaceCreuse
                        VStack(spacing: 4) {
                            Image(systemName: piece.origine == .scan ? "doc.viewfinder" : "doc")
                                .font(.system(size: 24, weight: .light))
                            Text(piece.tailleLisible).styleTexte(10, relativeTo: .caption2)
                        }
                        .foregroundStyle(Color.bronze)
                    }
                }
            }
            .frame(width: 84, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.filet, lineWidth: 0.5))

            Button(action: retirer) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.fond)
                    .frame(width: 22, height: 22)
                    .background(Color.encre.opacity(0.8), in: Circle())
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel(Text("Retirer \(piece.nom)"))
        }
    }
}

/// Scanner de documents VisionKit (bons de livraison, factures surlignées…).
struct ScannerDocuments: UIViewControllerRepresentable {
    var terminer: ([UIImage]) -> Void
    var annuler: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controleur = VNDocumentCameraViewController()
        controleur.delegate = context.coordinator
        return controleur
    }

    func updateUIViewController(_ controleur: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinateur { Coordinateur(terminer: terminer, annuler: annuler) }

    final class Coordinateur: NSObject, VNDocumentCameraViewControllerDelegate {
        let terminer: ([UIImage]) -> Void
        let annuler: () -> Void

        init(terminer: @escaping ([UIImage]) -> Void, annuler: @escaping () -> Void) {
            self.terminer = terminer
            self.annuler = annuler
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            terminer((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            annuler()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            annuler()
        }
    }
}

/// Appareil photo simple.
struct CameraPhoto: UIViewControllerRepresentable {
    var terminer: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controleur = UIImagePickerController()
        controleur.sourceType = .camera
        controleur.delegate = context.coordinator
        return controleur
    }

    func updateUIViewController(_ controleur: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinateur { Coordinateur(terminer: terminer) }

    final class Coordinateur: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let terminer: (UIImage?) -> Void

        init(terminer: @escaping (UIImage?) -> Void) {
            self.terminer = terminer
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            terminer(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            terminer(nil)
        }
    }
}

#Preview("Saisie — démo") {
    let app = ModeleApp()
    app.activerDemo()
    return SaisieView(modele: app.saisie!)
        .environment(app)
}

/// Historique des saisies : gardées sur l'iPhone, puis Transmis → En cours → Traité → Décision prête.
struct HistoriqueSaisies: View {
    var modele: ModeleSaisie
    @Environment(ModeleApp.self) private var app

    var body: some View {
        if !modele.enAttente.isEmpty || !modele.historique.isEmpty {
            VStack(alignment: .leading, spacing: Espace.s) {
                EnTeteSection(titre: "Mes saisies", detail: modele.enAttente.isEmpty ? nil : "\(modele.enAttente.count) en attente")
                VStack(spacing: 0) {
                    ForEach(modele.enAttente) { s in
                        ligne(texte: s.libelle, date: s.cree, photos: s.fichiers.count, statut: .attente, resume: nil, reference: nil)
                        Rectangle().fill(Color.filet).frame(height: 0.5)
                    }
                    ForEach(Array(modele.historique.prefix(8).enumerated()), id: \.element.id) { index, s in
                        ligne(texte: BureauClaude.libelle(s.texte), date: s.cree.flatMap(DateEndry.lire), photos: s.photos, statut: s.statut,
                              resume: s.resume, reference: s.decisionReference)
                        if index < min(modele.historique.count, 8) - 1 {
                            Rectangle().fill(Color.filet).frame(height: 0.5)
                        }
                    }
                }
                .padding(.horizontal, Espace.m)
                .surfaceCarte(rayon: 22)
            }
            .animation(.endry, value: modele.historique.map(\.id))
        }
    }

    private func ligne(texte: String, date: Date?, photos: Int, statut: StatutSaisie, resume: String?, reference: String?) -> some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(texte.isEmpty ? "Photos" : texte)
                    .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                    .foregroundStyle(Color.encre)
                    .lineLimit(2)
                Spacer(minLength: Espace.xs)
                if let date {
                    Text(DateEndry.ilYa(date)).styleTexte(11, relativeTo: .caption2).foregroundStyle(Color.encrePale)
                }
            }
            FriseStatut(statut: statut, decisionPrete: reference != nil && statut == .traite)
            HStack(spacing: Espace.s) {
                if photos > 0 {
                    Label("\(photos)", systemImage: "photo").styleTexte(11, relativeTo: .caption2).foregroundStyle(Color.encrePale)
                }
                if let resume {
                    Text(resume).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encreDouce).lineLimit(2)
                }
                Spacer(minLength: 0)
                if let reference, statut == .traite {
                    Button {
                        app.ouvrir(reference: reference)
                    } label: {
                        Label("Voir la décision", systemImage: "arrow.right.circle.fill")
                            .styleTexte(12, relativeTo: .caption, graisse: .semibold)
                            .foregroundStyle(Color.bronze)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, Espace.s)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(statut.libelle))
    }
}

/// Frise Transmis → En cours → Traité → Décision prête.
struct FriseStatut: View {
    var statut: StatutSaisie
    var decisionPrete: Bool

    private let etapes = ["Transmis", "En cours", "Traité", "Décision prête"]

    var body: some View {
        let atteinte = statut == .attente ? -1 : decisionPrete ? 3 : min(statut.etape, 2) + (statut == .traite ? 0 : -1)
        HStack(spacing: 4) {
            if statut == .attente {
                Label("Gardé sur l’iPhone", systemImage: "tray.and.arrow.up")
                    .styleTexte(11, relativeTo: .caption2, graisse: .semibold)
                    .foregroundStyle(Color.ambre)
            } else if statut == .erreur {
                Label("Erreur de traitement", systemImage: "exclamationmark.triangle")
                    .styleTexte(11, relativeTo: .caption2, graisse: .semibold)
                    .foregroundStyle(Color.rouille)
            } else {
                ForEach(etapes.indices, id: \.self) { i in
                    let fait = i <= atteinte
                    Capsule()
                        .fill(fait ? AnyShapeStyle(.degradeOr) : AnyShapeStyle(Color.surfaceCreuse))
                        .frame(height: 4)
                        .overlay(alignment: .bottomLeading) {
                            Text(etapes[i])
                                .styleTexte(9, relativeTo: .caption2, graisse: i == atteinte ? .semibold : .regular)
                                .foregroundStyle(fait ? Color.encreDouce : Color.encrePale)
                                .fixedSize()
                                .offset(y: 12)
                        }
                }
            }
        }
        .padding(.bottom, statut == .attente || statut == .erreur ? 0 : 12)
        .accessibilityHidden(true)
    }
}
