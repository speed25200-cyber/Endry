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
        XCTAssertEqual(Set(lundiSuivant), ["12", "24"], "Morel est fini, Le Mont commence")
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
