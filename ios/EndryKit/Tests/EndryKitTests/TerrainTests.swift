import XCTest
@testable import EndryKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Transport qui répond selon le chemin et garde les requêtes reçues.
final class TransportRoutes: TransportHTTP, @unchecked Sendable {
    private let verrou = NSLock()
    private var recues: [URLRequest] = []
    let reponses: [String: (Int, String)]

    init(_ reponses: [String: (Int, String)]) { self.reponses = reponses }

    var requetes: [URLRequest] { verrou.withLock { recues } }

    func executer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse) {
        verrou.withLock { recues.append(requete) }
        let chemin = requete.url?.path ?? ""
        let (statut, corps) = reponses.first { chemin.hasSuffix($0.key) }?.value ?? (404, #"{"erreur":"inconnu"}"#)
        let reponse = HTTPURLResponse(url: requete.url!, statusCode: statut, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        return (Data(corps.utf8), reponse)
    }
}

final class AnalyseurRegieTests: XCTestCase {
    func testDicteeComplete() {
        let r = AnalyseurRegie.analyser(
            "Marco et moi trois heures chacun. Posé un boiler 300 litres, 4 mètres de tube multicouche 16 et puis 2 raccords Mapress 22. Déplacement compris.",
            moi: "Luc")
        XCTAssertEqual(r.heures.map(\.intervenant), ["Luc", "Marco"])
        XCTAssertEqual(r.heures.map(\.heures), [3, 3])
        XCTAssertEqual(r.deplacement, true)
        XCTAssertEqual(r.materiel.count, 3)
        XCTAssertEqual(r.materiel[0].designation, "Boiler 300 litres")
        XCTAssertEqual(r.materiel[1].quantite, 4)
        XCTAssertEqual(r.materiel[1].unite, "m")
        XCTAssertEqual(r.materiel[1].designation, "Tube multicouche 16")
        XCTAssertEqual(r.materiel[2].designation, "Raccords Mapress 22")
        XCTAssertTrue(r.travaux.contains("Posé un boiler 300 litres"))
    }

    func testDurees() {
        XCTAssertEqual(AnalyseurRegie.duree(dans: "2 h 30"), 2.5)
        XCTAssertEqual(AnalyseurRegie.duree(dans: "2h30"), 2.5)
        XCTAssertEqual(AnalyseurRegie.duree(dans: "1,5 heure"), 1.5)
        XCTAssertEqual(AnalyseurRegie.duree(dans: AnalyseurRegie.nombresEnChiffres("deux heures et demie")), 2.5)
        XCTAssertEqual(AnalyseurRegie.duree(dans: AnalyseurRegie.nombresEnChiffres("une demi-heure")), 0.5)
        XCTAssertEqual(AnalyseurRegie.duree(dans: "45 minutes"), 0.75)
        XCTAssertNil(AnalyseurRegie.duree(dans: "posé 2 raccords"))
    }

    func testHeuresPourUnTravailEtSansDeplacement() {
        let r = AnalyseurRegie.analyser("J'ai passé 2 heures pour changer le mitigeur de la douche; sans déplacement")
        XCTAssertEqual(r.heures.first?.intervenant, "Patron")
        XCTAssertEqual(r.heures.first?.heures, 2)
        XCTAssertEqual(r.deplacement, false)
        XCTAssertTrue(r.travaux.contains("Changer le mitigeur de la douche"))
    }

    func testMemeIntervenantAdditionne() {
        let r = AnalyseurRegie.analyser("Luc 2 heures. Débouché la colonne. Luc encore 1 h 30.")
        XCTAssertEqual(r.heures.count, 1)
        XCTAssertEqual(r.heures.first?.heures, 3.5)
    }
}

final class BonRegieTests: XCTestCase {
    func testResumeSigneEtEnvoi() throws {
        let dossier = Fixtures.dossierDetaille
        var bon = BonRegie.nouveau(pour: dossier, le: DateEndry.lire("2026-09-28T14:32:00")!)
        XCTAssertEqual(bon.numero, "RG-20260928-1432")
        XCTAssertEqual(BonRegie.nouveau(pour: nil, le: DateEndry.lire("2026-09-28T02:05:00")!).numero, "RG-20260928-0205")
        XCTAssertFalse(bon.manques.isEmpty)
        bon.travaux = "Remplacement du mitigeur de la douche."
        bon.heures = [LigneHeures(intervenant: "Marco", heures: 1.5)]
        bon.materiel = [LigneMateriel(designation: "Mitigeur thermostatique", quantite: 1)]
        XCTAssertTrue(bon.manques.isEmpty)
        bon.signer(par: "M. Morel", le: DateEndry.lire("2026-09-28T15:05:00")!)
        XCTAssertTrue(bon.estSigne)
        XCTAssertTrue(bon.resume.contains("Marco 1 h 30"))
        XCTAssertTrue(bon.resume.contains("Signé sur place par M. Morel le 28.09.2026 à 15 h 05"))
        XCTAssertFalse(bon.resume.contains("CHF"), "aucun prix sur un bon de régie")

        let envoi = bon.envoi(pdf: Data([0x25, 0x50]), signature: Data([0x89]), photos: [])
        XCTAssertEqual(envoi.cle, bon.numero)
        XCTAssertEqual(envoi.fichiers.map(\.typeMIME), ["application/pdf", "image/png"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: envoi.donnees) as? [String: Any])
        XCTAssertEqual(json["signataire"] as? String, "M. Morel")
        XCTAssertEqual(json["signe_le"] as? String, "2026-09-28T15:05:00")
        XCTAssertEqual(json["chantier_id"] as? String, dossier.id)
        // Repli par saisie : seules les images, avec le domaine Comptabilité.
        XCTAssertEqual(envoi.photosSaisie.count, 1)
        XCTAssertTrue(envoi.texteSaisie.hasPrefix("[Pour l’agent Comptabilité] Bon de régie"))
    }
}

final class BonLivraisonTests: XCTestCase {
    let lignes = [
        "Meier Tobler SA", "Bahnstrasse 24", "Bulletin de livraison n° BL-2026-48817", "Date : 26.09.2026",
        "Votre commande : C-5521", "Commission : Morel Epalinges PAC",
        "Art. Désignation Quantité Prix",
        "35012 Raccord Mapress 22 mm 12 pce 4.80",
        "4 m Tube multicouche Alpex 16", "1 pce Vase d'expansion 25 l",
        "Total CHF 312.40", "TVA 8.1 % 25.30",
    ]

    func testLectureDuBon() {
        let bon = LecteurBonLivraison.analyser(lignes: lignes)
        XCTAssertEqual(bon.fournisseur, "Meier Tobler")
        XCTAssertEqual(bon.numero, "BL-2026-48817")
        XCTAssertEqual(bon.date, "2026-09-26")
        XCTAssertEqual(bon.commande, "C-5521")
        XCTAssertEqual(bon.commission, "Morel Epalinges PAC")
        XCTAssertEqual(bon.articles.count, 3)
        XCTAssertEqual(bon.articles[0].reference, "35012")
        XCTAssertEqual(bon.articles[0].designation, "Raccord Mapress 22 mm")
        XCTAssertEqual(bon.articles[0].quantite, 12)
        XCTAssertEqual(bon.articles[1].unite, "m")
        XCTAssertEqual(bon.articles[2].designation, "Vase d'expansion 25 l")
        XCTAssertFalse(bon.articles.contains { $0.designation.contains("Total") || $0.designation.contains("TVA") })
    }

    func testLigneLueDeuxFoisComptéeUneFois() {
        let bon = LecteurBonLivraison.analyser(lignes: lignes + ["35012 Raccord Mapress 22 mm 12 pce 4.80"])
        XCTAssertEqual(bon.articles.count, 3)
    }

    func testChantierSuggereDepuisLaCommission() {
        let bon = LecteurBonLivraison.analyser(lignes: lignes)
        let propositions = SuggestionChantier.classer(texte: bon.texteLu, chantiers: Fixtures.chantiers.chantiers)
        XCTAssertEqual(propositions.first?.dossier.id, "18", "Villa Morel, Epalinges")
    }

    func testEnvoiSansMontants() {
        var bon = LecteurBonLivraison.analyser(lignes: lignes)
        bon.chantierId = "18"
        bon.chantier = "Villa Morel"
        XCTAssertTrue(bon.manques.isEmpty)
        let envoi = bon.envoi(pages: [.init(champ: "pieces", nomFichier: "bon-1.jpg", typeMIME: "image/jpeg", donnees: Data([1]))])
        XCTAssertEqual(envoi.type, .bonLivraison)
        XCTAssertTrue(envoi.resume.contains("3 articles"))
        XCTAssertFalse(envoi.resume.contains("312"))
        XCTAssertTrue(envoi.texteSaisie.hasPrefix("[Pour l’agent Achats]"))
    }
}

final class EnvoiTerrainTests: XCTestCase {
    let base = URL(string: "https://pc.exemple.ts.net")!

    func testRouteTerrain() async throws {
        let transport = TransportRoutes(["/terrain": (200, #"{"ok":true,"message":"Reçu","id":"T-9","decision_reference":"V-1"}"#)])
        let client = ClientAPI(base: base, jeton: "J", transport: transport, capacites: CapacitesServeur())
        let envoi = EnvoiTerrain(type: .regie, chantierId: "18", resume: "Régie", donnees: Data(#"{"a":1}"#.utf8),
                                 fichiers: [.init(nomFichier: "r.pdf", typeMIME: "application/pdf", donnees: Data([1]))], cle: "RG-1")
        let r = try await client.envoyerTerrain(envoi)
        XCTAssertEqual(r.decisionReference, "V-1")
        XCTAssertFalse(r.parSaisie)
        let corps = String(decoding: transport.requetes.first?.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(corps.contains("name=\"type\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nregie"))
        XCTAssertTrue(corps.contains("name=\"pieces\"; filename=\"r.pdf\""))
        XCTAssertTrue(corps.contains("name=\"cle\""))
    }

    func testRepliParSaisieSurUnPCPlusAncien() async throws {
        let transport = TransportRoutes([
            "/terrain": (404, #"{"erreur":"inconnu"}"#),
            "/saisie": (200, #"{"ok":true,"message":"Transmis","saisie_id":"S-7"}"#),
        ])
        let capacites = CapacitesServeur()
        let client = ClientAPI(base: base, jeton: "J", transport: transport, capacites: capacites)
        let envoi = EnvoiTerrain(type: .bonLivraison, chantierId: nil, resume: "Bon", donnees: Data("{}".utf8),
                                 fichiers: [.init(nomFichier: "p.jpg", typeMIME: "image/jpeg", donnees: Data([1])),
                                            .init(nomFichier: "p.pdf", typeMIME: "application/pdf", donnees: Data([2]))])
        let r = try await client.envoyerTerrain(envoi)
        XCTAssertTrue(r.parSaisie)
        XCTAssertEqual(r.id, "S-7")
        // Deuxième envoi : la route absente n'est plus rappelée.
        _ = try await client.envoyerTerrain(envoi)
        let chemins = transport.requetes.compactMap { $0.url?.path }
        XCTAssertEqual(chemins.filter { $0.hasSuffix("/terrain") }.count, 1)
        XCTAssertEqual(chemins.filter { $0.hasSuffix("/saisie") }.count, 2)
        let corps = String(decoding: transport.requetes.last?.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(corps.contains("[Pour l’agent Achats]"))
        XCTAssertFalse(corps.contains("p.pdf"), "le PC v1.2 ne lit que les images dans une saisie")
    }

    @MainActor
    func testEnvoiTerrainGardeHorsLignePuisRejoueAvecLaMemeCle() async throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("terrain-\(UUID().uuidString)")
        let api = TransportIntermittent()
        let modele = ModeleSaisie(api: api, file: FileSaisies(dossier: dossier))
        let envoi = EnvoiTerrain(type: .regie, chantierId: "18", resume: "Régie RG-1", donnees: Data("{}".utf8),
                                 fichiers: [.init(nomFichier: "RG-1.pdf", typeMIME: "application/pdf", donnees: Data([1, 2]))], cle: "RG-1")
        let r1 = await modele.transmettre(terrain: envoi)
        XCTAssertEqual(r1, .gardee)
        XCTAssertEqual(modele.enAttente.first?.libelle, "Bon de régie")

        api.enPanne = false
        let relue = ModeleSaisie(api: api, file: FileSaisies(dossier: dossier))
        await relue.viderFile()
        XCTAssertTrue(relue.enAttente.isEmpty)
        let recu = await api.demo.terrainRecu
        XCTAssertEqual(recu, ["RG-1"])
        // Le PC (démo) a préparé la facture de régie à valider.
        let decisions = try await api.demo.envoyer(.decisions)
        XCTAssertTrue(String(decoding: decisions, as: UTF8.self).contains("Facture de régie RG-1"))
    }
}

final class SuiviCommercialTests: XCTestCase {
    let aujourdhui = DateEndry.lire("2026-09-28")!

    func testOffresSansReponse() {
        let offres = Fixtures.argent.offres.offres
        let a = SuiviOffres.aSuivre(offres, le: aujourdhui)
        XCTAssertEqual(a.map(\.offre.numero), ["OF-00037"], "émise le 08.09 : 20 jours ; les autres ont moins de 15 jours")
        XCTAssertEqual(a.first?.jours, 20)
        XCTAssertEqual(a.first?.expireDans, 10)
        XCTAssertTrue(SuiviOffres.aSuivre(offres, le: aujourdhui, ecartees: ["37"]).isEmpty)
        XCTAssertEqual(SuiviOffres.aSuivre(offres, le: aujourdhui, seuil: 7).count, 2)
        let texte = SuiviOffres.texteSaisie(a[0], consignes: "ton chaleureux")
        XCTAssertTrue(texte.contains("ne rien envoyer sans mon accord"))
        XCTAssertFalse(texte.lowercased().contains("relance"))
    }

    func testEntretiensGroupes() throws {
        let liste = try Fixtures.decoder(ListeEntretiens.self, .entretiens).entretiens
        XCTAssertEqual(liste.count, 5)
        let groupes = GroupesEntretiens.grouper(liste, le: aujourdhui)
        XCTAssertEqual(groupes.map(\.titre), ["En retard", "En octobre", "Plus tard"])
        XCTAssertEqual(groupes[0].entretiens.map(\.id), ["E-104"])
        XCTAssertEqual(liste.first { $0.id == "E-118" }?.statut, .propose)
        XCTAssertFalse(liste.first { $0.id == "E-118" }!.peutProposer)
    }

    func testPreparationsDemo() async throws {
        let demo = APIDemo(latence: .zero)
        let liste = try await demo.entretiens()
        let r = try await demo.proposerEntretien(liste[0], consignes: "")
        XCTAssertEqual(r.decisionReference, "V-EN104")
        let apres = try await demo.entretiens()
        XCTAssertEqual(apres[0].statut, .propose)
        let a = SuiviOffres.aSuivre(Fixtures.argent.offres.offres, le: aujourdhui)
        let s = try await demo.preparerSuivi(a[0], consignes: "")
        XCTAssertEqual(s.decisionReference, "V-SU37")
        let cartes = try await demo.decisions().decisions
        XCTAssertTrue(cartes.first { $0.reference == "V-SU37" }?.exigeGlisser ?? false, "un suivi est un envoi à un tiers")
    }

    func testRepliSaisieEntretien() async throws {
        let transport = TransportRoutes(["/saisie": (200, #"{"ok":true,"message":"Transmis","saisie_id":"S-8"}"#)])
        let client = ClientAPI(base: URL(string: "https://pc.exemple.ts.net")!, jeton: "J", transport: transport, capacites: CapacitesServeur())
        let e = Entretien(id: "E-1", client: "Famille Rochat", appareil: "Chaudière", echeance: "2026-10-02")
        let r = try await client.proposerEntretien(e, consignes: "plutôt le matin")
        XCTAssertTrue(r.parSaisie)
        let corps = String(decoding: transport.requetes.last?.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(corps.contains("[Pour l’agent Secrétariat]"))
        XCTAssertTrue(corps.contains("plutôt le matin"))
    }
}

final class EquipeTests: XCTestCase {
    func testSessionOuvrier() throws {
        let s = try Fixtures.decoder(SessionOuverte.self, .sessionOuvrier)
        XCTAssertEqual(s.role, .ouvrier)
        XCTAssertEqual(s.nom, "Marco")
        let patron = try Fixtures.decoder(SessionOuverte.self, .session)
        XCTAssertNil(patron.role)
    }

    @MainActor
    func testOuvertureDeSessionGardeLeRole() async throws {
        let transport = TransportFixe(statut: 200, corps: String(decoding: Fixtures.donnees(.sessionOuvrier), as: UTF8.self))
        let lien = try LienAcces.analyser("https://pc.exemple.ts.net/app/acces/equipe-fictif")
        let i = try await ClientAPI.ouvrirSession(lien, transport: transport)
        XCTAssertTrue(i.estOuvrier)
        XCTAssertEqual(i.nom, "Marco")
    }

    func testJourneeEtPointages() throws {
        let jour = try Fixtures.decoder(JourneeEquipe.self, .equipeJour)
        XCTAssertEqual(jour.chantiers.count, 2)
        XCTAssertEqual(jour.chantiers[0].id, "18")
        var feuille = FeuilleJournee(date: "2026-09-28", ouvrier: "Marco")
        let t0 = DateEndry.lire("2026-09-28T07:32:00")!
        feuille.commencer(jour.chantiers[0], le: t0)
        feuille.commencer(jour.chantiers[1], le: t0.addingTimeInterval(4 * 3600 + 20 * 60))  // arrête le premier
        feuille.arreter(le: t0.addingTimeInterval(8 * 3600 + 5 * 60))
        feuille.commencer(jour.chantiers[0], le: t0.addingTimeInterval(9 * 3600))
        feuille.arreter(le: t0.addingTimeInterval(9 * 3600 + 25 * 60))
        let h = feuille.heuresParChantier()
        XCTAssertEqual(h.map(\.chantierId), ["18", "12"])
        XCTAssertEqual(h[0].heures, 4.75, "4 h 20 + 25 min → 4 h 45")
        XCTAssertEqual(h[1].heures, 3.75)
        XCTAssertNil(feuille.enCours)
        let envoi = feuille.envoi()
        XCTAssertEqual(envoi.type, .journee)
        XCTAssertEqual(envoi.cle, "J-2026-09-28-Marco")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: envoi.donnees) as? [String: Any])
        let pointages = try XCTUnwrap(json["pointages"] as? [[String: Any]])
        XCTAssertEqual(pointages.first?["debut"] as? String, "2026-09-28T07:32:00")
        XCTAssertFalse(envoi.resume.contains("CHF"))
    }

    func testInvitation() async throws {
        let demo = APIDemo(latence: .zero)
        let inv = try await demo.inviterOuvrier(nom: "Marco")
        XCTAssertNotNil(try? LienAcces.analyser(inv.lien ?? ""))
    }
}

final class BriefingTests: XCTestCase {
    func testBriefingDuMatin() throws {
        let date = DateEndry.lire("2026-09-28T06:55:00")!
        let offres = SuiviOffres.aSuivre(Fixtures.argent.offres.offres, le: date)
        let entretiens = try Fixtures.decoder(ListeEntretiens.self, .entretiens).entretiens
        let b = Briefing.composer(accueil: Fixtures.accueil, semaine: Fixtures.chantiers.semaine, argent: Fixtures.argent,
                                  entretiens: entretiens, offresASuivre: offres, prenom: "Luc", le: date)
        XCTAssertTrue(b.ouverture.hasPrefix("Bonjour, Luc. Nous sommes lundi 28 septembre"))
        XCTAssertEqual(b.points.first?.titre, "Chantiers")
        XCTAssertTrue(b.texteParle.contains("Gérance Morel SA à Epalinges"))
        XCTAssertTrue(b.texteParle.contains("décisions vous attendent"))
        XCTAssertTrue(b.texteParle.contains("Famille Rey"))
        XCTAssertTrue(b.texteParle.contains("entretiens sont à planifier"))
        XCTAssertTrue(b.texteParle.contains("francs"))
        XCTAssertFalse(b.texteParle.contains("'"), "pas d’apostrophe de milliers dans le texte parlé")
        // Jamais de montant fournisseur.
        let aPayer = b.points.first { $0.titre == "À payer" }
        XCTAssertFalse(aPayer?.phrase.contains("franc") ?? false)
        XCTAssertLessThanOrEqual(b.resumeNotification.split(separator: "\n").count, 3)

        let discret = Briefing.composer(accueil: Fixtures.accueil, semaine: [], argent: Fixtures.argent, masquerMontants: true, le: date)
        XCTAssertFalse(discret.texteParle.contains("franc"))
    }

    func testMontantParle() {
        XCTAssertEqual(FormatSuisse.montantParle(42_300.4), "42 300 francs")
        XCTAssertEqual(FormatSuisse.montantParle(1), "1 franc")
    }
}

final class RappelsEtReleveTests: XCTestCase {
    func testZonesEtRappel() {
        let date = DateEndry.lire("2026-09-28")!
        let chantiers = Fixtures.chantiers.chantiers
        let zones = RappelsChantier.zones(chantiers: chantiers, semaine: Fixtures.chantiers.semaine, le: date)
        XCTAssertLessThanOrEqual(zones.count, RappelsChantier.maxZones)
        XCTAssertEqual(zones.first?.id, "18")
        let morel = chantiers.first { $0.id == "18" }!
        let r = RappelsChantier.rappel(pour: morel, decisions: Fixtures.cartes, achats: Fixtures.argent.aRefacturer.achats, le: date)
        XCTAssertEqual(r.titre, "Gérance Morel SA — Epalinges")
        XCTAssertTrue(r.corps.contains("Citerne à dégazer"))
        XCTAssertFalse(r.corps.contains("CHF"))
        XCTAssertEqual(RappelsChantier.adresse(morel), "Epalinges, Suisse")
    }

    func testReleveSalleDeBains() throws {
        var r = ReleveMesures(piece: "Salle de bains", chantierId: "18", chantier: "Villa Morel", date: "2026-09-28",
                              murs: [.init(largeur: 2.4, hauteur: 2.5), .init(largeur: 1.85, hauteur: 2.5),
                                     .init(largeur: 2.4, hauteur: 2.5), .init(largeur: 1.85, hauteur: 2.5)],
                              ouvertures: [.init(type: .porte, largeur: 0.8, hauteur: 2.0), .init(type: .fenetre, largeur: 0.6, hauteur: 0.8)],
                              objets: [.init(categorie: "toilet", largeur: 0.4, profondeur: 0.55, hauteur: 0.8),
                                       .init(categorie: "bathtub", largeur: 1.7, profondeur: 0.75, hauteur: 0.6),
                                       .init(categorie: "sink", largeur: 0.6, profondeur: 0.45, hauteur: 0.85),
                                       .init(categorie: "sink", largeur: 0.6, profondeur: 0.45, hauteur: 0.85)])
        XCTAssertEqual(r.perimetre, 8.5, accuracy: 0.001)
        XCTAssertEqual(r.surfaceSol ?? 0, 4.44, accuracy: 0.001)
        XCTAssertEqual(r.surfaceMursNette, 21.25 - 1.6 - 0.48, accuracy: 0.001)
        r.contourSol = [.init(x: 0, y: 0), .init(x: 2.4, y: 0), .init(x: 2.4, y: 1.85), .init(x: 0, y: 1.85)]
        XCTAssertEqual(r.surfaceSol ?? 0, 4.44, accuracy: 0.001)
        XCTAssertTrue(r.resume.contains("Sol 4,44 m²"))
        XCTAssertTrue(r.resume.contains("1 WC, 1 baignoire, 2 lavabos"))
        let envoi = r.envoi(usdz: Data([1]), plan: Data([2]))
        XCTAssertEqual(envoi.fichiers.map(\.typeMIME), ["image/png", "model/vnd.usdz+zip"])
        XCTAssertTrue(envoi.texteSaisie.hasPrefix("[Pour l’agent Offres] Relevé 3D"))
        XCTAssertFalse(String(decoding: envoi.donnees, as: UTF8.self).contains("releve_par"))
    }

    /// Relevé fait par un ouvrier (lien d'équipe) : le bureau sait qui a mesuré ; l'accord reste celui du patron.
    func testReleveParOuvrier() throws {
        var r = ReleveMesures(piece: "Cuisine", chantierId: "18", chantier: "Villa Morel", date: "2026-09-28",
                              murs: [.init(largeur: 3, hauteur: 2.4), .init(largeur: 2, hauteur: 2.4),
                                     .init(largeur: 3, hauteur: 2.4), .init(largeur: 2, hauteur: 2.4)])
        r.relevePar = "Marco"
        XCTAssertTrue(r.resume.contains("Relevé par Marco (équipe)."))
        XCTAssertTrue(r.resume.contains("sans l’accord du patron"))
        XCTAssertFalse(r.resume.contains("mon accord"))
        let envoi = r.envoi(usdz: nil, plan: nil)
        XCTAssertTrue(String(decoding: envoi.donnees, as: UTF8.self).contains(#""releve_par":"Marco""#))
        let decodeur = JSONDecoder()
        decodeur.keyDecodingStrategy = .convertFromSnakeCase
        let relu = try decodeur.decode(ReleveMesures.self, from: envoi.donnees)
        XCTAssertEqual(relu.relevePar, "Marco")
    }
}

@MainActor
final class ModeleEntretiensTests: XCTestCase {
    func testChargerEtProposer() async {
        let modele = ModeleEntretiens(api: APIDemo(latence: .zero))
        await modele.charger()
        XCTAssertEqual(modele.entretiens.count, 5)
        XCTAssertTrue(modele.disponible)
        let e = modele.entretiens[0]
        guard case .success(let r) = await modele.proposer(e, consignes: "") else { return XCTFail("proposition refusée") }
        XCTAssertNotNil(r.decisionReference)
        XCTAssertEqual(modele.entretiens[0].statut, .propose)
    }

    func testPCSansEntretiens() async {
        let transport = TransportRoutes([:])
        let modele = ModeleEntretiens(api: ClientAPI(base: URL(string: "https://pc.exemple.ts.net")!, jeton: "J", transport: transport,
                                                     capacites: CapacitesServeur()))
        await modele.charger()
        XCTAssertFalse(modele.disponible)
        XCTAssertEqual(modele.etat, .pret)
    }
}

@MainActor
final class ModeleEquipeTests: XCTestCase {
    func testPointageGardeEtRelu() async {
        let fichier = FileManager.default.temporaryDirectory.appendingPathComponent("journee-\(UUID().uuidString).json")
        let t0 = DateEndry.lire("2026-09-28T07:30:00")!
        let modele = ModeleEquipe(api: APIDemo(latence: .zero), ouvrier: "Marco", fichier: fichier, le: t0)
        await modele.charger()
        XCTAssertEqual(modele.chantiers.count, 2)
        modele.commencer(modele.chantiers[0], le: t0)
        modele.arreter(le: t0.addingTimeInterval(3 * 3600))
        modele.remarques = "Manque 2 coudes de 22."
        // Relance de l'app le même jour : la journée est relue.
        let relu = ModeleEquipe(api: APIDemo(latence: .zero), ouvrier: "Marco", fichier: fichier, le: t0.addingTimeInterval(4 * 3600))
        XCTAssertEqual(relu.feuille.pointages.count, 1)
        XCTAssertEqual(relu.remarques, "Manque 2 coudes de 22.")
        relu.corriger(chantierId: "18", heures: 3.5)
        XCTAssertEqual(relu.feuille.heuresParChantier().first?.heures, 3.5)
        // Le lendemain : page blanche.
        let demain = ModeleEquipe(api: APIDemo(latence: .zero), ouvrier: "Marco", fichier: fichier, le: t0.addingTimeInterval(86_400))
        XCTAssertTrue(demain.feuille.pointages.isEmpty)
    }
}

final class VoixTerrainTests: XCTestCase {
    let donnees = RepondeurLocal.Donnees(accueil: Fixtures.accueil, argent: Fixtures.argent, chantiers: Fixtures.chantiers.chantiers)

    func testOutilsParLaVoix() {
        guard case .dire(_, let carte) = RepondeurLocal.repondre("Fais un bon de régie pour Morel", avec: donnees) else { return XCTFail() }
        XCTAssertEqual(carte, .ouvrirOutil(outil: "regie", chantierId: "18"))
        guard case .dire(_, let bon) = RepondeurLocal.repondre("Scanner un bon de livraison", avec: donnees) else { return XCTFail() }
        XCTAssertEqual(bon, .ouvrirOutil(outil: "bon_livraison", chantierId: nil))
        guard case .dire(let briefing, _) = RepondeurLocal.repondre("Mon briefing", avec: donnees) else { return XCTFail() }
        XCTAssertTrue(briefing.contains("Nous sommes"))
    }

    func testOutilsExecuteur() async {
        let executeur = ExecuteurOutils(api: APIDemo(latence: .zero))
        let r = await executeur.executer(nom: "ouvrir_outil", arguments: #"{"outil":"releve","chantier_id":"18"}"#)
        XCTAssertEqual(r.effet, .ouvrirOutil(outil: "releve", chantierId: "18"))
        let inconnu = await executeur.executer(nom: "ouvrir_outil", arguments: #"{"outil":"facture"}"#)
        XCTAssertEqual(inconnu.effet, .aucun)
        let b = await executeur.executer(nom: "briefing", arguments: "{}")
        XCTAssertTrue(b.sortie.contains("briefing"))
    }
}
