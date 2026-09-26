import XCTest
@testable import EndryKit

final class DecodageTests: XCTestCase {
    func testToutesLesFixturesSeDecodent() throws {
        let accueil = try Fixtures.decoder(Accueil.self, .accueil)
        XCTAssertEqual(accueil.salut, "Bonjour Monsieur Endry")
        XCTAssertEqual(accueil.decisions.count, 5)
        XCTAssertEqual(accueil.encaisser.factures.count, 6)
        XCTAssertEqual(accueil.encaisser.total, 46_109.70, accuracy: 0.001)
        XCTAssertEqual(accueil.encaisser.anciennete.total, accueil.encaisser.total, accuracy: 0.01)
        XCTAssertEqual(accueil.chantiers7Jours.count, 3)
        XCTAssertFalse(accueil.pause)

        let decisions = try Fixtures.decoder(ReponseDecisions.self, .decisions)
        XCTAssertTrue(decisions.decisionsAutorisees)
        XCTAssertEqual(decisions.decisions.map(\.reference), accueil.decisions.map(\.reference))

        let chantiers = try Fixtures.decoder(ReponseChantiers.self, .chantiers)
        XCTAssertEqual(chantiers.chantiers.count, 10)
        XCTAssertEqual(chantiers.etapes.first?.cle, "tous")
        XCTAssertEqual(chantiers.etapes.dropFirst().reduce(0) { $0 + $1.nombre }, 10)
        XCTAssertEqual(chantiers.calendrierICS, "/app/planning.ics?jeton=demo")

        let details = try Fixtures.decoder([String: Dossier].self, .chantiersDetails)
        let rochat = try XCTUnwrap(details["D-1042"])
        XCTAssertEqual(rochat.etapeIndex, 3)
        XCTAssertEqual(rochat.documents.count, 2)
        XCTAssertEqual(rochat.achats.count, 2)
        XCTAssertEqual(rochat.facturesFournisseurs.count, 1)
        XCTAssertTrue(rochat.decisionEnAttente)

        let argent = try Fixtures.decoder(Argent.self, .argent)
        XCTAssertEqual(argent.aRefacturer.achats.count, 3)
        XCTAssertEqual(argent.versementsNonIdentifies.count, 2)
        XCTAssertEqual(argent.heuresSecretariat?.heures, 31.5)
        XCTAssertEqual(argent.payer.cetteSemaine.count, 2)

        let session = try Fixtures.decoder(SessionOuverte.self, .session)
        XCTAssertEqual(session.valableJours, 180)

        let erreur = try Fixtures.decoder(CorpsErreur.self, .erreur401)
        XCTAssertEqual(erreur.erreur, "non_authentifie")
    }

    func testCarteEnvoiEtQuestion() throws {
        let cartes = Fixtures.cartes
        let mail = try XCTUnwrap(cartes.first { $0.reference == "V-7K3F9Q" })
        XCTAssertTrue(mail.exigeGlisser)
        XCTAssertFalse(mail.estQuestion)
        XCTAssertEqual(mail.controle?.ok, true)
        XCTAssertEqual(mail.pieces.first?.estPDF, true)

        let facture = try XCTUnwrap(cartes.first { $0.reference == "V-2M8R4T" })
        XCTAssertTrue(facture.exigeGlisser)
        XCTAssertEqual(facture.controle?.ok, false)
        XCTAssertEqual(facture.controle?.pointsAVerifier.count, 1)

        let offreBexio = try XCTUnwrap(cartes.first { $0.reference == "V-9P1X6D" })
        XCTAssertFalse(offreBexio.exigeGlisser, "créer une offre dans Bexio n'envoie rien au client")

        let question = try XCTUnwrap(cartes.first { $0.reference == "Q-4HD2XP" })
        XCTAssertTrue(question.estQuestion)
        XCTAssertEqual(question.type, .question)
        XCTAssertNotNil(question.dateCreation)
    }

    func testDecodageTolerant() throws {
        let json = """
        {"decisions": [
            {"reference": "Q-AAA", "titre": 42, "destinataires": "a@b.ch", "modifiable": "oui"},
            {"titre": "sans référence : ignorée"},
            "n'importe quoi",
            {"reference": "V-BBB", "controle": {"points_a_verifier": ["IBAN différent"]}, "pieces": [{"url": "/app/doc/facture/9"}]}
        ], "decisions_autorisees": 0}
        """
        let r = try JSONDecoder().decode(ReponseDecisions.self, from: Data(json.utf8))
        XCTAssertEqual(r.decisions.count, 2)
        XCTAssertFalse(r.decisionsAutorisees)
        XCTAssertEqual(r.decisions[0].type, .question)
        XCTAssertEqual(r.decisions[0].titre, "42")
        XCTAssertEqual(r.decisions[0].destinataires, ["a@b.ch"])
        XCTAssertTrue(r.decisions[0].modifiable)
        XCTAssertEqual(r.decisions[1].controle?.ok, false)
        XCTAssertEqual(r.decisions[1].controle?.pointsAVerifier.first?.controle, "IBAN différent")
        XCTAssertEqual(r.decisions[1].pieces.first?.nom, "9")
    }

    func testMontantsEnTexteEtDossierMinimal() throws {
        let json = """
        {"id": 7, "montant": "13'695.45", "etape_index": 9, "decision_en_attente": "V-XYZ"}
        """
        let d = try JSONDecoder().decode(Dossier.self, from: Data(json.utf8))
        XCTAssertEqual(d.id, "7")
        XCTAssertEqual(d.montant ?? 0, 13_695.45, accuracy: 0.001)
        XCTAssertEqual(d.etapeIndex, 6)
        XCTAssertTrue(d.decisionEnAttente)
        XCTAssertEqual(d.referenceDecision, "V-XYZ")
        XCTAssertEqual(Double.depuisTexteSuisse("CHF 1’200.–"), 1200)
        XCTAssertEqual(Double.depuisTexteSuisse("486,35"), 486.35)
    }

    func testAccueilVide() throws {
        let a = try JSONDecoder().decode(Accueil.self, from: Data("{}".utf8))
        XCTAssertEqual(a.decisions, [])
        XCTAssertEqual(a.encaisser.total, 0)
        XCTAssertEqual(a.salut, "Bonjour")
    }

    func testRegroupementParClient() {
        let groupes = Fixtures.accueil.encaisser.parClient
        XCTAssertEqual(groupes.first?.client, "PPE Les Vergers")
        let chappuis = groupes.first { $0.client == "M. et Mme Chappuis" }
        XCTAssertEqual(chappuis?.factures.count, 2)
        XCTAssertEqual(chappuis?.retardMax, 12)
        XCTAssertEqual(chappuis?.montant ?? 0, 9_685.80, accuracy: 0.001)
    }
}
