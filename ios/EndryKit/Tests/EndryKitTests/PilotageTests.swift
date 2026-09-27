import XCTest
@testable import EndryKit

final class EvenementsTests: XCTestCase {
    func testFluxSSE() {
        var analyseur = AnalyseurSSE()
        let lignes = [": connexion ouverte", "event: maj", "data: {\"quoi\": \"decisions\"}", "",
                      "event: maj", "data: {\"quoi\":", "data:  \"saisies\"}", "\r",
                      "event: ping", "data: 1", "",
                      "event: maj", "data: {\"quoi\": \"inconnu\"}", ""]
        let evenements = lignes.compactMap { analyseur.lire($0) }
        XCTAssertEqual(evenements.count, 4)
        XCTAssertEqual(evenements[0].sujet, .decisions)
        XCTAssertEqual(evenements[1].donnees, "{\"quoi\":\n \"saisies\"}")
        XCTAssertEqual(evenements[1].sujet, .saisies)
        XCTAssertNil(evenements[2].sujet)
        XCTAssertNil(evenements[3].sujet)
    }

    func testRequeteFluxPorteLeJeton() throws {
        let client = ClientAPI(base: URL(string: "https://bureau.exemple.ts.net")!, jeton: "demo-jeton-appareil")
        let requete = try client.requeteFlux()
        XCTAssertEqual(requete.url?.absoluteString, "https://bureau.exemple.ts.net/app/api/v1/evenements")
        XCTAssertEqual(requete.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(requete.value(forHTTPHeaderField: "Authorization"), "Bearer demo-jeton-appareil")
    }
}

final class ChargeNotificationTests: XCTestCase {
    func testDecisionSansEnvoiPermetOui() {
        let charge = ChargeNotification(userInfo: [
            "aps": ["alert": ["title": "Offre prête"], "category": "DECISION", "thread-id": "chantier-18"],
            "reference": "V-9P1X6D",
        ])
        XCTAssertEqual(charge.categorie, .decision)
        XCTAssertEqual(charge.fil, "chantier-18")
        XCTAssertTrue(charge.ouiAutorise)
    }

    func testEnvoiATiersJamaisDepuisLaNotification() {
        let charge = ChargeNotification(userInfo: ["aps": ["category": "DECISION_ENVOI"], "reference": "V-7K3F9Q"])
        XCTAssertEqual(charge.categorie, .decisionEnvoi)
        XCTAssertFalse(charge.ouiAutorise)
        // Une question attend une réponse écrite : pas de « Oui » non plus.
        XCTAssertFalse(ChargeNotification(userInfo: ["aps": ["category": "DECISION"], "reference": "Q-4HD2XP"]).ouiAutorise)
    }

    func testChargeInconnueToleree() {
        let charge = ChargeNotification(userInfo: ["reference": " "])
        XCTAssertEqual(charge.categorie, .info)
        XCTAssertNil(charge.reference)
        XCTAssertFalse(charge.ouiAutorise)
    }
}

@MainActor
final class PilotageTests: XCTestCase {
    func testPauseEtReprise() async {
        let api = APIDemo(latence: .zero)
        let pilotage = ModelePilotage(api: api)
        var recu: [Bool] = []
        pilotage.surChangement = { recu.append($0) }
        await pilotage.charger()
        XCTAssertTrue(pilotage.disponible)
        XCTAssertFalse(pilotage.enPause)

        await pilotage.basculer()
        XCTAssertTrue(pilotage.enPause)
        let etat = try? await api.etatAssistant()
        XCTAssertEqual(etat?.pause, true)

        await pilotage.basculer()
        XCTAssertFalse(pilotage.enPause)
        XCTAssertEqual(recu, [true, false])
    }

    func testServeurV10SansPilotage() async {
        let pilotage = ModelePilotage(api: ServeurV10())
        await pilotage.charger()
        XCTAssertFalse(pilotage.disponible)
    }
}

/// Serveur v1.0 : les routes v1.1 n'existent pas.
final class ServeurV10: EndryAPI {
    nonisolated func urlAbsolue(_ chemin: String) -> URL? { URL(string: "https://bureau.exemple.ts.net" + chemin) }
    func envoyer(_ requete: Requete) async throws(ErreurAPI) -> Data {
        throw .serveur(statut: 404, message: nil)
    }
}

final class HorairesTests: XCTestCase {
    private func date(_ texte: String) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let f = DateFormatter()
        f.calendar = c
        f.timeZone = c.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: texte)!
    }

    func testLectureEtProchainPassage() throws {
        let h = try XCTUnwrap(HorairesAssistant(texte: "du lundi au vendredi, de 7 h à 18 h"))
        XCTAssertEqual(h, HorairesAssistant(jours: Set(1...5), debut: 7, fin: 18))
        // 27.09.2026 est un dimanche.
        XCTAssertFalse(h.enService(date("2026-09-27 12:00")))
        XCTAssertEqual(h.prochainPassage(apres: date("2026-09-27 12:00")), "demain à 7 h")
        XCTAssertEqual(h.prochainPassage(apres: date("2026-09-25 19:00")), "lundi à 7 h", "vendredi soir")
        XCTAssertEqual(h.prochainPassage(apres: date("2026-09-28 06:10")), "aujourd’hui à 7 h")
        XCTAssertTrue(h.enService(date("2026-09-28 09:00")))
        XCTAssertNil(HorairesAssistant(texte: "selon disponibilité"))
        XCTAssertEqual(HorairesAssistant(texte: "Du lundi au samedi, 07:00 – 17:30")?.fin, 17)
    }
}
