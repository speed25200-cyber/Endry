import XCTest
@testable import EndryKit

final class LienAccesTests: XCTestCase {
    func testLienCloudflare() throws {
        let l = try LienAcces.analyser("https://calm-river-1234.trycloudflare.com/app/acces/Zx9_kQ-42abc")
        XCTAssertEqual(l.base.absoluteString, "https://calm-river-1234.trycloudflare.com")
        XCTAssertEqual(l.secret, "Zx9_kQ-42abc")
        XCTAssertEqual(l.hoteAffiche, "calm-river-1234.trycloudflare.com")
    }

    func testLienTailscaleSansSchema() throws {
        let l = try LienAcces.analyser("100.101.12.7:8080/app/acces/abcdef123")
        XCTAssertEqual(l.base.absoluteString, "http://100.101.12.7:8080")
        XCTAssertEqual(l.hoteAffiche, "100.101.12.7:8080")
        XCTAssertEqual(l.secret, "abcdef123")
    }

    func testLienHTTPExplicite() throws {
        let l = try LienAcces.analyser("http://100.64.0.5:8080/app/acces/s3cr3t/")
        XCTAssertEqual(l.base.absoluteString, "http://100.64.0.5:8080")
        XCTAssertEqual(l.secret, "s3cr3t")
    }

    func testLienDansUnEmailColle() throws {
        let texte = """
        Bonjour,
        Voici votre accès : <https://pilotage.example.ch/app/acces/AbC%2DdEf?source=mail>.
        Meilleures salutations
        """
        let l = try LienAcces.analyser(texte)
        XCTAssertEqual(l.base.absoluteString, "https://pilotage.example.ch")
        XCTAssertEqual(l.secret, "AbC-dEf")
    }

    func testDomaineSansSchemaEtPointFinal() throws {
        let l = try LienAcces.analyser("  abc.trycloudflare.com/app/acces/xyz789.  ")
        XCTAssertEqual(l.base.scheme, "https")
        XCTAssertEqual(l.secret, "xyz789")
    }

    func testPrefixeDeCheminConserve() throws {
        let l = try LienAcces.analyser("https://example.ch/endry/app/acces/k1")
        XCTAssertEqual(l.base.absoluteString, "https://example.ch/endry")
    }

    func testErreurs() {
        XCTAssertThrowsError(try LienAcces.analyser("   ")) { XCTAssertEqual($0 as? ErreurLien, .vide) }
        XCTAssertThrowsError(try LienAcces.analyser("https://example.ch/autre")) { XCTAssertEqual($0 as? ErreurLien, .pasUnLienEndry) }
        XCTAssertThrowsError(try LienAcces.analyser("https://example.ch/app/acces/")) { XCTAssertEqual($0 as? ErreurLien, .secretManquant) }
        XCTAssertThrowsError(try LienAcces.analyser("/app/acces/abc")) { XCTAssertEqual($0 as? ErreurLien, .pasUnLienEndry) }
    }
}
