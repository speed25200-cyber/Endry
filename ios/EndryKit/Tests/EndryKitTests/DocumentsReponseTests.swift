import Foundation
import XCTest
@testable import EndryKit

/// Documents joints aux réponses du bureau (v1.9) : aperçu et enregistrement dans la conversation.
final class DocumentsReponseTests: XCTestCase {
    func testLiensVersDesDocumentsExtraitsDuTexte() {
        let r = Piece.extraire(du: "Voici l’offre : [Offre OF-00037.pdf](/app/doc/offre/OF-00037) et le [site](https://exemple.ch).")
        XCTAssertEqual(r.pieces, [Piece(nom: "Offre OF-00037.pdf", url: "/app/doc/offre/OF-00037")])
        XCTAssertEqual(r.texte, "Voici l’offre : Offre OF-00037.pdf et le [site](https://exemple.ch).")
        XCTAssertEqual(r.pieces.first?.libelleType, "PDF")
        XCTAssertEqual(Piece(nom: "Heures septembre.xlsx", url: "/documents/heures.xlsx").libelleType, "Excel")
        XCTAssertTrue(Piece.extraire(du: "Rien à joindre [ici].").pieces.isEmpty)
    }

    func testDocumentsJointsALaReponse() throws {
        let json = #"{"statut": "repondu", "question_id": "Q-1", "reponse": "Le relevé est prêt.", "documents": [{"nom": "Relevé.pdf", "url": "/app/doc/releve/9"}]}"#
        let r = try JSONDecoder().decode(ReponseAgent.self, from: Data(json.utf8))
        XCTAssertEqual(r.documents.map(\.nom), ["Relevé.pdf"])
        let lien = #"{"statut": "repondu", "reponse": "Voici : [Offre.pdf](/app/doc/offre/OF-1)"}"#
        let r2 = try JSONDecoder().decode(ReponseAgent.self, from: Data(lien.utf8))
        XCTAssertEqual(r2.documents.map(\.url), ["/app/doc/offre/OF-1"])
        XCTAssertEqual(r2.reponse, "Voici : Offre.pdf")
    }

    @MainActor
    func testDocumentsGardesDansLeFil() throws {
        let modele = ModeleConversation(bureau: nil)
        let id = modele.consignerQuestion("Envoie-moi l’offre en PDF", source: .ecrit)
        modele.repondre(id, avec: ReponseAgent(statut: .repondu, reponse: "La voici.",
                                               documents: [Piece(nom: "Offre.pdf", url: "/app/doc/offre/OF-1")]))
        XCTAssertEqual(modele.reponse(a: id)?.documents?.map(\.nom), ["Offre.pdf"])
        let data = try JSONEncoder().encode(modele.messages)
        let relus = try JSONDecoder().decode([MessageConversation].self, from: data)
        XCTAssertEqual(relus.last?.documents?.first?.url, "/app/doc/offre/OF-1")
    }
}
