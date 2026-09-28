import Foundation
import XCTest
@testable import EndryKit

@MainActor
final class ConversationTests: XCTestCase {
    private func attendre(_ condition: @MainActor () -> Bool, delai: TimeInterval = 5) async {
        let limite = Date().addingTimeInterval(delai)
        while !condition(), Date() < limite { try? await Task.sleep(for: .milliseconds(30)) }
    }

    func testQuestionEcriteRecoitSaReponseDansLeFil() async {
        let api = APIDemo(latence: .zero, delaiClaude: .milliseconds(150))
        let modele = ModeleConversation(bureau: BureauClaude(api: api))
        await modele.envoyer("Mme Gander a-t-elle rappelé ?")
        await attendre { modele.messages.last?.etat == .recu }
        XCTAssertEqual(modele.messages.count, 2)
        let question = modele.messages[0]
        XCTAssertEqual(question.role, .patron)
        XCTAssertEqual(question.nature, .question)
        let reponse = try? XCTUnwrap(modele.reponse(a: question.id))
        XCTAssertEqual(reponse?.role, .assistant)
        XCTAssertEqual(reponse?.etat, .recu)
        XCTAssertFalse(reponse?.texte.isEmpty ?? true)
        XCTAssertFalse(modele.reflechit)
        XCTAssertEqual(modele.contexte?.hasPrefix("Q : Mme Gander"), true)
    }

    func testMemeFilPuisNouveauApresTrenteMinutes() {
        let modele = ModeleConversation(bureau: nil)
        let debut = Date(timeIntervalSince1970: 1_800_000_000)
        modele.consignerQuestion("Première", source: .voix, le: debut)
        modele.consignerQuestion("Suite", source: .ecrit, le: debut.addingTimeInterval(10 * 60))
        modele.consignerQuestion("Plus tard", source: .ecrit, le: debut.addingTimeInterval(45 * 60))
        XCTAssertEqual(modele.messages[0].conversation, modele.messages[1].conversation)
        XCTAssertNotEqual(modele.messages[1].conversation, modele.messages[2].conversation)
    }

    func testReponseVocaleConsigneeEtDifferee() {
        let modele = ModeleConversation(bureau: nil)
        let id = modele.consignerQuestion("Qui me doit de l’argent ?", source: .voix)
        modele.attendre(id, suivi: .question(id: "Q-9", agent: "comptabilite"), message: nil)
        XCTAssertTrue(modele.reflechit)
        XCTAssertEqual(modele.reponse(a: id)?.questionId, "Q-9")
        XCTAssertEqual(modele.reponse(a: id)?.agent, "Comptabilité")
        modele.differer(id, message: nil)
        XCTAssertEqual(modele.reponse(a: id)?.etat, .differe)
        XCTAssertFalse(modele.reflechit)
        modele.repondre(id, avec: ReponseAgent(statut: .repondu, agent: "comptabilite", reponse: "Deux factures ouvertes.",
                                               decisionReference: "D-12"))
        XCTAssertEqual(modele.reponse(a: id)?.etat, .recu)
        XCTAssertEqual(modele.reponse(a: id)?.texte, "Deux factures ouvertes.")
        XCTAssertEqual(modele.reponse(a: id)?.decisionReference, "D-12")
        XCTAssertEqual(modele.derniereArrivee?.texte, "Deux factures ouvertes.")
        XCTAssertEqual(modele.messages.count, 2)
    }

    func testDemandePartEnSaisieAvecLeDomaine() async {
        var envoye: String?
        let modele = ModeleConversation(bureau: nil, transmettre: { texte in
            envoye = texte
            return .transmise
        })
        modele.choisirAgent(id: "offres", nom: "Offres")
        await modele.envoyer("Prépare l’offre de la Villa Morel", nature: .demande)
        XCTAssertEqual(envoye, "[Pour l’agent Offres] Prépare l’offre de la Villa Morel")
        XCTAssertEqual(modele.messages.count, 2)
        XCTAssertEqual(modele.messages[0].nature, .demande)
        XCTAssertEqual(modele.messages[0].texteEnvoye, envoye)
        XCTAssertEqual(modele.messages[1].role, .note)
        XCTAssertTrue(modele.messages[1].texte.contains("Rien ne part chez un tiers"))
    }

    func testDemandeSansReseauGardee() async {
        let modele = ModeleConversation(bureau: nil, transmettre: { _ in .gardee })
        await modele.envoyer("Commande les plaques", nature: .demande)
        XCTAssertEqual(modele.messages.last?.etat, .differe)
    }

    func testFilConserveSurLIPhone() async throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fichier = dossier.appendingPathComponent("conversation.json")
        defer { try? FileManager.default.removeItem(at: dossier) }
        let modele = ModeleConversation(bureau: nil, fichier: fichier)
        let id = modele.consignerQuestion("Chantiers de la semaine ?", source: .ecrit)
        modele.repondre(id, texte: "Trois chantiers.")
        await attendre({ (try? Data(contentsOf: fichier)).map { String(decoding: $0, as: UTF8.self).contains("Trois") } ?? false })
        let relu = ModeleConversation(bureau: nil, fichier: fichier)
        XCTAssertEqual(relu.messages.map(\.texte), ["Chantiers de la semaine ?", "Trois chantiers."])
        XCTAssertEqual(relu.identifiant, modele.identifiant)
        relu.effacer()
        XCTAssertTrue(relu.messages.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fichier.path))
    }

    func testBlocsDuTexte() {
        let blocs = BlocTexte.decouper("""
        ## Factures ouvertes
        Deux factures **attendent**.
        Suite du paragraphe.

        - FA-101 · 1 200 CHF
        * FA-102 · 800 CHF
        1. Relire
        2) Valider
        ```
        code
        ```
        """)
        XCTAssertEqual(blocs, [
            .titre("Factures ouvertes"),
            .paragraphe("Deux factures **attendent**.\nSuite du paragraphe."),
            .puce("FA-101 · 1 200 CHF"),
            .puce("FA-102 · 800 CHF"),
            .numero("1", "Relire"),
            .numero("2", "Valider"),
            .code("code"),
        ])
        XCTAssertEqual(BlocTexte.decouper("1200 CHF. Payé."), [.paragraphe("1200 CHF. Payé.")])
        XCTAssertEqual(BlocTexte.sansBalises("## Titre\nUn **mot** et `code`"), "Titre\nUn mot et code")
    }

    func testNatureProbable() {
        XCTAssertEqual(ModeleConversation.natureProbable("Prépare l’offre pour la Villa Morel"), .demande)
        XCTAssertEqual(ModeleConversation.natureProbable("Peux-tu rédiger la réponse à Mme Rey ?"), .demande)
        XCTAssertEqual(ModeleConversation.natureProbable("Qui me doit de l’argent ?"), .question)
        XCTAssertEqual(ModeleConversation.natureProbable("Est-ce que la facture FA-12 est payée ?"), .question)
        XCTAssertEqual(ModeleConversation.natureProbable(""), .question)
    }
}
