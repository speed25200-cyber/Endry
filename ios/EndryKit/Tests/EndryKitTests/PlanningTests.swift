import XCTest
@testable import EndryKit

final class PlanningTests: XCTestCase {
    private var dossiers: [Dossier] { Fixtures.chantiers.chantiers }
    private func jour(_ s: String) -> Date { DateEndry.lire(s)! }

    func testDureeReelleEtActifs() {
        // Villa Morel : 28.09 → 02.10. PPE Les Cèdres : 31.08 → 09.10.
        let mercredi = Planning.actifs(le: jour("2026-09-30"), dans: dossiers).map(\.id)
        XCTAssertEqual(Set(mercredi), ["12", "18"])
        let lundiSuivant = Planning.actifs(le: jour("2026-10-05"), dans: dossiers).map(\.id)
        XCTAssertEqual(Set(lundiSuivant), ["12", "24"], "Morel est fini, Les Pâquerets commencent")
        XCTAssertTrue(Planning.actifs(le: jour("2026-10-03"), dans: dossiers).contains { $0.id == "12" }, "un chantier long couvre le week-end")
    }

    func testBarresSurQuatreSemaines() {
        let debut = Planning.lundi(de: jour("2026-09-30"))
        XCTAssertEqual(DateEndry.courte("2026-09-28"), "28.09.2026")
        let barres = Planning.barres(dossiers, depuis: debut, nombreJours: 28)
        let morel = barres.first { $0.dossier.id == "18" }
        XCTAssertEqual(morel?.debut, 0)
        XCTAssertEqual(morel?.fin, 4)
        XCTAssertEqual(morel?.duree, 5)
        let cedres = barres.first { $0.dossier.id == "12" }
        XCTAssertEqual(cedres?.coupeAvant, true)
        XCTAssertEqual(cedres?.debut, 0)
        XCTAssertEqual(cedres?.fin, 11)
        XCTAssertNil(barres.first { $0.dossier.id == "5" }, "chantier de mai hors fenêtre")
        XCTAssertNil(barres.first { $0.dossier.id == "26" }, "sans dates : pas de barre")
    }

    func testLibellesEtJoursOuvrables() {
        let morel = dossiers.first { $0.id == "18" }!
        XCTAssertEqual(Planning.libelleDates(morel), "28.09 – 02.10")
        XCTAssertEqual(Planning.joursOuvrables(morel), 5)
        let mont = dossiers.first { $0.id == "24" }!
        XCTAssertEqual(Planning.libelleDates(mont), "05.10")
        XCTAssertEqual(Planning.jours(depuis: jour("2026-09-28"), nombre: 14).count, 14)
    }
}

/// Frise de la semaine (accueil Maison Endry) : bandes bornées à lundi → dimanche.
final class FriseSemaineTests: XCTestCase {
    private func semaine(_ json: String) throws -> [Semaine] {
        try JSONDecoder().decode([Semaine].self, from: Data(json.utf8))
    }

    func testBandesBorneesALaSemaine() throws {
        let jours = DateEndry.semaine(contenant: DateEndry.lire("2026-10-01")!)
        let s = try semaine(#"""
        [{"id":"18","titre":"Villa Morel","debut":"2026-09-28","fin":"2026-10-02"},
         {"id":"12","titre":"PPE Les Cèdres","debut":"2026-08-31","date_fin":"2026-10-09"},
         {"id":"24","titre":"Les Pâquerets","debut":"2026-10-05"},
         {"id":"30","titre":"Sans date"}]
        """#)
        let b = FriseSemaine.bandes(s, jours: jours)
        // Même jour de début : la bande la plus courte d'abord.
        XCTAssertEqual(b.map(\.id), ["18", "12"])
        XCTAssertEqual(b[0].debut, 0)
        XCTAssertEqual(b[0].fin, 4)
        XCTAssertFalse(b[0].continueApres)
        XCTAssertEqual(b[1].debut, 0)
        XCTAssertEqual(b[1].fin, 6)
        XCTAssertTrue(b[1].dejaCommence)
        XCTAssertTrue(b[1].continueApres)
    }

    func testMaximumDeBandes() throws {
        let jours = DateEndry.semaine(contenant: DateEndry.lire("2026-10-01")!)
        let s = try semaine(#"[{"id":"a","titre":"A","debut":"2026-09-29"},{"id":"b","titre":"B","debut":"2026-09-30"},{"id":"c","titre":"C","debut":"2026-10-01"},{"id":"d","titre":"D","debut":"2026-10-02"}]"#)
        XCTAssertEqual(FriseSemaine.bandes(s, jours: jours, maximum: 3).map(\.id), ["a", "b", "c"])
    }
}
