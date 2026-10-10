import Foundation
import XCTest
@testable import {{PREFIXE}}Kit

/// Tests de contrat (issus du skill app-pilotage-entreprise) : le décodage tolère un serveur qui évolue.
final class ContratTests: XCTestCase {
    func testDecisionTolerante() throws {
        let json = #"[{"id": "D-1", "titre": "Envoyer l'offre OF-00012", "envoi_tiers": "oui", "pieces": [{"nom": "OF-00012.pdf", "url": "/app/doc/offre/OF-00012"}, 42]}, "illisible"]"#
        let cartes = try JSONDecoder().decode([ElementOuNil<Carte>].self, from: Data(json.utf8)).compactMap(\.valeur)
        XCTAssertEqual(cartes.count, 1)
        XCTAssertTrue(cartes[0].envoiTiers, "« oui » est lu comme vrai : glissement obligatoire.")
        XCTAssertEqual(cartes[0].pieces.map(\.libelleType), ["PDF"], "Un élément invalide ne casse pas la liste.")
    }

    func testDocumentsDansLaReponse() throws {
        let json = #"{"statut": "repondu", "question_id": "Q-1", "reponse": "Voici [Offre OF-00037.pdf](/app/doc/offre/OF-00037).", "documents": [{"nom": "Tableau.xlsx", "url": "/app/doc/x/1"}]}"#
        let r = try JSONDecoder().decode(ReponseAgent.self, from: Data(json.utf8))
        XCTAssertEqual(r.reponse, "Voici Offre OF-00037.pdf.")
        XCTAssertEqual(Set(r.documents.map(\.nom)), ["Tableau.xlsx", "Offre OF-00037.pdf"])
    }

    func testMontantsSuisses() {
        XCTAssertEqual(Double.depuisTexteSuisse("CHF 13’695.45"), 13_695.45)
        XCTAssertEqual(Double.depuisTexteSuisse("1 200.–"), 1_200)
    }

    func testJetonJamaisVersUnAutreHote() throws {
        let client = ClientAPI(base: URL(string: "https://bureau.exemple.invalid")!, jeton: "fictif")
        XCTAssertNotNil(try client.construire(.decisions).value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(try client.construire(Requete(.get, "https://autre.exemple.invalid/doc.pdf")).value(forHTTPHeaderField: "Authorization"))
    }

    func testLongPoll() {
        let r = Requete.suiviQuestion("Q-1", attente: 20)
        XCTAssertEqual(r.parametres["attendre"], "20")
        XCTAssertGreaterThan(r.delai, 20)
    }

    func testEtapeTolerante() {
        XCTAssertEqual(EtapeDossier(texte: "Planifiée"), .planifiee)
        XCTAssertEqual(EtapeDossier(texte: "PAYE"), .payee)
    }
}

private struct ElementOuNil<T: Decodable>: Decodable {
    let valeur: T?
    init(from decoder: Decoder) throws { valeur = try? T(from: decoder) }
}
