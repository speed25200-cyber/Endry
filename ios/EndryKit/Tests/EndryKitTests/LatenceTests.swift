import Foundation
import XCTest
@testable import EndryKit

/// Conversation quasi instantanée avec le bureau (v1.8) : événements de réponse, réponse en flux, cadence.
final class LatenceTests: XCTestCase {
    func testEvenementReponseCompletOuSimpleSignal() throws {
        let complet = EvenementSSE(nom: "reponse", donnees: #"{"question_id": "Q-7", "statut": "repondu", "agent": "secretariat", "reponse": "Mme Gander a rappelé hier."}"#)
        let pret = try XCTUnwrap(complet.reponsePrete)
        XCTAssertEqual(pret.questionId, "Q-7")
        XCTAssertEqual(pret.reponse?.reponse, "Mme Gander a rappelé hier.")
        XCTAssertEqual(complet.sujet, .agents, "Le bureau est aussi relu.")

        let signal = EvenementSSE(nom: "reponse", donnees: #"{"question_id": "Q-8"}"#)
        XCTAssertEqual(signal.reponsePrete?.questionId, "Q-8")
        XCTAssertNil(signal.reponsePrete?.reponse, "Sans texte : l'app relit GET /questions/{id}.")

        XCTAssertNil(EvenementSSE(nom: "maj", donnees: #"{"quoi": "saisies"}"#).reponsePrete)
        XCTAssertNil(EvenementSSE(nom: "reponse", donnees: "illisible").reponsePrete)
    }

    func testReponsePartielle() {
        let partiel = EvenementSSE(nom: "reponse_partielle", donnees: #"{"question_id": "Q-9", "texte": "Deux factures"}"#)
        XCTAssertEqual(partiel.reponsePartielle?.questionId, "Q-9")
        XCTAssertEqual(partiel.reponsePartielle?.texte, "Deux factures")
        XCTAssertNil(partiel.sujet, "Un fragment ne déclenche aucun rechargement.")
    }

    func testCadenceDeSondageSerreeAuDebut() {
        XCTAssertEqual(BureauClaude.intervalle(apres: .seconds(1)), .milliseconds(400))
        XCTAssertEqual(BureauClaude.intervalle(apres: .seconds(15)), .milliseconds(800))
        XCTAssertEqual(BureauClaude.intervalle(apres: .seconds(90)), .milliseconds(1_500))
        let attente = Requete.suiviQuestion("Q-1", attente: 20)
        XCTAssertEqual(attente.parametres, [Parametre("attendre", "20")])
        XCTAssertGreaterThan(attente.delai, 20)
    }

    @MainActor
    func testReponseArriveeParEvenementEtTexteEnFlux() async {
        let modele = ModeleConversation(bureau: nil)
        let id = modele.consignerQuestion("Qui me doit de l’argent ?", source: .ecrit)
        modele.attendre(id, suivi: .question(id: "Q-42", agent: "comptabilite"), message: nil)

        // La réponse s'écrit : elle apparaît mot à mot, sans quitter l'attente.
        modele.recevoirPartiel(questionId: "Q-42", texte: "Deux")
        modele.recevoirPartiel(questionId: "Q-42", texte: "Deux factures")
        modele.recevoirPartiel(questionId: "Q-42", texte: "Deux")
        XCTAssertEqual(modele.reponse(a: id)?.texte, "Deux factures", "Un fragment en retard n'efface rien.")
        XCTAssertEqual(modele.reponse(a: id)?.etat, .attente)

        // L'événement final, réponse jointe : affichée sans aucune requête.
        await modele.recevoirReponse(questionId: "Q-42", reponse: ReponseAgent(statut: .repondu, questionId: "Q-42",
                                                                               reponse: "Deux factures sont ouvertes."))
        XCTAssertEqual(modele.reponse(a: id)?.etat, .recu)
        XCTAssertEqual(modele.reponse(a: id)?.texte, "Deux factures sont ouvertes.")

        // Un fragment tardif ne touche plus une réponse reçue.
        modele.recevoirPartiel(questionId: "Q-42", texte: "Deux factures sont ouvertes. Et")
        XCTAssertEqual(modele.reponse(a: id)?.texte, "Deux factures sont ouvertes.")
    }
}
