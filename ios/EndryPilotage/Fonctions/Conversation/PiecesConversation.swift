import EndryKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Photos et PDF joints à un message de la conversation (v1.10) : préparation avant l'envoi, vignettes dans le
/// champ d'écriture et dans la bulle du patron.
enum PiecesConversation {
    /// Photo (photothèque, appareil photo, fichier image) : toujours en JPEG lisible par le PC.
    static func photo(_ donnees: Data, rang: Int) async -> PieceSaisie? {
        guard let jpeg = await ImagePourPC.jpegHorsEcran(donnees) else { return nil }
        return PieceSaisie(nom: "photo-\(horodatage())-\(rang).jpg", typeMIME: "image/jpeg", donnees: jpeg, origine: .photo)
    }

    static func photo(_ image: UIImage, rang: Int) async -> PieceSaisie? {
        guard let jpeg = await ImagePourPC.jpegHorsEcran(image) else { return nil }
        return PieceSaisie(nom: "photo-\(horodatage())-\(rang).jpg", typeMIME: "image/jpeg", donnees: jpeg, origine: .photo)
    }

    /// Fichier choisi dans « Fichiers » : un PDF part tel quel, une image est convertie en JPEG.
    /// `nil` : fichier illisible ; l'erreur dit pourquoi un fichier lisible est refusé.
    static func fichier(_ url: URL, rang: Int) async throws(Refus) -> PieceSaisie? {
        let acces = url.startAccessingSecurityScopedResource()
        defer { if acces { url.stopAccessingSecurityScopedResource() } }
        guard let donnees = try? Data(contentsOf: url) else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .pdf) == true {
            guard donnees.count <= FormulaireMultipart.tailleMaxFichier else { throw Refus(nom: url.lastPathComponent) }
            return PieceSaisie(nom: url.lastPathComponent, typeMIME: "application/pdf", donnees: donnees, origine: .fichier)
        }
        return await photo(donnees, rang: rang)
    }

    struct Refus: Error {
        var nom: String
        var message: String { "« \(nom) » dépasse 15 Mo : le bureau ne peut pas le recevoir." }
    }

    private static func horodatage() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}

/// Pièces en attente d'envoi, au-dessus du champ d'écriture : une croix pour en retirer une.
struct PiecesAEnvoyer: View {
    var pieces: [PieceSaisie]
    var retirer: (PieceSaisie) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Espace.xs) {
                ForEach(pieces) { piece in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if piece.typeMIME.hasPrefix("image/") {
                                VignettePhoto(donnees: piece.donnees, cle: piece.id.uuidString)
                            } else {
                                EtiquetteDocument(nom: piece.nom)
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.filet, lineWidth: Espace.filet))

                        Button {
                            retirer(piece)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.fond)
                                .frame(width: 20, height: 20)
                                .background(Color.encre.opacity(0.8), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 5, y: -5)
                        .accessibilityLabel(Text("Retirer \(piece.nom)"))
                    }
                }
            }
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("pieces-conversation")
    }
}

/// Pièces d'un message envoyé, dans la bulle du patron : toucher = aperçu plein écran.
struct PiecesMessage: View {
    var pieces: [PieceMessage]
    var modele: ModeleConversation

    var body: some View {
        let colonnes = Array(repeating: GridItem(.fixed(88), spacing: 6), count: min(3, max(1, pieces.count)))
        LazyVGrid(columns: colonnes, alignment: .trailing, spacing: 6) {
            ForEach(pieces) { piece in
                VignettePieceMessage(piece: piece, modele: modele)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier("pieces-message")
    }
}

private struct VignettePieceMessage: View {
    @Environment(DocumentsConversation.self) private var documents
    var piece: PieceMessage
    var modele: ModeleConversation
    @State private var donnees: Data?

    var body: some View {
        Button {
            guard let local = modele.fichierLocal(de: piece), FileManager.default.fileExists(atPath: local.path) else { return }
            documents.apercu = local
        } label: {
            ZStack {
                Color.surfaceCreuse
                if piece.estImage {
                    if let donnees { VignettePhoto(donnees: donnees, cle: piece.id) }
                } else {
                    EtiquetteDocument(nom: piece.nom)
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.filet, lineWidth: Espace.filet))
        }
        .buttonStyle(.plain)
        .task(id: piece.id) {
            if piece.estImage { donnees = await modele.donnees(de: piece) }
        }
        .accessibilityLabel(Text(piece.estImage ? "Photo jointe" : "Document joint : \(piece.nom)"))
    }
}

/// Document (PDF) : icône et nom.
private struct EtiquetteDocument: View {
    var nom: String

    var body: some View {
        ZStack {
            Color.surfaceCreuse
            VStack(spacing: 3) {
                Image(systemName: "doc.text").font(.system(size: 20, weight: .light))
                Text(nom)
                    .styleTexte(9, relativeTo: .caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.bronze)
            .padding(4)
        }
    }
}
