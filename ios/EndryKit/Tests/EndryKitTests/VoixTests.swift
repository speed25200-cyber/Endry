import XCTest
@testable import EndryKit

final class ProtocoleRealtimeTests: XCTestCase {
    func testLectureEvenements() {
        func lire(_ s: String) -> EvenementRealtime { EvenementRealtime.lire(Data(s.utf8)) }
        XCTAssertEqual(lire(#"{"type":"input_audio_buffer.speech_started"}"#), .paroleDebut)
        XCTAssertEqual(lire(#"{"type":"conversation.item.input_audio_transcription.delta","delta":"Combien"}"#),
                       .transcriptionPatron(texte: "Combien", finale: false))
        XCTAssertEqual(lire(#"{"type":"response.output_audio.delta","item_id":"it_1","delta":"AAEC"}"#), .audio(Data([0, 1, 2]), itemId: "it_1"))
        XCTAssertEqual(lire(#"{"type":"response.function_call_arguments.done","call_id":"c1","name":"chantier","arguments":"{\"id\":\"24\"}"}"#),
                       .appelOutil(callId: "c1", nom: "chantier", arguments: #"{"id":"24"}"#))
        XCTAssertEqual(lire(#"{"type":"error","error":{"message":"expired"}}"#), .erreur("expired"))
        XCTAssertEqual(lire("pas du json"), .autre("illisible"))
    }

    func testConfigurationSession() throws {
        let json = #"{"disponible":true,"client_secret":"ek","modele":"gpt-realtime","voix":"marin","instructions":"Assistant Endry.","outils":[{"name":"accueil","description":"Résumé","parameters":{"type":"object","properties":{}}}]}"#
        let session = try JSONDecoder().decode(SessionVoix.self, from: Data(json.utf8))
        let data = CommandeRealtime.configuration(session: session, vocabulaire: ["Bexio", "Mapress"])
        let objet = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(objet["type"] as? String, "session.update")
        let s = try XCTUnwrap(objet["session"] as? [String: Any])
        XCTAssertEqual(s["type"] as? String, "realtime")
        XCTAssertTrue((s["instructions"] as? String ?? "").contains("Mapress"))
        XCTAssertTrue((s["instructions"] as? String ?? "").contains("proposer_decision"))
        let outils = try XCTUnwrap(s["tools"] as? [[String: Any]])
        XCTAssertEqual(outils.first?["name"] as? String, "accueil")
        let audio = try XCTUnwrap(s["audio"] as? [String: Any])
        XCTAssertEqual((audio["output"] as? [String: Any])?["voice"] as? String, "marin")
    }
}

final class OutilsVoixTests: XCTestCase {
    func testOutilsLectureEtProposition() async throws {
        let executeur = ExecuteurOutils(api: APIDemo(latence: .zero))
        let accueil = await executeur.executer(nom: "accueil", arguments: "{}")
        XCTAssertTrue(accueil.sortie.contains("V-7K3F9Q"))
        let chantier = await executeur.executer(nom: "chantier", arguments: #"{"id": 18}"#)
        XCTAssertEqual(chantier.effet, .afficherChantier("18"))
        XCTAssertTrue(chantier.sortie.contains("OF-00031"))
        let proposition = await executeur.executer(nom: "proposer_decision", arguments: #"{"reference":"V-2M8R4T"}"#)
        XCTAssertEqual(proposition.effet, .afficherDecision("V-2M8R4T"))
        XCTAssertTrue(proposition.sortie.contains("geste"))
        let saisie = await executeur.executer(nom: "saisie", arguments: #"{"texte":"Prépare une facture pour la régie Dubois"}"#)
        XCTAssertTrue(saisie.sortie.contains("Transmis"))
        let inconnu = await executeur.executer(nom: "virer_argent", arguments: "{}")
        XCTAssertTrue(inconnu.sortie.contains("Outil inconnu"))
    }
}

final class RepondeurLocalTests: XCTestCase {
    private var donnees: RepondeurLocal.Donnees {
        .init(accueil: Fixtures.accueil, argent: Fixtures.argent, chantiers: Fixtures.chantiers.chantiers)
    }

    func testQuestionsSimples() {
        guard case .dire(let jour, let carte) = RepondeurLocal.repondre("Qu’est-ce qui m’attend aujourd’hui ?", avec: donnees) else { return XCTFail() }
        XCTAssertTrue(jour.contains("5 décisions"))
        XCTAssertTrue(jour.contains("dont 2 envois"))
        XCTAssertEqual(carte, .afficherDecision("V-7K3F9Q"))

        guard case .dire(let dette, _) = RepondeurLocal.repondre("Combien la gérance Morel nous doit ?", avec: donnees) else { return XCTFail() }
        XCTAssertTrue(dette.hasPrefix("Gérance Morel SA vous doit 15 640 francs"), dette)
        XCTAssertTrue(dette.contains("aucune relance"))

        guard case .dire(let mont, let carteMont) = RepondeurLocal.repondre("Où en est le chantier du Mont ?", avec: donnees) else { return XCTFail() }
        XCTAssertTrue(mont.contains("boiler"), mont)
        XCTAssertTrue(mont.contains("05.10"))
        XCTAssertEqual(carteMont, .afficherChantier("24"))
    }

    func testActionsTransmises() {
        XCTAssertEqual(RepondeurLocal.repondre("Prépare une facture pour la régie Dubois, huit heures à cent quarante", avec: donnees),
                       .transmettre("Prépare une facture pour la régie Dubois, huit heures à cent quarante"))
        XCTAssertEqual(RepondeurLocal.repondre("Mets le chantier de Moudon au 12 octobre", avec: donnees),
                       .transmettre("Mets le chantier de Moudon au 12 octobre"))
        if case .transmettre = RepondeurLocal.repondre("Raconte-moi une blague", avec: donnees) {} else { XCTFail() }
    }

    func testMontantParle() {
        XCTAssertEqual(FormatSuisse.parle(642.35), "642 francs 35")
        XCTAssertEqual(FormatSuisse.parle(15_640), "15 640 francs")
    }
}
