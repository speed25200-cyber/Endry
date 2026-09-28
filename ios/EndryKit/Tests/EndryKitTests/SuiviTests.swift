import XCTest
@testable import EndryKit

final class RapprochementSuiviTests: XCTestCase {
    private let le = DateEndry.lire("2026-09-28T09:12:00")!

    private func action(_ geste: String = "oui") -> ActionSuivie {
        ActionSuivie(id: "D:V-8C4LQW", nature: .decision, reference: "V-8C4LQW",
                     titre: "Préparer la commande de matériel — AN-00024 Villa Morel · 5 ligne(s) de matériel",
                     geste: geste, le: le, etat: geste == "non" ? .ecarte : .transmis)
    }

    private func entree(_ id: String, _ heure: String, type: TypeEntree, titre: String, detail: String? = nil,
                        ref: String? = nil, agent: String = "achats") -> EntreeJournal {
        EntreeJournal(id: id, horodatage: "2026-09-28T\(heure)", agent: agent, type: type, titre: titre, detail: detail,
                      decisionReference: ref)
    }

    func testCommandePrepareeAvecFichier() {
        let journal = [
            entree("1", "09:12:40", type: .action, titre: "Commande préparée (5 articles)",
                   detail: "Fichier créé : Bureau › 00 À traiter › Commandes › « Commande AN-00024 Villa Morel.txt ». Pas envoyée au fournisseur.",
                   ref: "V-8C4LQW"),
            entree("2", "09:12:05", type: .info, titre: "Pris en charge", ref: "V-8C4LQW"),
            entree("3", "08:00:00", type: .action, titre: "Autre dossier", ref: "V-AUTRE"),
        ]
        let a = RapprochementSuivi.appliquer(journal: journal, a: action())
        XCTAssertEqual(a.etat, .fait)
        XCTAssertEqual(a.source, .journal)
        XCTAssertEqual(a.agent, "achats")
        XCTAssertEqual(a.fichiers, [FichierProduit(nom: "Commande AN-00024 Villa Morel.txt", emplacement: "Bureau › 00 À traiter › Commandes")])
        XCTAssertTrue(a.envois.isEmpty, "« Pas envoyée » n’est pas un envoi")
        XCTAssertEqual(a.etapes.map(\.titre), ["Pris en charge", "Commande préparée (5 articles)"])
        XCTAssertEqual(a.resume, "Commande préparée (5 articles)")
    }

    /// Un envoi à un tiers consigné au journal apparaît, avec son destinataire.
    func testEnvoiVisible() {
        let journal = [entree("1", "09:12:20", type: .action, titre: "Réponse de remerciement envoyée à M. Exemple",
                              detail: "Suite à l’offre AN-00024", ref: nil, agent: "secretariat")]
        let a = RapprochementSuivi.appliquer(journal: journal, a: action())
        XCTAssertEqual(a.envois.map(\.destinataire), ["M. Exemple"], "rapproché par le numéro de document cité")
        XCTAssertEqual(a.etat, .fait)
    }

    /// Le même numéro cité avant le geste appartient à l'historique : ignoré.
    func testNumeroAvantLeGesteIgnore() {
        let journal = [entree("1", "08:30:00", type: .emailPrepare, titre: "Offre AN-00024 acceptée par le client")]
        let a = RapprochementSuivi.appliquer(journal: journal, a: action())
        XCTAssertEqual(a.etat, .transmis)
        XCTAssertEqual(a.source, .geste)
    }

    func testErreurEtEcarte() {
        let erreur = [entree("1", "09:13:00", type: .erreur, titre: "Bexio ne répond pas", ref: "V-8C4LQW")]
        XCTAssertEqual(RapprochementSuivi.appliquer(journal: erreur, a: action()).etat, .erreur)
        XCTAssertEqual(RapprochementSuivi.appliquer(journal: erreur, a: action("non")).etat, .ecarte)
        let enCours = [entree("1", "09:12:05", type: .info, titre: "Pris en charge", ref: "V-8C4LQW")]
        XCTAssertEqual(RapprochementSuivi.appliquer(journal: enCours, a: action()).etat, .enCours)
    }

    func testCompteRenduPCFaitFoi() throws {
        let suivis = try JSONDecoder().decode(ListeSuiviPC.self, from: Fixtures.donnees(.suivi)).suivis
        XCTAssertEqual(suivis.count, 3)
        let commande = try XCTUnwrap(suivis.first)
        XCTAssertEqual(commande.etat, .fait)
        XCTAssertEqual(commande.chantierId, "18")
        XCTAssertEqual(commande.fichiers.first?.document, "/app/doc/fichier/cmd-an-00024")
        let a = RapprochementSuivi.appliquer(pc: commande, a: action())
        XCTAssertEqual(a.source, .pc)
        XCTAssertEqual(a.etat, .fait)
        XCTAssertTrue(a.ligneResultat.hasPrefix("Liste de commande prête"))
        // Le journal ne modifie plus une action dont le PC a donné le compte rendu.
        let apres = RapprochementSuivi.appliquer(journal: [entree("9", "09:20:00", type: .erreur, titre: "x", ref: "V-8C4LQW")], a: a)
        XCTAssertEqual(apres.etat, .fait)

        let mail = RapprochementSuivi.action(depuis: suivis[1])
        XCTAssertEqual(mail.envois.first?.destinataire, "c.rey@exemple.ch")
        XCTAssertEqual(mail.etapes.first?.qui, "vous")
        let facture = RapprochementSuivi.action(depuis: suivis[2])
        XCTAssertEqual(facture.etat, .erreur)
        XCTAssertEqual(facture.ligneResultat, "Nouvel essai au prochain passage.")
    }

    func testReperesEtFichiers() {
        XCTAssertEqual(RapprochementSuivi.reperes("Commande AN-00024 et facture RE-00036, bon RG-20260928-1432"),
                       ["AN-00024", "RE-00036", "RG-20260928-1432"])
        XCTAssertEqual(RapprochementSuivi.fichiers(dans: "Le résultat est un fichier : Bureau › 00 À traiter › Commandes › « Commande X.txt ».").first,
                       FichierProduit(nom: "Commande X.txt", emplacement: "Bureau › 00 À traiter › Commandes"))
        XCTAssertEqual(ModeleSuiviActions.titreSaisie("[Pour l’agent Chantiers] Remarque de Marco. Chantier Villa Morel : manque 2 raccords"),
                       "Remarque de Marco")
    }
}

@MainActor
final class ModeleSuiviActionsTests: XCTestCase {
    /// Oui dans l'app → ligne suivie → compte rendu du PC : fichier produit, rien de perdu.
    func testOuiSuiviJusquAuResultat() async throws {
        let api = APIDemo(latence: .zero, delaiClaude: .zero)
        let decisions = ModeleDecisions(api: api)
        let suivi = ModeleSuiviActions(api: api)
        decisions.surGeste = { geste, carte, reponse, consignes in suivi.enregistrer(geste, carte: carte, reponse: reponse, consignes: consignes) }
        await decisions.charger()
        let carte = try XCTUnwrap(decisions.cartes.first { $0.reference == "V-9P1X6D" })
        let ok = await decisions.agir(.oui, sur: carte, geste: .glissement)
        XCTAssertTrue(ok)
        XCTAssertEqual(suivi.actions.first?.etat, .transmis)
        XCTAssertEqual(suivi.actions.first?.etapes.map(\.qui), ["vous", "bureau"])

        await suivi.rafraichir()
        let a = try XCTUnwrap(suivi.pour(reference: "V-9P1X6D"))
        XCTAssertTrue(suivi.comptesRendusPC)
        XCTAssertEqual(a.etat, .fait)
        XCTAssertEqual(a.agent, "offres")
        XCTAssertEqual(a.fichiers.count, 1)
        XCTAssertTrue(a.envois.isEmpty)
        XCTAssertEqual(suivi.derniereIssue?.reference, "V-9P1X6D")
        XCTAssertEqual(suivi.recents().count, 1)

        let non = try XCTUnwrap(decisions.cartes.first { $0.reference == "V-5T7B2N" })
        _ = await decisions.agir(.non, sur: non)
        await suivi.rafraichir()
        XCTAssertEqual(suivi.pour(reference: "V-5T7B2N")?.etat, .ecarte)
    }

    /// PC sans `/suivi` (v1.2) : le journal fait le lien, la route n'est plus rappelée.
    func testRepliJournal() async throws {
        let transport = TransportRoutes([
            "/journal": (200, #"{"entrees":[{"id":"J-1","horodatage":"2099-01-01T10:00:00","agent":"achats","type":"action","titre":"Commande préparée","detail":"Bureau › Commandes › « Commande AN-00099.txt »","decision_reference":"V-1"}]}"#),
        ])
        let api = ClientAPI(base: URL(string: "https://pc.exemple.ts.net")!, jeton: "J", transport: transport, capacites: CapacitesServeur())
        let suivi = ModeleSuiviActions(api: api)
        let carte = Carte(type: .validation, reference: "V-1", genre: "Action", titre: "Préparer la commande AN-00099", motif: "")
        suivi.enregistrer(.oui, carte: carte, reponse: "Validé.")
        await suivi.rafraichir()
        XCTAssertFalse(suivi.comptesRendusPC)
        let a = try XCTUnwrap(suivi.pour(reference: "V-1"))
        XCTAssertEqual(a.etat, .fait)
        XCTAssertEqual(a.fichiers.first?.nom, "Commande AN-00099.txt")
        await suivi.rafraichir()
        XCTAssertEqual(transport.requetes.filter { $0.url?.path.hasSuffix("/suivi") == true }.count, 1)
    }

    func testPersistance() async throws {
        let fichier = FileManager.default.temporaryDirectory.appendingPathComponent("suivi-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fichier) }
        let api = APIDemo(latence: .zero)
        let suivi = ModeleSuiviActions(api: api, fichier: fichier)
        suivi.enregistrer(saisie: "S-1", texte: "Question du patron : où en est la Villa Morel ?", nature: .question)
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: fichier.path) { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(50))
        let relu = ModeleSuiviActions(api: api, fichier: fichier)
        XCTAssertEqual(relu.actions.first?.saisieId, "S-1")
        XCTAssertEqual(relu.actions.first?.titre, "où en est la Villa Morel ?")
    }
}
