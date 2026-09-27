import XCTest
@testable import EndryKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
final class ModelesTests: XCTestCase {
    func testDemoOuiNonCorrigerQuestion() async throws {
        let demo = APIDemo(latence: .zero)
        let modele = ModeleDecisions(api: demo)
        await modele.charger()
        XCTAssertEqual(modele.etat, .pret)
        XCTAssertEqual(modele.nombreDecisions, 5)
        XCTAssertTrue(modele.actionsPossibles)

        let cartes = modele.cartes
        let mail = try XCTUnwrap(cartes.first { $0.reference == "V-7K3F9Q" })
        let ok = await modele.agir(.oui, sur: mail)
        XCTAssertTrue(ok)
        XCTAssertEqual(modele.nombreDecisions, 4)
        XCTAssertEqual(modele.toast?.style, .succes)

        let facture = try XCTUnwrap(cartes.first { $0.reference == "V-2M8R4T" })
        let sansConsignes = await modele.agir(.corriger, sur: facture, consignes: "  ")
        XCTAssertFalse(sansConsignes)
        XCTAssertEqual(modele.nombreDecisions, 4)
        let avecConsignes = await modele.agir(.corriger, sur: facture, consignes: "Compter 6 h 30")
        XCTAssertTrue(avecConsignes)

        let question = try XCTUnwrap(cartes.first { $0.estQuestion })
        let reponseVide = await modele.agir(.repondre, sur: question)
        XCTAssertFalse(reponseVide)
        let reponse = await modele.agir(.oui, sur: question, consignes: "Jeudi 1er octobre en fin de journée.")
        XCTAssertTrue(reponse, "une question passe toujours par « repondre »")
        XCTAssertTrue(reponse)

        let paiement = try XCTUnwrap(cartes.first { $0.reference == "V-5T7B2N" })
        let non = await modele.agir(.non, sur: paiement)
        XCTAssertTrue(non)
        XCTAssertEqual(modele.toast?.style, .info)
        XCTAssertEqual(modele.nombreDecisions, 1)

        // Une carte déjà traitée : refus du serveur, puis rechargement.
        let deja = await modele.agir(.oui, sur: mail)
        XCTAssertFalse(deja)
        XCTAssertEqual(modele.toast?.style, .erreur)
        XCTAssertEqual(modele.nombreDecisions, 1)

        let journal = await demo.journal
        XCTAssertTrue(journal.contains("POST /app/api/v1/decisions/V-7K3F9Q/oui"))
    }

    func testHorsLigneAvecCache() async throws {
        let cache = CacheHorsLigne(dossier: nil)
        await cache.enregistrer(Fixtures.donnees(.accueil), cle: "/app/api/v1/accueil", le: Date().addingTimeInterval(-600))
        var erreurs: [ErreurAPI] = []
        let client = ClientAPI(base: URL(string: "https://x.trycloudflare.com")!, jeton: "J", transport: TransportEnPanne())
        let modele = ModeleDecisions(api: client, cache: cache) { erreurs.append($0) }
        await modele.charger()
        XCTAssertEqual(modele.etat, .pret)
        XCTAssertTrue(modele.horsLigne)
        XCTAssertFalse(modele.actionsPossibles)
        XCTAssertEqual(modele.nombreDecisions, 5)
        XCTAssertEqual(DateEndry.ilYa(try XCTUnwrap(modele.majLe)), "il y a 10 min")
        XCTAssertEqual(erreurs.count, 1)

        let refuse = await modele.agir(.oui, sur: modele.cartes[0])
        XCTAssertFalse(refuse)
        XCTAssertEqual(modele.toast?.message, ErreurAPI.horsLigne.message)
    }

    func testSansCacheErreur() async {
        let client = ClientAPI(base: URL(string: "https://x.trycloudflare.com")!, jeton: "J", transport: TransportEnPanne())
        let modele = ModeleArgent(api: client, cache: CacheHorsLigne(dossier: nil))
        await modele.charger()
        guard case .erreur(let e) = modele.etat else { return XCTFail() }
        XCTAssertTrue(e.estProblemeReseau)
    }

    func testCacheDisque() async throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID().uuidString)")
        let cache = CacheHorsLigne(dossier: dossier)
        await cache.enregistrer(Data("{}".utf8), cle: "/app/api/v1/chantiers?etape=tous")
        let relu = CacheHorsLigne(dossier: dossier)
        let lu = await relu.lire(cle: "/app/api/v1/chantiers?etape=tous")
        XCTAssertEqual(lu?.data, Data("{}".utf8))
        await relu.effacer()
        let efface = await CacheHorsLigne(dossier: dossier).lire(cle: "/app/api/v1/chantiers?etape=tous")
        XCTAssertNil(efface)
    }

    func testChantiersFiltreEtWebcal() async throws {
        let modele = ModeleChantiers(api: APIDemo(latence: .zero))
        await modele.charger()
        XCTAssertEqual(modele.chantiers.count, 10)
        XCTAssertEqual(modele.compteurs.count, 8)
        modele.choisir("offre")
        XCTAssertEqual(modele.chantiers.count, 2)
        XCTAssertEqual(modele.tous.count, 10, "le filtre ne touche pas la liste complète")
        XCTAssertTrue(modele.chantiers.allSatisfy { $0.etape == "offre" })
        await modele.actualiser()
        XCTAssertEqual(modele.urlAbonnement?.absoluteString, "webcal://demo.endry.invalid/app/planning.ics?jeton=demo")

        let dossier = ModeleDossier(dossier: modele.tous[0], api: APIDemo(latence: .zero))
        await dossier.charger()
        XCTAssertEqual(dossier.dossier.id, "18")
        XCTAssertEqual(dossier.dossier.documents.count, 2)
    }

    func testSaisie() async throws {
        let modele = ModeleSaisie(api: APIDemo(latence: .zero))
        XCTAssertFalse(modele.peutEnvoyer)
        modele.preparer(prefixe: Fixtures.dossierDetaille.prefixeSaisie)
        XCTAssertEqual(modele.texte, "Chantier Gérance Morel SA — Epalinges : ")
        modele.texte += "citerne dégazée, OK pour démontage."
        XCTAssertFalse(modele.ajouter(PieceSaisie(nom: "enorme.jpg", typeMIME: "image/jpeg", donnees: Data(count: 16 * 1024 * 1024), origine: .photo)))
        XCTAssertTrue(modele.ajouter(PieceSaisie(nom: "bon.pdf", typeMIME: "application/pdf", donnees: Data([1]), origine: .scan)))
        XCTAssertEqual(modele.pieces.count, 1)
        await modele.envoyer()
        guard case .transmis = modele.etat else { return XCTFail("\(modele.etat)") }
        modele.recommencer()
        XCTAssertEqual(modele.texte, "")
    }

    func testSessionConnexionEtDeconnexion() async throws {
        ServeurFactice.reinitialiser { requete in
            requete.url?.path == "/app/api/v1/session"
                ? .init(statut: 200, corps: Fixtures.donnees(.session))
                : .init(statut: 401, corps: Fixtures.donnees(.erreur401))
        }
        let coffre = CoffreMemoire()
        let session = ModeleSession(coffre: coffre, cache: CacheHorsLigne(dossier: nil), transport: ServeurFactice.transport())
        session.appareil = ("iPhone de test", "iPhone17,1")
        XCTAssertEqual(session.etat, .deconnecte)

        do {
            try await session.connecter(texte: "bonjour")
            XCTFail()
        } catch {
            XCTAssertEqual(error, .lien(.pasUnLienEndry))
        }

        try await session.connecter(texte: "https://abc.trycloudflare.com/app/acces/secret-42")
        XCTAssertTrue(session.estConnecte)
        XCTAssertEqual(session.hoteAffiche, "abc.trycloudflare.com")
        XCTAssertEqual(coffre.lire()?.jeton, "demo-jeton-appareil")

        // Un nouveau lancement relit le trousseau.
        let relance = ModeleSession(coffre: coffre, cache: CacheHorsLigne(dossier: nil), transport: ServeurFactice.transport())
        XCTAssertTrue(relance.estConnecte)

        do {
            _ = try await relance.api!.accueil()
        } catch {
            relance.signaler(error)
        }
        XCTAssertTrue(relance.connexionPerdue)

        await session.deconnecter()
        XCTAssertNil(coffre.lire())
        XCTAssertEqual(session.etat, .deconnecte)

        session.activerDemo(latence: .zero)
        XCTAssertTrue(session.estDemo)
        session.signaler(.nonAuthentifie(nil))
        XCTAssertFalse(session.connexionPerdue, "le mode démo ne perd jamais la connexion")
    }

    func testJetonExpireIgnore() {
        let coffre = CoffreMemoire(Identifiants(base: URL(string: "https://a.b")!, jeton: "x", expireLe: Date().addingTimeInterval(-1)))
        let session = ModeleSession(coffre: coffre, cache: CacheHorsLigne(dossier: nil))
        XCTAssertEqual(session.etat, .deconnecte)
    }

    func testBexioIndisponible() async {
        let modele = ModeleChantiers(api: APIDemo(latence: .zero, bexioIndisponible: true))
        await modele.actualiser()
        XCTAssertEqual(modele.toast?.message, "Bexio ne répond pas, réessayez dans un instant.")
        XCTAssertEqual(modele.tous.count, 10, "on recharge quand même la liste")
    }

    func testPauseBloqueLesActionsPasLaLecture() async throws {
        let modele = ModeleDecisions(api: APIDemo(latence: .zero))
        await modele.charger()
        modele.appliquerPause(true)
        XCTAssertTrue(modele.enPause)
        XCTAssertEqual(modele.nombreDecisions, 5, "la lecture reste possible")
        let refuse = await modele.agir(.oui, sur: modele.cartes[2])
        XCTAssertFalse(refuse)
        XCTAssertEqual(modele.toast?.message, "L’assistant est en pause : reprenez-le pour agir.")
    }
}
