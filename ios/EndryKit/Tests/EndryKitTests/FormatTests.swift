import XCTest
@testable import EndryKit

final class FormatTests: XCTestCase {
    func testMontantsSuisses() {
        XCTAssertEqual(FormatSuisse.chf(13_695.45), "CHF 13’695.45")
        XCTAssertEqual(FormatSuisse.chf(0), "CHF 0.00")
        XCTAssertEqual(FormatSuisse.chf(1_234_567.8), "CHF 1’234’567.80")
        XCTAssertEqual(FormatSuisse.chf(999.999), "CHF 1’000.00")
        XCTAssertEqual(FormatSuisse.chf(-42.5), "CHF −42.50")
        XCTAssertEqual(FormatSuisse.chfArrondi(46_109.70), "CHF 46’110")
        let p = FormatSuisse.parties(21_500)
        XCTAssertEqual(p.francs, "21’500")
        XCTAssertEqual(p.centimes, "00")
    }

    func testHeures() {
        XCTAssertEqual(FormatSuisse.heures(31.5), "31 h 30")
        XCTAssertEqual(FormatSuisse.heures(8), "8 h")
        XCTAssertEqual(FormatSuisse.heures(0.1), "0 h 06")
    }

    func testDates() throws {
        XCTAssertEqual(DateEndry.courte("2026-09-22"), "22.09.2026")
        XCTAssertEqual(DateEndry.jourMois("2026-09-22"), "22 sept.")
        XCTAssertNotNil(DateEndry.lire("2026-09-26T07:42:00+02:00"))
        XCTAssertNotNil(DateEndry.lire("2026-09-26T07:42:00.123Z"))
        XCTAssertNotNil(DateEndry.lire("2026-09-26T07:42:00"))
        XCTAssertNil(DateEndry.lire("bientôt"))
        let d = try XCTUnwrap(DateEndry.lire("2026-09-28"))
        XCTAssertEqual(DateEndry.longue(d), "lundi 28 septembre")
        XCTAssertEqual(DateEndry.semaine(contenant: d).count, 7)
        XCTAssertEqual(DateEndry.jourAbrege(DateEndry.semaine(contenant: d)[0]), "lun.")
    }

    /// Lecture rapide (sans formateur) : mêmes instants que les formateurs du système.
    func testLectureRapideIdentiqueAuxFormateurs() {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        XCTAssertEqual(DateEndry.lire("2026-09-26T07:42:00+02:00"), iso.date(from: "2026-09-26T07:42:00+02:00"))
        XCTAssertEqual(DateEndry.lire("2026-09-26T05:42:00Z"), iso.date(from: "2026-09-26T05:42:00Z"))
        XCTAssertEqual(DateEndry.lire("2026-09-26T07:42:00-0130"), iso.date(from: "2026-09-26T07:42:00-01:30"))
        // Sans fuseau : heure suisse (UTC+2 en été).
        XCTAssertEqual(DateEndry.lire("2026-09-26T07:42:00"), iso.date(from: "2026-09-26T05:42:00Z"))
        XCTAssertEqual(DateEndry.lire("2026-09-26 07:42:00"), iso.date(from: "2026-09-26T05:42:00Z"))
        XCTAssertEqual(DateEndry.lire("2026-09-26T07:42"), iso.date(from: "2026-09-26T05:42:00Z"))
        let fraction = DateEndry.lire("2026-09-26T07:42:00.250000")
        XCTAssertEqual(fraction?.timeIntervalSince1970 ?? 0, (iso.date(from: "2026-09-26T05:42:00Z")?.timeIntervalSince1970 ?? 0) + 0.25, accuracy: 0.001)
        // Formes rares toujours lues ; dates impossibles refusées ; résultat gardé en mémoire.
        XCTAssertNotNil(DateEndry.lire("26.09.2026"))
        XCTAssertNil(DateEndry.isoRapide("2026-13-26T07:42:00"))
        XCTAssertNil(DateEndry.isoRapide("2026-09-26T07:42:00 et plus"))
        XCTAssertEqual(DateEndry.lire("2026-09-26T07:42:00"), DateEndry.lire("2026-09-26T07:42:00"))
    }

    func testIlYa() {
        let maintenant = Date()
        XCTAssertEqual(DateEndry.ilYa(maintenant.addingTimeInterval(-10), maintenant: maintenant), "à l’instant")
        XCTAssertEqual(DateEndry.ilYa(maintenant.addingTimeInterval(-300), maintenant: maintenant), "il y a 5 min")
        XCTAssertEqual(DateEndry.ilYa(maintenant.addingTimeInterval(-7_200), maintenant: maintenant), "il y a 2 h")
        XCTAssertEqual(DateEndry.ilYa(maintenant.addingTimeInterval(-86_400 * 3), maintenant: maintenant), "il y a 3 jours")
    }

    func testPDFDemoValide() {
        let pdf = PDFDemo.document(titre: "Facture RE-2026-0412", lignes: ["Montant : CHF 13’695.45"])
        let texte = String(decoding: pdf, as: UTF8.self)
        XCTAssertTrue(texte.hasPrefix("%PDF-1.4"))
        XCTAssertTrue(texte.hasSuffix("%%EOF\n"))
        XCTAssertTrue(texte.contains("/Count 1"))
    }

    func testMultipart() {
        let f = FormulaireMultipart(
            frontiere: "XYZ",
            champs: [Parametre("texte", "Chantier Rochat : citerne vidée")],
            fichiers: [.init(nomFichier: "bon.jpg", typeMIME: "image/jpeg", donnees: Data([1, 2, 3]))]
        )
        let corps = String(decoding: f.corps(), as: UTF8.self)
        XCTAssertTrue(corps.contains("--XYZ\r\nContent-Disposition: form-data; name=\"texte\""))
        XCTAssertTrue(corps.contains("name=\"photos\"; filename=\"bon.jpg\"\r\nContent-Type: image/jpeg"))
        XCTAssertTrue(corps.hasSuffix("--XYZ--\r\n"))
        XCTAssertEqual(f.typeContenu, "multipart/form-data; boundary=XYZ")
    }
}
