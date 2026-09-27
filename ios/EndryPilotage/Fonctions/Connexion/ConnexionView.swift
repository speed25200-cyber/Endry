import EndryKit
import SwiftUI
import UIKit
import VisionKit

/// « Collez votre lien d'accès » : presse-papiers, saisie manuelle ou QR code.
struct ConnexionView: View {
    var enFeuille = false

    @Environment(ModeleApp.self) private var modele
    @Environment(\.dismiss) private var fermer
    @State private var texte = ""
    @State private var enCours = false
    @State private var erreur: String?
    @State private var scanPresente = false
    @State private var presseAPapiersAUnLien = false
    @State private var visible = false
    @FocusState private var champActif: Bool

    var body: some View {
        ZStack {
            MatiereEspresso(rayon: 0).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Espace.l) {
                    entete
                        .apparitionEnCascade(index: 0, visible: visible)

                    if modele.session.connexionPerdue {
                        Label("Connexion perdue : collez le nouveau lien.", systemImage: "link.badge.plus")
                            .styleTexte(15, relativeTo: .subheadline, graisse: .semibold)
                            .foregroundStyle(Color.orClair)
                            .padding(Espace.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: 0xC4583C).opacity(0.25), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    panneauLien
                        .apparitionEnCascade(index: 1, visible: visible)

                    if !enFeuille {
                        Button {
                            modele.activerDemo()
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Découvrir en mode démo")
                            }
                            .styleTexte(15, relativeTo: .subheadline, graisse: .medium)
                            .foregroundStyle(Color.orClair.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Espace.s)
                        }
                        .accessibilityIdentifier("bouton-demo")
                        .apparitionEnCascade(index: 2, visible: visible)
                    }

                    Text("Le lien vous est envoyé par e-mail par l’assistant du bureau. Il est échangé contre un jeton rangé dans le trousseau de l’iPhone ; aucun mot de passe n’est demandé.")
                        .styleTexte(12, relativeTo: .caption)
                        .foregroundStyle(Color.orClair.opacity(0.5))
                        .apparitionEnCascade(index: 3, visible: visible)
                }
                .padding(.horizontal, Espace.l)
                .padding(.top, enFeuille ? Espace.xl : 72)
                .padding(.bottom, Espace.xxl)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            visible = true
            presseAPapiersAUnLien = UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings
        }
        .sheet(isPresented: $scanPresente) {
            ScanQRView { contenu in
                scanPresente = false
                texte = contenu
                Task { await connecter() }
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.error, trigger: erreur) { _, nouveau in nouveau != nil }
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            LogoEndry(taille: 56)
            Text("Endry Pilotage")
                .styleTitre(40, relativeTo: .largeTitle)
                .foregroundStyle(Color.orClair)
            Text("Collez votre lien d’accès pour relier l’iPhone à l’assistant du bureau.")
                .styleTexte(17, relativeTo: .body)
                .foregroundStyle(Color.orClair.opacity(0.72))
        }
    }

    private var panneauLien: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            // Bouton système : colle sans alerte de confidentialité (équivalent SwiftUI de UIPasteControl).
            PasteButton(payloadType: String.self) { chaines in
                guard let premier = chaines.first else { return }
                Task { @MainActor in
                    texte = premier
                    await connecter()
                }
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.titleAndIcon)
            .tint(Color.or)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("coller-lien")

            if presseAPapiersAUnLien {
                Text("Un lien semble copié : touchez « Coller ».")
                    .styleTexte(12, relativeTo: .caption, graisse: .medium)
                    .foregroundStyle(Color.or.opacity(0.8))
            }

            HStack(spacing: Espace.xs) {
                Rectangle().fill(Color.or.opacity(0.2)).frame(height: 0.5)
                Text("ou").styleTexte(12, relativeTo: .caption).foregroundStyle(Color.orClair.opacity(0.5))
                Rectangle().fill(Color.or.opacity(0.2)).frame(height: 0.5)
            }

            HStack(spacing: Espace.xs) {
                TextField("", text: $texte, prompt: Text("https://…/app/acces/…").foregroundStyle(Color.orClair.opacity(0.35)), axis: .vertical)
                    .lineLimit(1...3)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($champActif)
                    .onSubmit { Task { await connecter() } }
                    .styleTexte(15, relativeTo: .body)
                    .foregroundStyle(Color.orClair)
                    .padding(.horizontal, Espace.m)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.or.opacity(champActif ? 0.6 : 0.2), lineWidth: 0.8))
                    .accessibilityIdentifier("champ-lien")

                if DataScannerViewController.isSupported {
                    Button {
                        scanPresente = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.or)
                            .frame(width: 52, height: 52)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityLabel(Text("Scanner un QR code"))
                }
            }

            if let erreur {
                Label(erreur, systemImage: "exclamationmark.circle.fill")
                    .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                    .foregroundStyle(Color(hex: 0xF0A48C))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                Task { await connecter() }
            } label: {
                HStack(spacing: Espace.xs) {
                    if enCours { ProgressView().tint(Color.espresso) }
                    Text(enCours ? "Connexion…" : "Se connecter")
                }
            }
            .buttonStyle(BoutonPrincipal(couleur: .or))
            .disabled(texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || enCours)
            .accessibilityIdentifier("bouton-connecter")
        }
        .padding(Espace.l)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: Espace.rayon, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Espace.rayon, style: .continuous).strokeBorder(Color.or.opacity(0.18), lineWidth: 0.6))
        .animation(.endry, value: erreur)
    }

    private func connecter() async {
        guard !enCours else { return }
        champActif = false
        enCours = true
        erreur = nil
        defer { enCours = false }
        do {
            try await modele.connecter(texte: texte)
            if enFeuille { fermer() }
        } catch {
            erreur = error.message
        }
    }
}

/// Lecteur de QR code (VisionKit).
struct ScanQRView: UIViewControllerRepresentable {
    var surLecture: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controleur: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controleur: DataScannerViewController, coordinator: Coordinateur) {
        controleur.stopScanning()
    }

    func makeCoordinator() -> Coordinateur { Coordinateur(surLecture: surLecture) }

    final class Coordinateur: NSObject, DataScannerViewControllerDelegate {
        let surLecture: (String) -> Void
        private var lu = false

        init(surLecture: @escaping (String) -> Void) {
            self.surLecture = surLecture
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !lu else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let valeur = code.payloadStringValue, valeur.contains(LienAcces.marqueur) {
                    lu = true
                    surLecture(valeur)
                    return
                }
            }
        }
    }
}

#Preview {
    ConnexionView().environment(ModeleApp())
}
