import Foundation
import XCTest
@testable import EndryKit

final class FluiditeTests: XCTestCase {
    func testFinDePhraseNeCoupePasLaParole() {
        XCTAssertEqual(FinDePhrase.delai(definitif: "Qui me doit de l’argent ?", provisoire: ""), .milliseconds(800))
        // Un point posé par la dictée à chaque pause ne veut pas dire que la phrase est finie.
        XCTAssertEqual(FinDePhrase.delai(definitif: "Prépare l’offre de la Villa Morel.", provisoire: ""), .milliseconds(1_000))
        XCTAssertEqual(FinDePhrase.delai(definitif: "Quels chantiers", provisoire: "cette sem"), .milliseconds(1_300))
        XCTAssertEqual(FinDePhrase.delai(definitif: "Prépare l’offre pour", provisoire: ""), .milliseconds(2_400))
        XCTAssertEqual(FinDePhrase.delai(definitif: "Dis-moi", provisoire: "euh"), .milliseconds(2_400))
        // Réglage « Long » : une fois et demie plus de patience.
        XCTAssertEqual(FinDePhrase.delai(definitif: "Quels chantiers cette semaine", provisoire: "", patience: 1.5), .milliseconds(1_500))
        XCTAssertEqual(FinDePhrase.delai(definitif: "Qui me doit de l’argent ?", provisoire: "", patience: 0.7), .milliseconds(560))
    }

    func testReponseCourteDiteEnEntier() {
        let r = ResumeOral.pourLaVoix("**Deux** factures sont ouvertes.")
        XCTAssertEqual(r.dit, "Deux factures sont ouvertes.")
        XCTAssertTrue(r.complet)
    }

    func testReponseLongueDiteEnResume() {
        let texte = """
        ## Factures ouvertes
        Trois factures attendent un paiement, pour un total de 12 400 francs.
        - FA-101 : Gérance Morel, 30 jours de retard.
        - FA-102 : Famille Rey, à échéance vendredi.
        - FA-103 : Commune de Moudon, envoyée hier.
        Aucune relance n’est partie : je n’en prépare que sur votre demande, et chacune attend votre Oui.
        """
        let lisible = ResumeOral.lisible(texte)
        XCTAssertFalse(lisible.contains("##"))
        XCTAssertFalse(lisible.contains("- FA"))
        let r = ResumeOral.pourLaVoix(texte, limite: 110)
        XCTAssertFalse(r.complet)
        XCTAssertTrue(lisible.hasPrefix(r.dit), "Le texte dit doit être le début du texte affiché.")
        XCTAssertTrue(r.dit.hasSuffix("francs."))
        XCTAssertLessThanOrEqual(r.dit.count, 110)
    }

    func testUneSeuleLonguePhraseCoupeeAuMot() {
        let phrase = String(repeating: "chantier ", count: 60)
        let r = ResumeOral.pourLaVoix(phrase, limite: 100)
        XCTAssertFalse(r.complet)
        XCTAssertFalse(r.dit.hasSuffix(" "))
        XCTAssertLessThanOrEqual(r.dit.count, 100)
    }

    func testCommandesVocales() {
        XCTAssertEqual(CommandeVocale.detecter("Répète, s’il te plaît"), .repeter)
        XCTAssertEqual(CommandeVocale.detecter("Merci, c’est tout."), .terminer)
        XCTAssertEqual(CommandeVocale.detecter("Ouvre la conversation"), .ouvrirConversation)
        XCTAssertEqual(CommandeVocale.detecter("On change de sujet"), .nouvelleConversation)
        XCTAssertEqual(CommandeVocale.detecter("Parle plus lentement"), .plusLentement)
        XCTAssertEqual(CommandeVocale.detecter("Plus vite !"), .plusVite)
        // Une vraie question n'est jamais prise pour une commande.
        XCTAssertNil(CommandeVocale.detecter("Merci de préparer la facture de la Villa Morel"))
        XCTAssertNil(CommandeVocale.detecter("Stop la commande de matériel chez Sanitas pour le chantier"))
        XCTAssertNil(CommandeVocale.detecter(""))
    }
}

/// Réseau coupé puis rétabli.
actor APICoupee: EndryAPI {
    private let demo = APIDemo(latence: .zero, delaiClaude: .milliseconds(100))
    var coupee = true

    func retablir() { coupee = false }

    func envoyer(_ requete: Requete) async throws(ErreurAPI) -> Data {
        if coupee { throw .horsLigne }
        return try await demo.envoyer(requete)
    }

    nonisolated func urlAbsolue(_ chemin: String) -> URL? { nil }
}

@MainActor
final class ConversationHorsLigneTests: XCTestCase {
    func testQuestionGardeeSansReseauPuisRenvoyee() async {
        let api = APICoupee()
        let modele = ModeleConversation(bureau: BureauClaude(api: api))
        await modele.envoyer("Mme Gander a-t-elle rappelé ?")
        let id = modele.messages[0].id
        XCTAssertEqual(modele.reponse(a: id)?.etat, .differe)
        XCTAssertEqual(modele.enAttenteReseau, 1)
        XCTAssertTrue(modele.reponse(a: id)?.message?.contains("réseau") ?? false)

        await api.retablir()
        await modele.renvoyerEnAttente()
        let limite = Date().addingTimeInterval(5)
        while modele.reponse(a: id)?.etat != .recu, Date() < limite { try? await Task.sleep(for: .milliseconds(30)) }
        XCTAssertEqual(modele.reponse(a: id)?.etat, .recu)
        XCTAssertEqual(modele.enAttenteReseau, 0)
        XCTAssertEqual(modele.messages.count, 2)
    }
}

final class RechercheTests: XCTestCase {
    func testScore() {
        XCTAssertEqual(RechercheGlobale.score(["Villa Morel", "Épalinges"], requete: "morel"), 3)
        XCTAssertEqual(RechercheGlobale.score(["Villa Morel"], requete: "orel"), 1)
        XCTAssertNil(RechercheGlobale.score(["Villa Morel"], requete: "morel dubois"))
        XCTAssertEqual(RechercheGlobale.score(["Épalinges"], requete: "epal"), 3, "Accents ignorés.")
        XCTAssertEqual(RechercheGlobale.score(["RE-00416"], requete: "RE-00416", titre: "RE-00416"), 10)
    }

    func testChercheDansLesDonneesDeDemo() async throws {
        let api = APIDemo(latence: .zero)
        let argent = try await api.argent()
        let chantiers = try await api.chantiers()
        let accueil = try await api.accueil()
        let tous = RechercheGlobale.chercher("a", cartes: accueil.decisions, chantiers: chantiers.chantiers, argent: argent)
        XCTAssertFalse(tous.isEmpty)
        let facture = try XCTUnwrap(argent.encaisser.factures.first)
        let parNumero = RechercheGlobale.chercher(facture.numero, argent: argent)
        XCTAssertEqual(parNumero.first?.genre, .facture)
        XCTAssertEqual(parNumero.first?.cible, .document(chemin: facture.cheminPDF, nom: "\(facture.numero).pdf"))
        let sansFournisseurs = RechercheGlobale.chercher("a", argent: argent, fournisseurs: false)
        XCTAssertFalse(sansFournisseurs.contains { $0.genre == .fournisseur })
        XCTAssertFalse(RechercheGlobale.chercher("a", argent: argent).contains { $0.genre == .fournisseur && $0.detail.contains("CHF") },
                       "Jamais de montant d’achat fournisseur.")
        XCTAssertTrue(RechercheGlobale.chercher("   ", argent: argent).isEmpty)
    }
}

final class InterruptionTests: XCTestCase {
    private let dit = "L’assistant répond : trois factures attendent un paiement, pour un total de douze mille francs."

    func testEchoDeSaVoixNeCoupePas() {
        XCTAssertFalse(Interruption.couper("trois factures attendent", pendant: dit))
        XCTAssertFalse(Interruption.couper("euh", pendant: dit))
        XCTAssertFalse(Interruption.couper("un paiement euh", pendant: dit))
    }

    func testLePatronCoupeEnParlant() {
        XCTAssertTrue(Interruption.couper("Et pour la Villa Morel ?", pendant: dit))
        XCTAssertTrue(Interruption.couper("Stop", pendant: dit))
        XCTAssertTrue(Interruption.couper("Attends", pendant: dit))
        XCTAssertTrue(Interruption.couper("factures non", pendant: dit))
        XCTAssertEqual(Interruption.motsDuPatron("trois factures pour Morel", pendant: dit), ["morel"])
    }

    func testTexteSansEcho() {
        XCTAssertEqual(Interruption.sansEcho("total de euh et pour la Villa Morel", pendant: dit), "et pour la Villa Morel")
        XCTAssertEqual(Interruption.sansEcho("Et Morel", pendant: dit), "Et Morel")
    }

    func testSuiteDeLaPhrase() {
        XCTAssertEqual(Interruption.suite(de: "Prépare l’offre.", nouvelle: "Pour la Villa Morel", apres: 1.5),
                       "Prépare l’offre pour la Villa Morel")
        XCTAssertEqual(Interruption.suite(de: "Prépare l’offre.", nouvelle: "Qui me doit de l’argent ?", apres: 8),
                       "Qui me doit de l’argent ?")
        XCTAssertEqual(Interruption.suite(de: "Prépare l’offre.", nouvelle: "Stop", apres: 1), "Stop")
        XCTAssertEqual(Interruption.suite(de: "Prépare l’offre.", nouvelle: "Répète", apres: 1), "Répète")
    }
}

final class DecoupeurTests: XCTestCase {
    func testPhrasesDitesPendantLecriture() {
        var texte = "Oui. Trois factures attendent un paiement"
        XCTAssertNil(DecoupeurPhrases.prochaine(texte, depuis: 0, fini: false), "Phrase pas encore finie.")
        texte += ", pour 12'400 francs. La plus ancienne"
        let premiere = DecoupeurPhrases.prochaine(texte, depuis: 0, fini: false)
        XCTAssertEqual(premiere?.phrase, "Oui. Trois factures attendent un paiement, pour 12'400 francs.")
        let suite = premiere.map { $0.fin } ?? 0
        XCTAssertNil(DecoupeurPhrases.prochaine(texte, depuis: suite, fini: false))
        texte += " date de 45 jours."
        XCTAssertEqual(DecoupeurPhrases.prochaine(texte, depuis: suite, fini: true)?.phrase, "La plus ancienne date de 45 jours.")
        XCTAssertNil(DecoupeurPhrases.prochaine(texte, depuis: texte.utf16.count, fini: true))
    }

    func testChiffresEtQuestions() {
        let texte = "Le chantier démarre le 12.10.2026 à Épalinges. Voulez-vous le détail ? Je peux aussi"
        let p1 = DecoupeurPhrases.prochaine(texte, depuis: 0, fini: false)
        XCTAssertEqual(p1?.phrase, "Le chantier démarre le 12.10.2026 à Épalinges.")
        let p2 = DecoupeurPhrases.prochaine(texte, depuis: p1?.fin ?? 0, fini: false)
        XCTAssertEqual(p2?.phrase, "Voulez-vous le détail ?")
    }
}
