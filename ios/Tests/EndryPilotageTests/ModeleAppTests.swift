import EndryKit
import XCTest
@testable import EndryPilotage

@MainActor
final class ModeleAppTests: XCTestCase {
    private func sessionVide() -> ModeleSession {
        ModeleSession(coffre: CoffreMemoire(), cache: CacheHorsLigne(dossier: nil))
    }

    func testDemarrageDeconnecte() {
        let app = ModeleApp(session: sessionVide())
        XCTAssertFalse(app.session.estConnecte)
        XCTAssertNil(app.decisions)
        XCTAssertNil(app.saisie)
    }

    func testModeDemoConstruitLesEcrans() async throws {
        let app = ModeleApp(session: sessionVide())
        app.activerDemo()
        XCTAssertTrue(app.session.estDemo)
        XCTAssertFalse(app.verrou.doitAfficherEcran, "la démo ne doit pas rester bloquée derrière Face ID")
        let decisions = try XCTUnwrap(app.decisions)
        await decisions.charger()
        XCTAssertEqual(decisions.nombreDecisions, 5)
        XCTAssertNotNil(app.chantiers)
        XCTAssertNotNil(app.argent)
    }

    func testDicterPourUnChantier() throws {
        let app = ModeleApp(session: sessionVide())
        app.activerDemo()
        app.dicter(pour: Fixtures.dossierDetaille)
        XCTAssertEqual(app.onglet, .saisie)
        XCTAssertEqual(app.saisie?.texte, "Chantier Famille Rochat — Épalinges (VD) : ")
    }

    func testNotificationOuvreLaCarte() {
        let app = ModeleApp(session: sessionVide())
        app.activerDemo()
        app.onglet = .argent
        app.ouvrir(reference: "V-7K3F9Q")
        XCTAssertEqual(app.onglet, .decisions)
        XCTAssertEqual(app.referenceCiblee, "V-7K3F9Q")
    }

    func testDeconnexion() async {
        let app = ModeleApp(session: sessionVide())
        app.activerDemo()
        await app.deconnecter()
        XCTAssertFalse(app.session.estConnecte)
        XCTAssertNil(app.decisions)
    }

    func testAucuneRelanceNiPaiement() {
        // Règle métier : l'app n'expose aucune route de relance ni de paiement.
        let routes = [Requete.accueil, .decisions, .argent, .actualiser, .chantiers(), .chantier(id: "1")].map(\.chemin)
        XCTAssertFalse(routes.contains { $0.contains("relance") || $0.contains("paiement") })
    }

    func testPolicesEmbarquees() {
        for nom in ["InterTight-SemiBold", "InterTight-Medium", "Inter-Regular", "Inter-Medium", "Inter-SemiBold"] {
            XCTAssertNotNil(UIFont(name: nom, size: 12), "police manquante : \(nom)")
        }
    }
}
