import XCTest
@testable import EndryKit

final class DemandeDocumentTests: XCTestCase {
    func testOffreDicteeEtResume() throws {
        var d = DemandeDocument(type: .offre, chantierId: "24", chantier: "Les Pâquerets — chauffe-eau 300 L", client: "M. et Mme Lambert",
                                clientEmail: "lambert@exemple.ch", objet: "Remplacement du chauffe-eau")
        XCTAssertEqual(d.manques, [])
        d.lignes = [LigneDemandee(designation: "Chauffe-eau 300 L", quantite: 1, unite: "pce"),
                    LigneDemandee(designation: "Main-d’œuvre", quantite: 6, unite: "h", prixUnitaire: 98)]
        let r = d.resume
        XCTAssertTrue(r.hasPrefix("Nouvelle offre à préparer pour M. et Mme Lambert : Remplacement du chauffe-eau."))
        XCTAssertTrue(r.contains("1 pce Chauffe-eau 300 L ; 6 h Main-d’œuvre à CHF 98.00 HT"), r)
        XCTAssertTrue(r.contains("Validité 30 jours."))
        XCTAssertTrue(r.hasSuffix("rien ne part au client sans mon accord."))
        let envoi = d.envoi()
        XCTAssertEqual(envoi.type, .demandeOffre)
        XCTAssertTrue(envoi.texteSaisie.hasPrefix("[Pour l’agent Offres] Nouvelle offre depuis l’iPhone."))
        let json = String(decoding: envoi.donnees, as: UTF8.self)
        XCTAssertTrue(json.contains(#""client_email":"lambert@exemple.ch""#), json)
        XCTAssertTrue(json.contains(#""prix_unitaire":98"#), json)
    }

    func testManques() {
        XCTAssertEqual(DemandeDocument(type: .facture).manques, ["le client ou le chantier", "ce qu’il faut facturer"])
        let depuisOffre = DemandeDocument.facture(depuis: OffreSignee(id: "o", numero: "AN-00028", client: "Lambert"), acompte: 30)
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

final class HeuresSecretariatTests: XCTestCase {
    func testDetail() async throws {
        let h = try await APIDemo(latence: .zero).heuresSecretariat()
        XCTAssertEqual(h.heures, 31.5, accuracy: 0.001)
        XCTAssertEqual(h.lignes.count, 13)
        XCTAssertEqual(h.lignes.reduce(0) { $0 + $1.heures }, h.heures, accuracy: 0.001)
        XCTAssertEqual(h.parCategorie.first?.categorie, "Comptabilité")
        XCTAssertEqual(h.documents.first?.format, "pdf")
        XCTAssertEqual(h.moisDisponibles.first, "2026-09")
    }

    /// Navigation : jours du plus récent au plus ancien, filtre par travail, recherche sans accents.
    func testParJourFiltreEtRecherche() async throws {
        let h = try await APIDemo(latence: .zero).heuresSecretariat()
        let jours = h.parJour()
        XCTAssertEqual(jours.map(\.date), jours.map(\.date).sorted(by: >))
        XCTAssertEqual(jours.reduce(0) { $0 + $1.heures }, h.heures, accuracy: 0.001)
        let compta = h.parJour(categorie: "Comptabilité")
        XCTAssertFalse(compta.isEmpty)
        XCTAssertTrue(compta.flatMap(\.lignes).allSatisfy { $0.categorie == "Comptabilité" })
        let tri = h.parJour(recherche: "  E-MAILS ")
        XCTAssertTrue(tri.flatMap(\.lignes).contains { $0.libelle.contains("e-mails") })
        XCTAssertTrue(h.parJour(recherche: "zzz introuvable").isEmpty)
    }

    /// Le relevé PDF / Excel est produit par le bureau : la demande part au Secrétariat.
    func testDemandeReleveAuSecretariat() async throws {
        let h = try await APIDemo(latence: .zero).heuresSecretariat()
        XCTAssertTrue(h.demandeReleve.hasPrefix("[Pour l’agent Secrétariat]"))
        XCTAssertTrue(h.demandeReleve.contains("septembre 2026"))
        XCTAssertTrue(h.demandeReleve.contains(".xlsx"))
    }

    /// Ancien PC (v1.0 / v1.1) : pas de détail, rien ne casse.
    func testSansDetail() throws {
        let h = try JSONDecoder().decode(HeuresSecretariat.self, from: Data(#"{"heures":"12 h 15","mois":"août 2026"}"#.utf8))
        XCTAssertEqual(h.heures, 12.25, accuracy: 0.001)
        XCTAssertTrue(h.lignes.isEmpty)
        XCTAssertTrue(h.documents.isEmpty)
    }
}
