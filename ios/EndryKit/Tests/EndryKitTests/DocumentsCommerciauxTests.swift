import XCTest
@testable import EndryKit

final class DemandeDocumentTests: XCTestCase {
    func testOffreDicteeEtResume() throws {
        var d = DemandeDocument(type: .offre, chantierId: "24", chantier: "Le Mont — boiler 300 L", client: "M. et Mme Favre",
                                clientEmail: "favre@exemple.ch", objet: "Remplacement du boiler")
        XCTAssertEqual(d.manques, [])
        d.lignes = [LigneDemandee(designation: "Boiler 300 L", quantite: 1, unite: "pce"),
                    LigneDemandee(designation: "Main-d’œuvre", quantite: 6, unite: "h", prixUnitaire: 98)]
        let r = d.resume
        XCTAssertTrue(r.hasPrefix("Nouvelle offre à préparer pour M. et Mme Favre : Remplacement du boiler."))
        XCTAssertTrue(r.contains("1 pce Boiler 300 L ; 6 h Main-d’œuvre à CHF 98.00 HT"), r)
        XCTAssertTrue(r.contains("Validité 30 jours."))
        XCTAssertTrue(r.hasSuffix("rien ne part au client sans mon accord."))
        let envoi = d.envoi()
        XCTAssertEqual(envoi.type, .demandeOffre)
        XCTAssertTrue(envoi.texteSaisie.hasPrefix("[Pour l’agent Offres] Nouvelle offre depuis l’iPhone."))
        let json = String(decoding: envoi.donnees, as: UTF8.self)
        XCTAssertTrue(json.contains(#""client_email":"favre@exemple.ch""#), json)
        XCTAssertTrue(json.contains(#""prix_unitaire":98"#), json)
    }

    func testManques() {
        XCTAssertEqual(DemandeDocument(type: .facture).manques, ["le client ou le chantier", "ce qu’il faut facturer"])
        let depuisOffre = DemandeDocument.facture(depuis: OffreSignee(id: "o", numero: "AN-00028", client: "Favre"), acompte: 30)
        XCTAssertEqual(depuisOffre.manques, [])
        XCTAssertTrue(depuisOffre.resume.contains("Sur la base de l’offre AN-00028. Facture d’acompte de 30 %."))
        XCTAssertTrue(depuisOffre.envoi().texteSaisie.hasPrefix("[Pour l’agent Comptabilité] Nouvelle facture"))
    }

    /// Démo comme le PC : la demande devient une décision d'envoi qui attend le Oui du patron.
    func testDemoPrepareUneDecision() async throws {
        let api = APIDemo(latence: .zero)
        let d = DemandeDocument(type: .offre, client: "Mme Gander", clientEmail: "gander@exemple.ch", objet: "Adoucisseur")
        let r = try await api.envoyerTerrain(d.envoi())
        let ref = try XCTUnwrap(r.decisionReference)
        let decisions = try await api.decisions().decisions
        let carte = try XCTUnwrap(decisions.first { $0.reference == ref })
        XCTAssertEqual(carte.envoiTiers, true)
        XCTAssertEqual(carte.destinataires, ["gander@exemple.ch"])
        XCTAssertTrue(carte.titre.contains("Mme Gander — Adoucisseur"))
    }
}

@MainActor
final class ModeleOffresSigneesTests: XCTestCase {
    func testClassementDuPC() async throws {
        let modele = ModeleOffresSignees(api: APIDemo(latence: .zero))
        await modele.charger(chantiers: [])
        XCTAssertTrue(modele.parLePC)
        XCTAssertEqual(modele.offres.count, 3)
        XCTAssertEqual(modele.offres.first?.numero, "AN-00028", "la plus récemment reçue d’abord")
        XCTAssertEqual(modele.offres.first?.source, .email)
        XCTAssertEqual(modele.groupes.map(\.suite), [.aPlanifier, .planifiee, .acompte])
        XCTAssertEqual(modele.aPlanifier, 1)
    }

    func testRepliSurLesChantiers() async throws {
        let api = APIDemo(latence: .zero)
        let chantiers = try await api.chantiers().chantiers
        let transport = TransportRoutes([:])
        let pc = ClientAPI(base: URL(string: "https://pc.exemple.ts.net")!, jeton: "J", transport: transport, capacites: CapacitesServeur())
        let modele = ModeleOffresSignees(api: pc)
        await modele.charger(chantiers: chantiers)
        XCTAssertFalse(modele.parLePC)
        XCTAssertEqual(Set(modele.offres.map(\.chantierId)), Set(chantiers.filter { ["acceptee", "planifie"].contains($0.etape) }.map(\.id)))
        XCTAssertTrue(modele.offres.allSatisfy(\.deduite))
    }
}
