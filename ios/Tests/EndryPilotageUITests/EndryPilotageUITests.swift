import XCTest

/// Flux principaux en mode démo : connexion démo, Oui / Non / Corriger, glisser pour envoyer, saisie.
/// Les captures d'écran (clair / sombre) sont jointes au rapport de test et exportées par Codemagic.
final class EndryPilotageUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func lancer(_ arguments: [String] = ["-demo"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitests", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func titreDecisions(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["titre-a-decider"].firstMatch
    }

    /// Fait défiler jusqu'à ce que l'élément existe et soit touchable (listes paresseuses).
    @MainActor
    @discardableResult
    private func atteindre(_ element: XCUIElement, dans app: XCUIApplication, essais: Int = 8) -> XCUIElement {
        var n = 0
        while !(element.exists && element.isHittable) && n < essais {
            app.swipeUp(velocity: .slow)
            n += 1
        }
        return element
    }

    /// Touche un élément dès qu'il est touchable (fin des animations d'apparition) ; sinon, touche sa position.
    @MainActor
    private func toucher(_ element: XCUIElement, delai: TimeInterval = 5) {
        let limite = Date().addingTimeInterval(delai)
        while !element.isHittable && Date() < limite {
            usleep(200_000)
        }
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        }
    }

    /// Pile de décisions : passe les cartes (« Plus tard ») jusqu'à ce que l'élément voulu soit devant.
    @MainActor
    @discardableResult
    private func amener(_ element: XCUIElement, dans app: XCUIApplication, essais: Int = 7) -> XCUIElement {
        let suivante = app.buttons["decision-suivante"]
        for _ in 0..<essais {
            if element.exists {
                return atteindre(element, dans: app)
            }
            guard suivante.waitForExistence(timeout: 2) else { break }
            atteindre(suivante, dans: app).tap()
        }
        return atteindre(element, dans: app)
    }

    @MainActor
    func testConnexionDemoDepuisAccueil() {
        let app = lancer([])
        let demo = app.buttons["bouton-demo"]
        guard demo.waitForExistence(timeout: 5) else {
            // Un jeton réel est déjà présent sur ce simulateur : rien à tester ici.
            return
        }
        XCTAssertTrue(app.buttons["coller-lien"].exists || app.textFields["champ-lien"].exists)
        demo.tap()
        XCTAssertTrue(titreDecisions(app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testOuiNonCorriger() {
        let app = lancer()
        XCTAssertTrue(titreDecisions(app).waitForExistence(timeout: 5))

        // Oui simple (créer une offre dans Bexio : pas d'envoi au client).
        let oui = amener(app.buttons["oui-V-9P1X6D"], dans: app)
        XCTAssertTrue(oui.waitForExistence(timeout: 3))
        oui.tap()
        XCTAssertTrue(oui.waitForNonExistence(timeout: 5))

        // Non : confirmation obligatoire.
        let non = amener(app.buttons["non-V-5T7B2N"], dans: app)
        XCTAssertTrue(non.waitForExistence(timeout: 3))
        non.tap()
        let ecarter = app.buttons["Écarter"]
        XCTAssertTrue(ecarter.waitForExistence(timeout: 3))
        ecarter.tap()
        XCTAssertTrue(non.waitForNonExistence(timeout: 5))

        // Corriger : consignes écrites.
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        let corriger = amener(app.buttons["corriger-V-2M8R4T"], dans: app)
        XCTAssertTrue(corriger.waitForExistence(timeout: 3))
        corriger.tap()
        let champ = app.textViews["champ-consignes"]
        XCTAssertTrue(champ.waitForExistence(timeout: 3))
        champ.tap()
        champ.typeText("Compter 6 h 30 au lieu de 7 h.")
        app.buttons["envoyer-consignes"].tap()
        XCTAssertTrue(corriger.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testGlisserPourEnvoyer() {
        let app = lancer()
        XCTAssertTrue(titreDecisions(app).waitForExistence(timeout: 5))
        let carte = app.descendants(matching: .any)["carte-V-7K3F9Q"]
        let curseur = amener(app.descendants(matching: .any)["glisser-pour-envoyer"].firstMatch, dans: app)
        XCTAssertTrue(curseur.waitForExistence(timeout: 3))
        let depart = curseur.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        let arrivee = curseur.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5))
        depart.press(forDuration: 0.1, thenDragTo: arrivee)
        XCTAssertTrue(carte.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testSaisieTerrain() {
        let app = lancer()
        let onglet = app.buttons["onglet-saisie"]
        XCTAssertTrue(onglet.waitForExistence(timeout: 5))
        onglet.tap()
        let texte = app.textViews["texte-saisie"]
        XCTAssertTrue(texte.waitForExistence(timeout: 3))
        toucher(texte)
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            texte.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Le champ de saisie ne prend pas le focus.")
        texte.typeText("Chantier Rochat : citerne dégazée.")
        app.buttons["transmettre"].tap()
        XCTAssertTrue(app.staticTexts["Transmis"].waitForExistence(timeout: 5))
    }

    /// Captures relues à chaque lot : clair / sombre. La CI relance ce test sur iPhone SE en taille XXL
    /// et sur un Pro Max (variables `CAPTURE_APPAREIL` et `CAPTURE_TAILLE`, passées via `TEST_RUNNER_…`).
    @MainActor
    func testCapturesClairEtSombre() {
        let env = ProcessInfo.processInfo.environment
        let appareil = env["CAPTURE_APPAREIL"].map { "-\($0)" } ?? ""
        var reglages: [String] = []
        if let taille = env["CAPTURE_TAILLE"], !taille.isEmpty {
            reglages = ["-UIPreferredContentSizeCategoryName", taille]
        }
        for schema in ["-clair", "-sombre"] {
            let suffixe = schema + appareil
            let app = lancer(["-demo", schema] + reglages)
            XCTAssertTrue(titreDecisions(app).waitForExistence(timeout: 5))
            sleep(1)
            capturer(app, "1-aujourdhui\(suffixe)")
            app.swipeUp(velocity: .slow)
            sleep(1)
            capturer(app, "1b-aujourdhui-suite\(suffixe)")
            for (onglet, nom) in [("onglet-chantiers", "2-chantiers"), ("onglet-saisie", "3-saisie"), ("onglet-finances", "4-finances"), ("onglet-entreprise", "5-entreprise")] {
                app.buttons[onglet].tap()
                sleep(1)
                capturer(app, "\(nom)\(suffixe)")
                let planning = app.buttons["segment-planning"]
                if onglet == "onglet-chantiers", planning.waitForExistence(timeout: 2) {
                    planning.tap()
                    sleep(1)
                    capturer(app, "2b-planning\(suffixe)")
                    app.buttons["segment-pipeline"].tap()
                }
            }
            app.terminate()
        }
    }

    @MainActor
    private func capturer(_ app: XCUIApplication, _ nom: String) {
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }
}
