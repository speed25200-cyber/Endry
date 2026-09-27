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

    /// Carrousel des décisions : revient au début, puis fait défiler jusqu'à ce que l'élément soit touchable.
    @MainActor
    @discardableResult
    private func amener(_ element: XCUIElement, dans app: XCUIApplication, essais: Int = 7) -> XCUIElement {
        let carrousel = app.scrollViews["carrousel-decisions"].firstMatch
        if !carrousel.waitForExistence(timeout: 3) { return atteindre(element, dans: app) }
        atteindre(carrousel, dans: app)
        if element.exists, element.isHittable { return element }
        for _ in 0..<essais { carrousel.swipeRight() }
        for _ in 0..<essais {
            if element.exists, element.isHittable { return element }
            carrousel.swipeLeft()
            usleep(300_000)
        }
        return element
    }

    /// Ouvre la fiche complète d'une décision (toucher la carte du carrousel).
    @MainActor
    private func ouvrirFiche(_ reference: String, dans app: XCUIApplication) {
        let apercu = amener(app.buttons["apercu-\(reference)"], dans: app)
        XCTAssertTrue(apercu.waitForExistence(timeout: 3))
        apercu.tap()
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

        // Oui directement sur la carte (offre Bexio : rien ne part chez un tiers).
        let oui = amener(app.buttons["oui-V-9P1X6D"], dans: app)
        XCTAssertTrue(oui.waitForExistence(timeout: 3))
        oui.tap()
        XCTAssertTrue(oui.waitForNonExistence(timeout: 5))

        // Non : depuis la fiche complète, confirmation obligatoire.
        ouvrirFiche("V-5T7B2N", dans: app)
        let non = app.buttons["non-V-5T7B2N"]
        XCTAssertTrue(non.waitForExistence(timeout: 3))
        atteindre(non, dans: app).tap()
        let ecarter = app.buttons["Écarter"]
        XCTAssertTrue(ecarter.waitForExistence(timeout: 3))
        ecarter.tap()
        XCTAssertTrue(app.buttons["apercu-V-5T7B2N"].waitForNonExistence(timeout: 5))

        // Corriger : consignes écrites, depuis la fiche.
        ouvrirFiche("V-2M8R4T", dans: app)
        let corriger = app.buttons["corriger-V-2M8R4T"]
        XCTAssertTrue(corriger.waitForExistence(timeout: 3))
        atteindre(corriger, dans: app).tap()
        let champ = app.textViews["champ-consignes"]
        XCTAssertTrue(champ.waitForExistence(timeout: 3))
        champ.tap()
        champ.typeText("Compter 6 h 30 au lieu de 7 h.")
        app.buttons["envoyer-consignes"].tap()
        XCTAssertTrue(app.buttons["apercu-V-2M8R4T"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testFicheComplete() {
        let app = lancer()
        XCTAssertTrue(titreDecisions(app).waitForExistence(timeout: 5))
        ouvrirFiche("V-7K3F9Q", dans: app)
        // La fiche montre tout : destinataires, texte complet, pièce jointe, gestes.
        XCTAssertTrue(app.descendants(matching: .any)["fiche-decision"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["fermer-fiche"].exists)
        capturer(app, "6-fiche-decision")
        app.buttons["fermer-fiche"].tap()
        XCTAssertTrue(app.buttons["fermer-fiche"].waitForNonExistence(timeout: 3))
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

    /// Assistant : ouvert depuis « Parler à Endry », une suggestion touchée reçoit une réponse dite et affichée.
    @MainActor
    func testAssistantRepond() {
        let app = lancer()
        let bouton = app.buttons["parler-endry"]
        XCTAssertTrue(bouton.waitForExistence(timeout: 8))
        toucher(bouton)
        let suggestion = app.buttons["suggestion-0"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 8))
        let limite = Date().addingTimeInterval(25)
        while !suggestion.isEnabled && Date() < limite { usleep(250_000) }
        if !suggestion.isEnabled { capturer(app, "7-assistant-pas-pret") }
        XCTAssertTrue(suggestion.isEnabled, "L’assistant n’est pas prêt.")
        suggestion.tap()
        let reponse = app.descendants(matching: .any)["reponse-assistant"].firstMatch
        let repondu = reponse.waitForExistence(timeout: 30)
        capturer(app, repondu ? "7-assistant" : "7-assistant-sans-reponse")
        XCTAssertTrue(repondu, "L’assistant n’a pas répondu.")

        // Question pour Claude, sur le PC : la carte « Claude cherche » puis sa réponse.
        let champ = app.textFields["champ-assistant"]
        XCTAssertTrue(champ.waitForExistence(timeout: 5))
        champ.tap()
        champ.typeText("Demande à Claude si Mme Gander a rappelé")
        app.buttons["envoyer-question"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["carte-claude"].firstMatch.waitForExistence(timeout: 10),
                      "La question n’est pas partie chez Claude.")
        let reponseClaude = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "jeudi")).firstMatch
        let claudeRepond = reponseClaude.waitForExistence(timeout: 30)
        capturer(app, claudeRepond ? "8-claude" : "8-claude-sans-reponse")
        XCTAssertTrue(claudeRepond, "La réponse de Claude n’est pas arrivée.")
        app.buttons["fermer-assistant"].tap()
        XCTAssertTrue(bouton.waitForExistence(timeout: 5))
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
                    if !planning.isSelected {
                        planning.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                        sleep(1)
                    }
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
