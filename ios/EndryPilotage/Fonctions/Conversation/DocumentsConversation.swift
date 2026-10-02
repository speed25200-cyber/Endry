import EndryKit
import PDFKit
import SwiftUI

/// Documents joints aux réponses du bureau (PDF, Excel, Word…) : téléchargés une fois avec le jeton de l'appareil,
/// vignette de la première page, aperçu plein écran (QuickLook) et enregistrement dans Fichiers ou partage.
@MainActor
@Observable
final class DocumentsConversation {
    struct Pret {
        var fichier: URL
        var vignette: UIImage?
    }

    private(set) var prets: [String: Pret] = [:]
    private(set) var enCours: Set<String> = []
    private(set) var erreurs: [String: String] = [:]
    /// Document montré en plein écran (QuickLook : feuilleter, zoomer, enregistrer, partager).
    var apercu: URL?

    func preparer(_ piece: Piece, api: (any EndryAPI)?) async {
        guard prets[piece.url] == nil, !enCours.contains(piece.url), let api else { return }
        enCours.insert(piece.url)
        erreurs[piece.url] = nil
        defer { enCours.remove(piece.url) }
        do {
            let fichier = try await api.telechargerDocument(piece.url, nom: piece.nom)
            prets[piece.url] = Pret(fichier: fichier, vignette: Self.premierePage(fichier))
        } catch {
            erreurs[piece.url] = error.message
        }
    }

    /// Première page d'un PDF en vignette (les autres types gardent leur icône).
    private static func premierePage(_ fichier: URL) -> UIImage? {
        guard fichier.pathExtension.lowercased() == "pdf", let page = PDFDocument(url: fichier)?.page(at: 0) else { return nil }
        return page.thumbnail(of: CGSize(width: 180, height: 240), for: .cropBox)
    }
}

/// Les documents d'une réponse, sous le texte : vignette, nom, type ; toucher = aperçu, flèche = enregistrer.
struct CartesDocuments: View {
    @Environment(ModeleApp.self) private var app
    @Environment(DocumentsConversation.self) private var documents
    var pieces: [Piece]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(pieces) { piece in
                carte(piece)
                    .task(id: piece.url) { await documents.preparer(piece, api: app.session.api) }
            }
        }
        .padding(.top, 4)
    }

    private func carte(_ piece: Piece) -> some View {
        let pret = documents.prets[piece.url]
        let erreur = documents.erreurs[piece.url]
        return HStack(spacing: 12) {
            Group {
                if let vignette = pret?.vignette {
                    Image(uiImage: vignette)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.signal.opacity(0.12)
                        Image(systemName: Self.icone(piece))
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Color.signal)
                    }
                }
            }
            .frame(width: 46, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.filet, lineWidth: Espace.filet))

            VStack(alignment: .leading, spacing: 3) {
                Text(piece.nom)
                    .styleTexte(15, relativeTo: .subheadline, graisse: .medium)
                    .foregroundStyle(Color.encre)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Group {
                    if let erreur {
                        Text(erreur).foregroundStyle(Color.rouille)
                    } else if pret == nil {
                        Text("\(piece.libelleType) · préparation…")
                    } else {
                        Text("\(piece.libelleType) · toucher pour l’aperçu")
                    }
                }
                .font(Police.mono(11.5))
                .foregroundStyle(Color.encreDouce)
                .lineLimit(2)
            }
            Spacer(minLength: 4)
            if let fichier = pret?.fichier {
                // Partager ou « Enregistrer dans Fichiers ».
                ShareLink(item: fichier) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.encre)
                        .frame(width: 40, height: 40)
                        .verreMaison(Circle(), interactif: true)
                }
                .accessibilityLabel(Text("Enregistrer ou partager \(piece.nom)"))
            } else if erreur != nil {
                Button {
                    Task { await documents.preparer(piece, api: app.session.api) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.encre)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel(Text("Réessayer"))
            } else {
                ProgressView().tint(Color.signal).frame(width: 40, height: 40)
            }
        }
        .padding(10)
        .frame(maxWidth: 420, alignment: .leading)
        .tuileMaison(rayon: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if let fichier = pret?.fichier { documents.apercu = fichier }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Ouvre l’aperçu du document"))
        .accessibilityIdentifier("document-\(piece.nom)")
    }

    static func icone(_ piece: Piece) -> String {
        switch piece.libelleType {
        case "PDF": "doc.richtext"
        case "Excel": "tablecells"
        case "Word": "doc.text"
        case "Image": "photo"
        default: "doc"
        }
    }
}
