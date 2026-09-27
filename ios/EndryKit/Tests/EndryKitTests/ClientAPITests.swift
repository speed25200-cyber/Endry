import XCTest
@testable import EndryKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Serveur factice branché dans URLSession via URLProtocol : aucune requête ne sort de la machine.
final class ServeurFactice: URLProtocol, @unchecked Sendable {
    struct Reponse {
        var statut: Int
        var corps: Data
    }

    nonisolated(unsafe) static var gestionnaire: (@Sendable (URLRequest) -> Reponse)?
    nonisolated(unsafe) static var requetes: [URLRequest] = []
    private static let verrou = NSLock()

    static func reinitialiser(_ gestionnaire: @escaping @Sendable (URLRequest) -> Reponse) {
        verrou.lock(); defer { verrou.unlock() }
        self.gestionnaire = gestionnaire
        requetes = []
    }

    static var dernieres: [URLRequest] {
        verrou.lock(); defer { verrou.unlock() }
        return requetes
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var requete = request
        // URLSession transforme httpBody en flux : on le relit pour les assertions.
        if requete.httpBody == nil, let flux = requete.httpBodyStream {
            flux.open()
            var data = Data()
            let tampon = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            while flux.hasBytesAvailable {
                let lus = flux.read(tampon, maxLength: 4096)
                if lus <= 0 { break }
                data.append(tampon, count: lus)
            }
            tampon.deallocate()
            flux.close()
            requete.httpBody = data
        }
        Self.verrou.lock()
        Self.requetes.append(requete)
        let gestionnaire = Self.gestionnaire
        Self.verrou.unlock()

        let reponse = gestionnaire?(requete) ?? Reponse(statut: 500, corps: Data())
        let http = HTTPURLResponse(url: request.url!, statusCode: reponse.statut, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reponse.corps)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func transport() -> TransportURLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServeurFactice.self]
        return TransportURLSession(session: URLSession(configuration: configuration))
    }
}

/// Transport qui simule une panne réseau.
struct TransportEnPanne: TransportHTTP {
    var code: URLError.Code = .timedOut
    func executer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(code)
    }
}

final class ClientAPITests: XCTestCase {
    let base = URL(string: "https://calm-river-1234.trycloudflare.com")!

    func testOuvertureDeSession() async throws {
        ServeurFactice.reinitialiser { requete in
            guard requete.url?.path == "/app/api/v1/session", requete.httpMethod == "POST" else {
                return .init(statut: 404, corps: Data())
            }
            let corps = (try? JSONSerialization.jsonObject(with: requete.httpBody ?? Data())) as? [String: Any]
            let appareil = corps?["appareil"] as? [String: String]
            return corps?["acces"] as? String == "bon-secret" && appareil?["modele"] == "iPhone17,1"
                ? .init(statut: 200, corps: Fixtures.donnees(.session))
                : .init(statut: 401, corps: Fixtures.donnees(.erreurLienInvalide))
        }
        let lien = try LienAcces.analyser("https://calm-river-1234.trycloudflare.com/app/acces/bon-secret")
        let identifiants = try await ClientAPI.ouvrirSession(lien, appareil: ("iPhone de la direction", "iPhone17,1"), transport: ServeurFactice.transport())
        XCTAssertEqual(identifiants.appareilId, "app-7f3c")
        XCTAssertEqual(identifiants.jeton, "demo-jeton-appareil")
        XCTAssertEqual(identifiants.base, base)
        XCTAssertEqual(identifiants.entreprise, "Endry SA")
        let expire = try XCTUnwrap(identifiants.expireLe)
        XCTAssertEqual(expire.timeIntervalSinceNow, 180 * 86_400, accuracy: 60)
        XCTAssertNil(ServeurFactice.dernieres.first?.value(forHTTPHeaderField: "Authorization"))

        let mauvais = try LienAcces.analyser("https://calm-river-1234.trycloudflare.com/app/acces/revoque")
        do {
            _ = try await ClientAPI.ouvrirSession(mauvais, appareil: ("iPhone", "iPhone17,1"), transport: ServeurFactice.transport())
            XCTFail("un lien révoqué doit échouer")
        } catch {
            XCTAssertEqual(error, .lienInvalide("Ce lien d’accès a été révoqué."))
        }
    }

    func testLectureAvecJetonEtErreur401() async throws {
        ServeurFactice.reinitialiser { requete in
            guard requete.value(forHTTPHeaderField: "Authorization") == "Bearer J1" else {
                return .init(statut: 401, corps: Fixtures.donnees(.erreur401))
            }
            switch requete.url?.path {
            case "/app/api/v1/accueil": return .init(statut: 200, corps: Fixtures.donnees(.accueil))
            case "/app/api/v1/chantiers":
                XCTAssertEqual(requete.url?.query, "etape=planifie")
                return .init(statut: 200, corps: Fixtures.donnees(.chantiers))
            default: return .init(statut: 404, corps: Data())
            }
        }
        let client = ClientAPI(base: base, jeton: "J1", transport: ServeurFactice.transport())
        let accueil = try await client.accueil()
        XCTAssertEqual(accueil.decisions.count, 5)
        _ = try await client.chantiers(etape: "planifie")

        let expire = ClientAPI(base: base, jeton: "ancien", transport: ServeurFactice.transport())
        do {
            _ = try await expire.accueil()
            XCTFail("401 attendu")
        } catch {
            XCTAssertEqual(error, .nonAuthentifie("Jeton expiré ou révoqué."))
            XCTAssertEqual(error.message, "Connexion perdue : collez le nouveau lien.")
            XCTAssertTrue(error.demandeNouveauLien)
        }
    }

    func testActionsDecision() async throws {
        ServeurFactice.reinitialiser { requete in
            let corps = (try? JSONSerialization.jsonObject(with: requete.httpBody ?? Data())) as? [String: String] ?? [:]
            switch requete.url?.path {
            case "/app/api/v1/decisions/V-7K3F9Q/oui":
                return .init(statut: 200, corps: Data(#"{"ok":true,"message":"Envoyé.","decisions_restantes":4}"#.utf8))
            case "/app/api/v1/decisions/V-2M8R4T/corriger":
                return corps["consignes"] == "Mettre 6 h 30"
                    ? .init(statut: 200, corps: Data(#"{"ok":true,"message":"Noté.","decisions_restantes":3}"#.utf8))
                    : .init(statut: 400, corps: Data(#"{"ok":false,"message":"Consignes obligatoires."}"#.utf8))
            default:
                return .init(statut: 200, corps: Data(#"{"ok":false,"message":"Déjà traitée."}"#.utf8))
            }
        }
        let client = ClientAPI(base: base, jeton: "J1", transport: ServeurFactice.transport())
        let oui = try await client.agir(.oui, sur: "V-7K3F9Q")
        XCTAssertEqual(oui.decisionsRestantes, 4)
        let corriger = try await client.agir(.corriger, sur: "V-2M8R4T", consignes: "Mettre 6 h 30")
        XCTAssertEqual(corriger.message, "Noté.")
        do {
            _ = try await client.agir(.corriger, sur: "V-2M8R4T")
            XCTFail()
        } catch {
            XCTAssertEqual(error, .refus("Consignes obligatoires."))
        }
        do {
            _ = try await client.agir(.non, sur: "V-AUTRE")
            XCTFail("ok:false doit être un refus")
        } catch {
            XCTAssertEqual(error, .refus("Déjà traitée."))
        }
        let requetes = ServeurFactice.dernieres
        XCTAssertEqual(requetes.first?.httpMethod, "POST")
        XCTAssertEqual(requetes.first?.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
    }

    func testSaisieMultipart() async throws {
        ServeurFactice.reinitialiser { requete in
            let type = requete.value(forHTTPHeaderField: "Content-Type") ?? ""
            let corps = String(decoding: requete.httpBody ?? Data(), as: UTF8.self)
            let ok = type.hasPrefix("multipart/form-data; boundary=") && corps.contains("Citerne vidée") && corps.contains("filename=\"scan.pdf\"")
            return .init(statut: 200, corps: Data(#"{"ok":\#(ok),"message":"Transmis"}"#.utf8))
        }
        let client = ClientAPI(base: base, jeton: "J1", transport: ServeurFactice.transport())
        let r = try await client.saisie(texte: "Citerne vidée", fichiers: [.init(nomFichier: "scan.pdf", typeMIME: "application/pdf", donnees: PDFDemo.document(titre: "Bon", lignes: []))])
        XCTAssertTrue(r.ok)
    }

    func testJetonJamaisEnvoyeAUnAutreHote() throws {
        let client = ClientAPI(base: base, jeton: "J1", transport: TransportEnPanne())
        let interne = try client.construire(.document("/app/doc/facture/3187"))
        XCTAssertEqual(interne.value(forHTTPHeaderField: "Authorization"), "Bearer J1")
        XCTAssertEqual(interne.url?.absoluteString, "https://calm-river-1234.trycloudflare.com/app/doc/facture/3187")
        let externe = try client.construire(.document("https://ailleurs.example.com/app/doc/facture/1"))
        XCTAssertNil(externe.value(forHTTPHeaderField: "Authorization"))
    }

    func testServeurInjoignableEtTunnelMort() async {
        let client = ClientAPI(base: base, jeton: "J1", transport: TransportEnPanne())
        do {
            _ = try await client.accueil()
            XCTFail()
        } catch {
            XCTAssertTrue(error.estProblemeReseau)
            XCTAssertTrue(error.demandeNouveauLien)
        }
        let horsLigne = ClientAPI(base: base, jeton: "J1", transport: TransportEnPanne(code: .notConnectedToInternet))
        do {
            _ = try await horsLigne.accueil()
            XCTFail()
        } catch {
            XCTAssertEqual(error, .horsLigne)
        }
    }

    func testCalendrierAbsolu() {
        let client = ClientAPI(base: URL(string: "http://100.64.0.5:8080")!, jeton: "J1", transport: TransportEnPanne())
        XCTAssertEqual(client.urlAbsolue("/app/planning.ics?jeton=abc")?.absoluteString, "http://100.64.0.5:8080/app/planning.ics?jeton=abc")
    }
}
