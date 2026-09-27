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
        if case .demanderClaude = RepondeurLocal.repondre("Raconte-moi une blague", avec: donnees) {} else { XCTFail() }
        XCTAssertEqual(RepondeurLocal.repondre("Que fait Claude en ce moment ?", avec: donnees), .etatBureau)
        XCTAssertEqual(RepondeurLocal.repondre("Demande à Claude si Mme Gander a rappelé", avec: donnees),
                       .demanderClaude("Demande à Claude si Mme Gander a rappelé"))
        XCTAssertEqual(RepondeurLocal.repondre("Est-ce que le fournisseur a confirmé la livraison ?", avec: donnees),
                       .demanderClaude("Est-ce que le fournisseur a confirmé la livraison ?"))
    }

    func testMontantParle() {
        XCTAssertEqual(FormatSuisse.parle(642.35), "642 francs 35")
        XCTAssertEqual(FormatSuisse.parle(15_640), "15 640 francs")
    }
}

final class CerveauTests: XCTestCase {
    func testConsignesPortentLesRegles() {
        let date = DateEndry.lire("2026-09-27")!
        let t = ConsignesCerveau.texte(date: date)
        XCTAssertTrue(t.contains("27.09.2026"))
        XCTAssertTrue(t.contains("aucune relance sans sa demande"))
        XCTAssertTrue(t.contains("proposer_decision"))
        XCTAssertTrue(t.contains("rien ne part"))
    }

    func testTexteParleSansBalises() {
        XCTAssertEqual(TexteParle.nettoyer("**Muller SA** vous doit 1'390 francs."), "Muller SA vous doit 1'390 francs.")
        XCTAssertEqual(TexteParle.nettoyer("Deux chantiers :\n- Rossi\n- Favre 😀"), "Deux chantiers : Rossi. Favre.")
        XCTAssertEqual(TexteParle.nettoyer("  Tout roule.  "), "Tout roule.")
    }

    func testMessageTexteRealtime() throws {
        let data = CommandeRealtime.messageTexte("Qui me doit ?")
        let objet = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(objet["type"] as? String, "conversation.item.create")
        let item = try XCTUnwrap(objet["item"] as? [String: Any])
        XCTAssertEqual(item["role"] as? String, "user")
    }
}

final class BureauClaudeTests: XCTestCase {
    func testQuestionPoseeEtReponseLue() async throws {
        let api = APIDemo(latence: .zero, delaiClaude: .milliseconds(200))
        let bureau = BureauClaude(api: api)
        let posee = try await bureau.poser("Où en est Mme Gander pour l’adoucisseur ?")
        guard case .enAttente(let id, let texte) = posee else { return XCTFail("Réponse directe inattendue en démo") }
        XCTAssertNotNil(id)
        XCTAssertTrue(BureauClaude.estQuestion(texte))
        XCTAssertEqual(BureauClaude.questionSeule(texte), "Où en est Mme Gander pour l’adoucisseur ?")
        let saisie = await bureau.attendre(saisieId: id, texte: texte, delai: .seconds(5), intervalle: .milliseconds(50))
        XCTAssertEqual(saisie?.statut, .traite)
        XCTAssertTrue(saisie?.resume?.contains("Gander") ?? false)
    }

    func testEtatDuBureau() async {
        let bureau = BureauClaude(api: APIDemo(latence: .zero))
        let etat = await bureau.etat()
        XCTAssertEqual(etat?.enPause, false)
        XCTAssertEqual(etat?.libelleCourt, "Claude travaille · 2 en cours")
        let phrase = etat?.phrase ?? ""
        XCTAssertTrue(phrase.contains("Claude travaille sur le PC"), phrase)
        XCTAssertTrue(phrase.contains("Mme Gander"), phrase)
        XCTAssertTrue(phrase.contains("Facture RE-00416 préparée, à valider"), phrase)
    }

    func testOutilsExecutes() async {
        let executeur = ExecuteurOutils(api: APIDemo(latence: .zero))
        let bureau = await executeur.executer(nom: "bureau", arguments: "{}")
        XCTAssertTrue(bureau.sortie.contains("resume"))
        let question = await executeur.executer(nom: "demander_claude", arguments: #"{"question":"Des e-mails urgents ?"}"#)
        guard case .questionClaude(_, _, let q) = question.effet else { return XCTFail("\(question.effet)") }
        XCTAssertEqual(q, "Des e-mails urgents ?")
    }

    func testOutilsDansLaSessionTempsReel() throws {
        let session = try JSONDecoder().decode(SessionVoix.self, from: Data(#"{"disponible":true,"client_secret":"x","outils":[]}"#.utf8))
        let data = CommandeRealtime.configuration(session: session, vocabulaire: [])
        let texte = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(texte.contains("demander_claude"))
        XCTAssertTrue(texte.contains("\"bureau\""))
    }
}
