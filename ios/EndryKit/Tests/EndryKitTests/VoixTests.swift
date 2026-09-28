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
        XCTAssertTrue(proposition.sortie.contains("glissant"), "validée seulement en glissant à l’écran")
        let saisie = await executeur.executer(nom: "saisie", arguments: #"{"texte":"Prépare une facture pour la régie Dubois"}"#)
        XCTAssertTrue(saisie.sortie.contains("Transmettre"), "préparée, jamais transmise d'ici")
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

        guard case .dire(let paquerets, let cartePaquerets) = RepondeurLocal.repondre("Où en est le chantier des Pâquerets ?", avec: donnees) else { return XCTFail() }
        XCTAssertTrue(paquerets.contains("chauffe-eau"), paquerets)
        XCTAssertTrue(paquerets.contains("05.10"))
        XCTAssertEqual(cartePaquerets, .afficherChantier("24"))
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
        XCTAssertTrue(t.contains("touche Transmettre"))
        XCTAssertTrue(t.contains("s’en occupe tout de suite"))
        XCTAssertFalse(t.contains("lecture seule"))
    }

    func testConsignesConversationDirecte() {
        let t = ConsignesCerveau.texte(envoiDirect: true, recap: "Q : Qui me doit ?\nR : Gérance Morel.")
        XCTAssertTrue(t.contains("Je pose la question au bureau"))
        XCTAssertFalse(t.contains("touche Envoyer"))
        XCTAssertTrue(t.contains("Commence toujours par une phrase courte"))
        XCTAssertTrue(t.contains("Gérance Morel"))
        XCTAssertTrue(t.contains("aucune relance sans sa demande"))
    }

    func testTexteParleSansBalises() {
        XCTAssertEqual(TexteParle.nettoyer("**Muller SA** vous doit 1'390 francs."), "Muller SA vous doit 1'390 francs.")
        XCTAssertEqual(TexteParle.nettoyer("Deux chantiers :\n- Rossi\n- Lambert 😀"), "Deux chantiers : Rossi. Lambert.")
        XCTAssertEqual(TexteParle.nettoyer("  Tout roule.  "), "Tout roule.")
        // Réponse qui s'écrit encore : la ligne en cours ne reçoit pas de point.
        XCTAssertEqual(TexteParle.nettoyer("Deux chantiers :\n- Rossi\n- Fav", fini: false), "Deux chantiers : Rossi. Fav")
    }

    func testMessageTexteRealtime() throws {
        let data = CommandeRealtime.messageTexte("Qui me doit ?")
        let objet = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(objet["type"] as? String, "conversation.item.create")
        let item = try XCTUnwrap(objet["item"] as? [String: Any])
        XCTAssertEqual(item["role"] as? String, "user")
    }
}

/// Serveur v1.1 : les routes v1.2 répondent 404 (repli sur la saisie).
actor APISansV12: EndryAPI {
    let demo: APIDemo
    init(_ demo: APIDemo) { self.demo = demo }
    nonisolated func urlAbsolue(_ chemin: String) -> URL? { nil }
    func envoyer(_ requete: Requete) async throws(ErreurAPI) -> Data {
        if ["/agents", "/journal", "/questions", "/assistant/question"].contains(where: { requete.chemin.contains($0) }) {
            throw .serveur(statut: 404, message: "Route inconnue")
        }
        return try await demo.envoyer(requete)
    }
}

final class BureauClaudeTests: XCTestCase {
    func testQuestionAUnAgentV12() async throws {
        let bureau = BureauClaude(api: APIDemo(latence: .zero, delaiClaude: .milliseconds(150)))
        let (id, nom) = await bureau.resoudreAgent(question: "Demande au secrétariat si Mme Gander a rappelé", demande: nil)
        XCTAssertEqual(id, "secretariat")
        XCTAssertEqual(nom, "Secrétariat")
        let posee = try await bureau.poser("Mme Gander a-t-elle rappelé ?", agentId: id, nomAgent: nom)
        guard case .enAttente(let suivi, let message) = posee, case .question(_, let agent) = suivi else { return XCTFail("\(posee)") }
        XCTAssertNil(message)
        XCTAssertEqual(agent, "secretariat")
        // Pendant la recherche, l'agent est au travail.
        let pendant = await bureau.etat()
        XCTAssertEqual(pendant?.agents.first { $0.id == "secretariat" }?.etat, .occupe)
        let reponse = await bureau.attendre(suivi, delai: .seconds(5), intervalle: .milliseconds(50))
        XCTAssertEqual(reponse?.statut, .repondu)
        XCTAssertTrue(reponse?.reponse?.contains("Gander") ?? false)
        let apres = await bureau.etat()
        XCTAssertEqual(apres?.journal.first?.titre, "Réponse au patron")
    }

    func testRepliSaisieV11() async throws {
        let bureau = BureauClaude(api: APISansV12(APIDemo(latence: .zero, delaiClaude: .milliseconds(150))))
        let (id, nom) = await bureau.resoudreAgent(question: "Des e-mails urgents ?", demande: nil)
        XCTAssertNil(id, "Pas de GET /agents : pas d'identifiant")
        XCTAssertEqual(nom, "Secrétariat")
        let posee = try await bureau.poser("Des e-mails urgents ?", agentId: id, nomAgent: nom)
        guard case .enAttente(let suivi, _) = posee, case .saisie(let saisieId, let texte) = suivi else { return XCTFail("\(posee)") }
        XCTAssertNotNil(saisieId)
        XCTAssertEqual(BureauClaude.agent(texte), .secretariat)
        XCTAssertEqual(BureauClaude.questionSeule(texte), "Des e-mails urgents ?")
        // Plus de sondage de /saisies : une vérification, puis une autre à l'événement `maj saisies`.
        let tropTot = await bureau.attendre(suivi)
        XCTAssertNil(tropTot)
        try await Task.sleep(for: .milliseconds(200))
        let reponse = await bureau.verifier(suivi)
        XCTAssertEqual(reponse?.statut, .repondu)
        XCTAssertEqual(reponse?.agent, "Secrétariat")
        XCTAssertTrue(reponse?.reponse?.hasPrefix("Secrétariat : ") ?? false)
    }

    func testEtatDuBureauV12() async {
        let etat = await BureauClaude(api: APIDemo(latence: .zero)).etat()
        XCTAssertEqual(etat?.agents.count, 5)
        XCTAssertEqual(etat?.libelleCourt, "Assistant au travail · Secrétariat, Comptabilité")
        let phrase = etat?.phrase ?? ""
        XCTAssertTrue(phrase.contains("L’assistant travaille côté Secrétariat : répond à Mme Rey"), phrase)
        XCTAssertTrue(phrase.contains("En pause : Achats"), phrase)
        XCTAssertTrue(phrase.contains("Dernières actions : côté Secrétariat, réponse préparée pour Mme Rey"), phrase)
        let secretariat = etat?.agent(cite: "Que fait le secrétariat ?")
        XCTAssertEqual(secretariat?.id, "secretariat")
        let detail = secretariat.flatMap { etat?.phrase(agent: $0) } ?? ""
        XCTAssertTrue(detail.contains("L’assistant, côté Secrétariat, est au travail"), detail)
        XCTAssertTrue(detail.contains("14 e-mails triés"), detail)
    }

    func testEtatDuBureauV11() async {
        let etat = await BureauClaude(api: APISansV12(APIDemo(latence: .zero))).etat()
        XCTAssertEqual(etat?.agents.isEmpty, true)
        XCTAssertEqual(etat?.libelleCourt, "Assistant au travail · 2 en cours")
        let phrase = etat?.phrase ?? ""
        XCTAssertTrue(phrase.contains("L’assistant travaille sur le PC"), phrase)
        XCTAssertTrue(phrase.contains("Facture RE-00416 préparée, à valider"), phrase)
    }

    func testOutilsExecutes() async {
        let executeur = ExecuteurOutils(api: APIDemo(latence: .zero))
        let bureau = await executeur.executer(nom: "bureau", arguments: #"{"agent":"compta"}"#)
        XCTAssertTrue(bureau.sortie.contains("côté Comptabilité, est au travail"), bureau.sortie)
        // La voix prépare, le patron confirme : rien ne part d'ici.
        let question = await executeur.executer(nom: "demander_claude", arguments: #"{"question":"Des e-mails urgents ?"}"#)
        guard case .questionAConfirmer(let q, let agent, let agentId) = question.effet else { return XCTFail("\(question.effet)") }
        XCTAssertEqual(q, "Des e-mails urgents ?")
        XCTAssertEqual(agent, "Secrétariat", "Les e-mails vont au secrétariat")
        XCTAssertEqual(agentId, "secretariat")
        let saisie = await executeur.executer(nom: "saisie", arguments: #"{"texte":"Prépare une offre pour Mme Rey"}"#)
        XCTAssertEqual(saisie.effet, .saisieAConfirmer(texte: "Prépare une offre pour Mme Rey"))
        XCTAssertTrue(saisie.sortie.contains("rien n’est parti"))
    }

    func testDecodageV12() throws {
        let agents = try JSONDecoder().decode(ListeAgentsPC.self, from: Fixtures.donnees(.agents)).agents
        XCTAssertEqual(agents.map(\.id), ["secretariat", "comptabilite", "chantiers", "offres", "achats"])
        XCTAssertEqual(agents[0].connu, .secretariat)
        XCTAssertEqual(agents[4].etat, .pause)
        let tolerant = try JSONDecoder().decode(ListeAgentsPC.self, from: Data(#"[{"nom":"RH","tache":"Prépare les fiches de salaire"}, {"x":1}]"#.utf8)).agents
        XCTAssertEqual(tolerant.count, 1)
        XCTAssertEqual(tolerant[0].etat, .occupe, "Une tâche sans état : au travail")
        let journal = try JSONDecoder().decode(JournalPC.self, from: Fixtures.donnees(.journal)).entrees
        XCTAssertEqual(journal.first?.type, .emailPrepare)
        XCTAssertEqual(journal.first?.decisionReference, "V-7K3F9Q")
        let reponse = try JSONDecoder().decode(ReponseAgent.self, from: Data(#"{"reponse":"Oui, hier à 16 h.","agent":"secretariat"}"#.utf8))
        XCTAssertEqual(reponse.statut, .repondu)
        let attente = try JSONDecoder().decode(ReponseAgent.self, from: Data(#"{"question_id":"Q-1"}"#.utf8))
        XCTAssertEqual(attente.statut, .enCours)
    }

    func testOutilsDansLaSessionTempsReel() throws {
        let session = try JSONDecoder().decode(SessionVoix.self, from: Data(#"{"disponible":true,"client_secret":"x","outils":[]}"#.utf8))
        let data = CommandeRealtime.configuration(session: session, vocabulaire: [])
        let texte = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(texte.contains("demander_assistant"))
        XCTAssertTrue(texte.contains("\"bureau\""))
    }
}

final class AgentsBureauTests: XCTestCase {
    func testDetection() {
        XCTAssertEqual(AgentBureau.detecter("Demande au secrétariat si Mme Gander a rappelé"), .secretariat)
        XCTAssertEqual(AgentBureau.detecter("Est-ce que la compta a payé le fournisseur ?"), .comptabilite)
        XCTAssertEqual(AgentBureau.detecter("Quels mails sont arrivés ce matin ?"), .secretariat)
        XCTAssertEqual(AgentBureau.detecter("La facture Dubois est-elle payée ?"), .comptabilite)
        XCTAssertEqual(AgentBureau.detecter("Le devis Rochat est parti ?"), .offres)
        XCTAssertNil(AgentBureau.detecter("Raconte-moi une blague"))
        XCTAssertEqual(AgentBureau(nom: "secretariat"), .secretariat)
        XCTAssertEqual(AgentBureau(nom: "Comptabilité"), .comptabilite)
    }

    func testQuestionAdresseeALAgent() {
        let texte = BureauClaude.texteQuestion("Des e-mails urgents ?", agent: .secretariat)
        XCTAssertTrue(texte.contains("[Pour l’agent Secrétariat]"))
        XCTAssertEqual(BureauClaude.questionSeule(texte), "Des e-mails urgents ?")
        XCTAssertEqual(BureauClaude.agent(texte), .secretariat)
        XCTAssertNil(BureauClaude.agent(BureauClaude.texteQuestion("Quoi de neuf ?")))
    }

    func testRepondeurAgents() {
        let donnees = RepondeurLocal.Donnees(accueil: nil, argent: nil, chantiers: [])
        XCTAssertEqual(RepondeurLocal.repondre("Demande au secrétariat si Mme Gander a rappelé", avec: donnees),
                       .demanderClaude("Demande au secrétariat si Mme Gander a rappelé"))
        XCTAssertEqual(RepondeurLocal.repondre("Que fait la compta ?", avec: donnees), .etatBureau)
    }
}

final class EvenementsV12Tests: XCTestCase {
    func testEvenementsAgents() {
        XCTAssertEqual(EvenementSSE(nom: "agent", donnees: #"{"id":"secretariat","etat":"occupe"}"#).sujet, .agents)
        XCTAssertEqual(EvenementSSE(nom: "journal", donnees: "{}").sujet, .agents)
        XCTAssertEqual(EvenementSSE(nom: "maj", donnees: #"{"quoi":"agents"}"#).sujet, .agents)
        XCTAssertNil(EvenementSSE(nom: "ping", donnees: "{}").sujet)
    }
}

final class HorsHorairesTests: XCTestCase {
    func testJamaisDisponibleHorsHoraires() throws {
        let agents = try JSONDecoder().decode(ListeAgentsPC.self, from: Data(#"""
        {"agents":[{"id":"secretariat","nom":"Secrétariat","etat":"hors_horaires","horaires":"du lundi au vendredi, de 7 h à 18 h"},
                   {"id":"offres","nom":"Offres","etat":"libre"}],
         "assistant":{"pause":false,"file":0,"en_cours":null,"en_service":false,"horaires":"du lundi au vendredi, de 7 h à 18 h"}}
        """#.utf8))
        XCTAssertEqual(agents.agents[0].etat, .horsHoraires)
        XCTAssertEqual(agents.assistant?.enService, false)
        let etat = EtatBureau(etat: agents.assistant, saisies: [], agents: agents.agents)
        XCTAssertEqual(etat.etatAffiche(agents.agents[1]), .horsHoraires, "« libre » hors horaires n'est jamais « Disponible »")
        XCTAssertTrue(etat.libelleCourt.hasPrefix("Hors horaires · repasse "), etat.libelleCourt)
        XCTAssertTrue(etat.phrase.contains("hors horaires (du lundi au vendredi, de 7 h à 18 h), il repasse"), etat.phrase)
        XCTAssertTrue(etat.phrase(agent: agents.agents[1]).contains("est hors horaires"))
    }

    func testReponseAvecMessageHorsHoraires() throws {
        let r = try JSONDecoder().decode(ReponseAgent.self, from: Data(#"""
        {"statut":"en_cours","question_id":"Q-12","agent":"comptabilite",
         "message":"L’assistant répondra à son prochain passage (du lundi au vendredi, de 7 h à 18 h)."}
        """#.utf8))
        XCTAssertEqual(r.statut, .enCours)
        XCTAssertEqual(r.questionId, "Q-12")
        XCTAssertTrue(r.message?.contains("prochain passage") ?? false)
    }

    func testSaisiesV12() throws {
        let data = Data(#"""
        [{"id":"S-201","cree":"2026-09-27T18:10:00","texte":"Question du patron : des e-mails ?","photos":0,"statut":"en_cours",
          "resume":null,"decision_reference":null,"question":true,"agent":"secretariat","tache_id":"T-88"}]
        """#.utf8)
        let s = try XCTUnwrap(try JSONDecoder().decode(ListeSaisies.self, from: data).saisies.first)
        XCTAssertTrue(s.question)
        XCTAssertEqual(s.agent, "secretariat")
        XCTAssertEqual(s.tacheId, "T-88")
    }
}

final class ContratPC270926Tests: XCTestCase {
    func testQuestionsFixtures() throws {
        let enCours = try JSONDecoder().decode(ReponseAgent.self, from: Fixtures.donnees(.questionEnCours))
        XCTAssertEqual(enCours.statut, .enCours)
        XCTAssertNil(enCours.message)
        let horsHoraires = try JSONDecoder().decode(ReponseAgent.self, from: Fixtures.donnees(.questionHorsHoraires))
        XCTAssertEqual(horsHoraires.statut, .enCours)
        XCTAssertTrue(horsHoraires.message?.contains("prochain passage") ?? false)
        let repondu = try JSONDecoder().decode(ReponseAgent.self, from: Fixtures.donnees(.questionRepondu))
        XCTAssertEqual(repondu.statut, .repondu)
        XCTAssertNil(repondu.decisionReference)
    }

    func testFixturesAuContratReel() throws {
        let argent = try JSONDecoder().decode(Argent.self, from: Fixtures.donnees(.argent))
        XCTAssertTrue(argent.aRefacturer.achats.allSatisfy { $0.id.hasPrefix("achat:") })
        XCTAssertEqual(argent.heuresSecretariat?.heures, 31.5)
        let saisies = try JSONDecoder().decode(ListeSaisies.self, from: Fixtures.donnees(.saisies)).saisies
        let question = try XCTUnwrap(saisies.first { $0.question })
        XCTAssertEqual(question.agent, "secretariat")
        XCTAssertEqual(BureauClaude.libelle(question.texte), "Question à Claude · Secrétariat : Mme Gander a-t-elle rappelé ?")
        let accueil = try JSONDecoder().decode(Accueil.self, from: Fixtures.donnees(.accueil))
        XCTAssertEqual(accueil.salut, "Bonjour")
        XCTAssertEqual(accueil.chantiers7Jours.first?.etape, "planifie")
        XCTAssertTrue(accueil.decisions.filter { $0.estQuestion }.allSatisfy { !$0.partChezUnTiers })
    }

    func testRenvoiIdentiqueMemeIdentifiant() async throws {
        let demo = APIDemo(latence: .zero)
        let formulaire = FormulaireMultipart(champs: [Parametre("texte", "Citerne dégazée à la Villa Morel.")])
        let premier = try await demo.charger(ReponseSimple.self, .saisie(formulaire))
        let second = try await demo.charger(ReponseSimple.self, .saisie(formulaire))
        XCTAssertEqual(premier.saisieId, second.saisieId)
        XCTAssertEqual(second.message, "Déjà transmis.")
    }
}

final class VocabulaireMetierTests: XCTestCase {
    func testTermesDuMetierPuisNomsSansDoublons() {
        let termes = VocabulaireMetier.pour(noms: ["Famille Rochat", "GEBERIT", "Fondation Les Tilleuls, Moudon", "  ", "12", "Rochat"])
        XCTAssertEqual(Array(termes.prefix(VocabulaireMetier.termes.count)), VocabulaireMetier.termes)
        XCTAssertTrue(termes.contains("Famille Rochat"))
        XCTAssertTrue(termes.contains("Fondation Les Tilleuls"), "coupé à la virgule")
        XCTAssertTrue(termes.contains("Rochat"))
        XCTAssertFalse(termes.contains("GEBERIT"), "doublon de Geberit, sans égard à la casse")
        XCTAssertFalse(termes.contains("12"))
        XCTAssertFalse(termes.contains(""))
    }

    func testLimiteAppleEtExpressionsCourtes() {
        let noms = (1...300).map { "Client \($0)" } + ["Une raison sociale beaucoup trop longue pour la dictée"]
        let termes = VocabulaireMetier.pour(noms: noms)
        XCTAssertEqual(termes.count, VocabulaireMetier.limite)
        XCTAssertTrue(termes.allSatisfy { $0.split(separator: " ").count <= 4 && $0.count <= 40 })
    }

    func testNomsDesDonneesSansMontants() {
        let noms = VocabulaireMetier.noms(semaine: [], chantiers: Fixtures.chantiers.chantiers, argent: Fixtures.argent)
        XCTAssertFalse(noms.isEmpty)
        XCTAssertTrue(noms.allSatisfy { !$0.contains("CHF") })
        let vocabulaire = VocabulaireVocal()
        vocabulaire.mettreAJour(noms: noms)
        XCTAssertLessThanOrEqual(vocabulaire.termes.count, VocabulaireMetier.limite)
        XCTAssertTrue(vocabulaire.termes.contains(Fixtures.chantiers.chantiers[0].client))
    }
}
