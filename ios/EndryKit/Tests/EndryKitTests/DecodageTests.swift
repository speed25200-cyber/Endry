import XCTest
@testable import EndryKit

/// Tests de contrat : décodent les réponses exactes du serveur v1.0 (production) et v1.1 (champs ajoutés).
final class ContratV10Tests: XCTestCase {
    func testAccueilV10() throws {
        let a = try Fixtures.decoder(Accueil.self, .accueilV10)
        XCTAssertEqual(a.salut, "Bonjour", "le PC n'envoie que « Bonjour » ou « Bonsoir »")
        XCTAssertFalse(a.pause)
        XCTAssertEqual(a.decisions.count, 5)
        XCTAssertEqual(a.encaisser.factures.count, 6)
        XCTAssertEqual(a.encaisser.total, 49_673.35, accuracy: 0.001)
        XCTAssertEqual(a.encaisser.anciennete.total, a.encaisser.total, accuracy: 0.01)
        XCTAssertEqual(a.encaisser.factures.first?.factureId, "412")
        XCTAssertEqual(a.offres.offres.first?.offreId, "37")
        XCTAssertEqual(a.payer.factures.first?.id, "901")
        XCTAssertEqual(a.payer.cetteSemaine.count, 2)
        XCTAssertEqual(a.chantiers7Jours.first?.client, "Gérance Morel SA")
        XCTAssertEqual(a.chantiers7Jours.first?.debut, "2026-09-28")
        XCTAssertEqual(a.chantiers7Jours.first?.fin, "2026-10-02")
    }

    func testDecisionsV10SansEnvoiTiers() throws {
        let r = try Fixtures.decoder(ReponseDecisions.self, .decisionsV10)
        XCTAssertTrue(r.decisionsAutorisees)
        let mail = try XCTUnwrap(r.decisions.first { $0.reference == "V-7K3F9Q" })
        XCTAssertNil(mail.envoiTiers)
        XCTAssertTrue(mail.partChezUnTiers, "repli sur la liste d’outils : mail_repondre")
        XCTAssertEqual(mail.documents, ["OF-00037-B.pdf"])
        let facture = try XCTUnwrap(r.decisions.first { $0.reference == "V-2M8R4T" })
        XCTAssertTrue(facture.partChezUnTiers, "envoyer_facture")
        XCTAssertEqual(facture.controle?.pointsAVerifier.count, 1)
        let bexio = try XCTUnwrap(r.decisions.first { $0.reference == "V-9P1X6D" })
        XCTAssertFalse(bexio.partChezUnTiers)
        XCTAssertEqual(bexio.texte, "")
        let question = try XCTUnwrap(r.decisions.first { $0.reference == "Q-4HD2XP" })
        XCTAssertTrue(question.estQuestion)
        XCTAssertNil(question.controle, "controle: null")
    }

    func testChantiersV10() throws {
        let r = try Fixtures.decoder(ReponseChantiers.self, .chantiersV10)
        XCTAssertEqual(r.chantiers.count, 10)
        XCTAssertEqual(r.etapes.reduce(0) { $0 + $1.nombre }, 10)
        let gander = try XCTUnwrap(r.chantiers.first { $0.id == "29" })
        XCTAssertNil(gander.montant, "montant 0 : pas de « CHF 0 »")
        XCTAssertNil(gander.dates, "dates vides : pas d’étiquette")
        XCTAssertNil(gander.dateDebut)
        let morel = try XCTUnwrap(r.chantiers.first { $0.id == "18" })
        XCTAssertEqual(morel.etapeIndex, 3)
        XCTAssertTrue(morel.decisionEnAttente)
        XCTAssertEqual(morel.misAJour, "2026-09-26T17:40:00")
        XCTAssertNotNil(morel.fin)
    }

    func testDetailChantierV10() throws {
        let d = try Fixtures.decoder(Dossier.self, .chantierV10)
        XCTAssertEqual(d.elements.count, 3)
        let offre = try XCTUnwrap(d.documents.first { $0.type == .offre })
        XCTAssertNil(offre.numero)
        XCTAssertNil(offre.numeroAffiche, "« offre:31 » est une clé interne, jamais affichée")
        XCTAssertEqual(offre.pdf, "/app/doc/offre/31")
        let achat = try XCTUnwrap(d.achats.first)
        XCTAssertNil(achat.pdf)
        XCTAssertEqual(d.facturesFournisseurs.first?.fournisseur, "Meier Tobler AG")
    }

    func testArgentV10() throws {
        let a = try Fixtures.decoder(Argent.self, .argentV10)
        let achat = try XCTUnwrap(a.aRefacturer.achats.first)
        XCTAssertEqual(achat.libelle, "Siphon design et bonde clic-clac (hors offre)", "champ v1.0 « achat »")
        XCTAssertEqual(achat.chantier, "Résidence Les Tilleuls", "champ v1.0 « dossier »")
        XCTAssertEqual(achat.dossierId, "21")
        XCTAssertNil(achat.fournisseur)
        XCTAssertEqual(Set(a.aRefacturer.achats.map(\.id)).count, 3, "identifiants uniques sans « id »")
        XCTAssertEqual(a.heuresSecretariat?.heures, 31.5, "« 31 h 30 » converti")
        let v = try XCTUnwrap(a.versementsNonIdentifies.first)
        XCTAssertEqual(v.id, "VN-2026-09-23-1500")
        XCTAssertEqual(v.contrepartie, "M. Dupasquier")
        XCTAssertEqual(v.texte, "ACOMPTE TRAVAUX")
        XCTAssertEqual(v.reference, "RF18 5390 0754 7034")
        XCTAssertEqual(a.versementsNonIdentifies[1].reference, nil)
    }

    func testSessionV10() throws {
        let s = try Fixtures.decoder(SessionOuverte.self, .sessionV10)
        XCTAssertEqual(s.jeton, "demo-jeton-commun")
        XCTAssertNil(s.appareilId)
    }
}

final class ContratV11Tests: XCTestCase {
    func testChampsAjoutes() throws {
        let decisions = try Fixtures.decoder(ReponseDecisions.self, .decisions).decisions
        let bexio = try XCTUnwrap(decisions.first { $0.reference == "V-9P1X6D" })
        XCTAssertEqual(bexio.envoiTiers, false)
        XCTAssertEqual(bexio.chantierId, "29")
        let mail = try XCTUnwrap(decisions.first { $0.reference == "V-7K3F9Q" })
        XCTAssertEqual(mail.envoiTiers, true)

        let argent = try Fixtures.decoder(Argent.self, .argent)
        XCTAssertEqual(argent.aRefacturer.achats.first?.id, "achat:12")
        XCTAssertEqual(argent.aRefacturer.achats.first?.fournisseur, "Sanipex SA")
        XCTAssertEqual(argent.heuresSecretariat?.heures, 31.5)
        // v1.10 : comptabilité (reste à facturer des devis acceptés, comptes utilisés, documents).
        let compta = try XCTUnwrap(argent.comptabilite)
        XCTAssertEqual(compta.travaux.first?.reste, 9200)
        XCTAssertEqual(compta.travaux.first?.titre, "PPE Les Cèdres")
        XCTAssertEqual(compta.aFacturer, 12650)
        XCTAssertEqual(compta.nousDoit, 62323.35, accuracy: 0.001)
        XCTAssertEqual(compta.solde, 62323.35 - 16790.75, accuracy: 0.001)
        XCTAssertEqual(compta.comptes.first?.numero, "4000")
        XCTAssertEqual(compta.documents.first?.format, "pdf")
        XCTAssertNil(try Fixtures.decoder(Argent.self, .argentV10).comptabilite)

        let details = try Fixtures.decoder([String: Dossier].self, .chantiersDetails)
        let offre = try XCTUnwrap(details["18"]?.documents.first)
        XCTAssertEqual(offre.numeroAffiche, "OF-00031")
    }

    func testEnvoiTiersFaitFoi() throws {
        let json = #"{"reference":"V-X","outil":"mail_envoyer","envoi_tiers":false}"#
        let carte = try JSONDecoder().decode(Carte.self, from: Data(json.utf8))
        XCTAssertFalse(carte.partChezUnTiers)
        let rappel = try JSONDecoder().decode(Carte.self, from: Data(#"{"reference":"V-Y","outil":"envoyer_rappel"}"#.utf8))
        XCTAssertTrue(rappel.partChezUnTiers)
    }

    func testGesteRequisGlisser() throws {
        let json = #"{"reference":"V-Z","outil":"commande_passer","envoi_tiers":false,"geste_requis":"glisser"}"#
        let carte = try JSONDecoder().decode(Carte.self, from: Data(json.utf8))
        XCTAssertEqual(carte.gesteRequis, "glisser")
        XCTAssertTrue(carte.exigeGlisser)
        XCTAssertEqual(carte.libelleGlisser, "Glisser pour valider")
        // Absent : la règle s'applique quand même.
        let sans = try JSONDecoder().decode(Carte.self, from: Data(#"{"reference":"V-W","outil":"note_ajouter"}"#.utf8))
        XCTAssertNil(sans.gesteRequis)
        XCTAssertTrue(sans.exigeGlisser)
    }

    func testSessionAppareilsSaisiesEtat() throws {
        let s = try Fixtures.decoder(SessionOuverte.self, .session)
        XCTAssertEqual(s.appareilId, "app-7f3c")
        let appareils = try Fixtures.decoder(ListeAppareils.self, .appareils).appareils
        XCTAssertEqual(appareils.count, 2)
        XCTAssertEqual(appareils.filter(\.actuel).count, 1)
        let saisies = try Fixtures.decoder(ListeSaisies.self, .saisies).saisies
        XCTAssertEqual(saisies.map(\.statut), [.traite, .traite, .enCours, .traite])
        XCTAssertTrue(saisies[1].decisionPrete)
        XCTAssertFalse(saisies[0].decisionPrete)
        let etat = try Fixtures.decoder(EtatAssistant.self, .etatAssistant)
        XCTAssertEqual(etat, EtatAssistant(pause: false, file: 2, derniereActivite: "2026-09-27T12:40:00", enCours: "Réponse à Mme Rey",
                                            enService: true, horaires: "du lundi au vendredi, de 7 h à 18 h"))
        let voix = try Fixtures.decoder(SessionVoix.self, .sessionVoix)
        XCTAssertFalse(voix.disponible)
    }

    func testSessionVoixDisponible() throws {
        let json = """
        {"disponible": true, "fournisseur": "openai", "client_secret": {"value": "ek_test", "expires_at": 1},
         "modele": "gpt-realtime", "voix": "marin", "instructions": "Tu es l’assistant d’Endry SA.",
         "outils": [{"type": "function", "name": "accueil", "description": "Résumé du jour", "parameters": {"type": "object", "properties": {}}}]}
        """
        let v = try JSONDecoder().decode(SessionVoix.self, from: Data(json.utf8))
        XCTAssertTrue(v.disponible)
        XCTAssertEqual(v.clientSecret, "ek_test")
        XCTAssertEqual(v.outils.first?.nom, "accueil")
        XCTAssertEqual(v.outils.first?.parametres, #"{"properties":{},"type":"object"}"#)
        let sansCle = try JSONDecoder().decode(SessionVoix.self, from: Data(#"{"disponible": true}"#.utf8))
        XCTAssertFalse(sansCle.disponible, "sans secret, jamais disponible")
    }

    func testCleInconnueIgnoree() throws {
        let json = #"{"salut":"Bonjour","nouveau_champ":{"x":1},"decisions":[{"reference":"V-1","futur":[1,2]}]}"#
        let a = try JSONDecoder().decode(Accueil.self, from: Data(json.utf8))
        XCTAssertEqual(a.decisions.count, 1)
    }
}

final class DecodageTests: XCTestCase {
    func testDecodageTolerant() throws {
        let json = """
        {"decisions": [
            {"reference": "Q-AAA", "titre": 42, "destinataires": "a@b.ch", "modifiable": "oui"},
            {"titre": "sans référence : ignorée"},
            "n'importe quoi",
            {"reference": "V-BBB", "controle": {"points_a_verifier": ["IBAN différent"]}, "pieces": [{"url": "/app/doc/facture/9"}]}
        ], "decisions_autorisees": 0}
        """
        let r = try JSONDecoder().decode(ReponseDecisions.self, from: Data(json.utf8))
        XCTAssertEqual(r.decisions.count, 2)
        XCTAssertFalse(r.decisionsAutorisees)
        XCTAssertEqual(r.decisions[0].type, .question)
        XCTAssertEqual(r.decisions[0].titre, "42")
        XCTAssertEqual(r.decisions[0].destinataires, ["a@b.ch"])
        XCTAssertEqual(r.decisions[1].controle?.ok, false)
        XCTAssertEqual(r.decisions[1].pieces.first?.nom, "9")
    }

    func testHeuresTexte() {
        XCTAssertEqual(HeuresSecretariat.lireHeures("31 h 30"), 31.5)
        XCTAssertEqual(HeuresSecretariat.lireHeures("8h"), 8)
        XCTAssertEqual(HeuresSecretariat.lireHeures("7:45"), 7.75)
        XCTAssertEqual(HeuresSecretariat.lireHeures("12,5"), 12.5)
        XCTAssertNil(HeuresSecretariat.lireHeures("beaucoup"))
    }

    func testMontantsEnTexteEtDossierMinimal() throws {
        let d = try JSONDecoder().decode(Dossier.self, from: Data(#"{"id": 7, "montant": "13'695.45", "etape_index": 9, "decision_en_attente": "V-XYZ"}"#.utf8))
        XCTAssertEqual(d.id, "7")
        XCTAssertEqual(d.montant ?? 0, 13_695.45, accuracy: 0.001)
        XCTAssertEqual(d.etapeIndex, 6)
        XCTAssertEqual(d.referenceDecision, "V-XYZ")
        XCTAssertEqual(Double.depuisTexteSuisse("CHF 1’200.–"), 1200)
    }

    func testAccueilVide() throws {
        let a = try JSONDecoder().decode(Accueil.self, from: Data("{}".utf8))
        XCTAssertEqual(a.decisions, [])
        XCTAssertEqual(a.salut, "Bonjour")
    }

    func testRegroupementParClient() {
        let groupes = Fixtures.accueil.encaisser.parClient
        XCTAssertEqual(groupes.first?.client, "PPE Les Cèdres")
        let dubois = groupes.first { $0.client == "Régie Dubois" }
        XCTAssertEqual(dubois?.factures.count, 2)
        XCTAssertEqual(dubois?.retardMax, 24)
    }
}
