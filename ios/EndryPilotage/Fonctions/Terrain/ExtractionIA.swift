import EndryKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Structuration des documents de terrain par Apple Intelligence (modèle sur l'iPhone, rien ne sort de l'appareil),
/// avec l'analyse locale d'EndryKit en repli. Le résultat est toujours relu par le patron avant signature ou envoi.
enum ExtractionIA {
    /// Apple Intelligence est prête sur cet iPhone (iOS 26, activée, modèle téléchargé).
    static var disponible: Bool {
        guard !Configuration.testsUI else { return false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    /// Dictée de chantier → heures, matériel, travaux, déplacement.
    static func regie(_ dictee: String, moi: String) async -> AnalyseurRegie.Resultat {
        let local = AnalyseurRegie.analyser(dictee, moi: moi)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), disponible,
           let ia = await avecDelai(12, { try await regieIA(dictee, moi: moi) }) {
            return fusion(ia: ia, local: local)
        }
        #endif
        return local
    }

    /// Lignes lues sur un bon de livraison → fournisseur, numéros, articles (jamais de prix).
    static func bonLivraison(_ lignes: [String]) async -> BonLivraison {
        let local = LecteurBonLivraison.analyser(lignes: lignes)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), disponible,
           let ia = await avecDelai(15, { try await bonIA(lignes.joined(separator: "\n")) }) {
            return fusion(ia: ia, local: local)
        }
        #endif
        return local
    }

    /// Dictée d'une offre ou d'une facture → client, objet, lignes (prix seulement s'ils sont dits).
    static func document(_ dictee: String, type: TypeDemandeDocument) async -> DocumentDicte {
        let local = documentLocal(dictee)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), disponible,
           let ia = await avecDelai(12, { try await documentIA(dictee, type: type) }) {
            var r = ia
            if r.lignes.isEmpty { r.lignes = local.lignes }
            return r
        }
        #endif
        return local
    }

    struct DocumentDicte: Sendable {
        var client = ""
        var objet = ""
        var lignes: [LigneDemandee] = []
    }

    /// Repli sans Apple Intelligence : le matériel et les heures dictés deviennent des lignes.
    static func documentLocal(_ dictee: String) -> DocumentDicte {
        let r = AnalyseurRegie.analyser(dictee, moi: "moi")
        var lignes = r.materiel.map { LigneDemandee(designation: $0.designation, quantite: $0.quantite, unite: $0.unite) }
        let heures = r.heures.reduce(0) { $0 + $1.heures }
        if heures > 0 { lignes.append(LigneDemandee(designation: "Main-d’œuvre", quantite: heures, unite: "h")) }
        if r.deplacement == true { lignes.append(LigneDemandee(designation: "Déplacement", quantite: 1, unite: "forfait")) }
        return DocumentDicte(objet: r.travaux.trimmingCharacters(in: .whitespacesAndNewlines), lignes: lignes)
    }

    // MARK: - Fusion

    /// L'IA comprend mieux la phrase ; l'analyse locale ne rate pas un chiffre. On garde le plus complet.
    static func fusion(ia: AnalyseurRegie.Resultat, local: AnalyseurRegie.Resultat) -> AnalyseurRegie.Resultat {
        var r = ia
        if r.heures.isEmpty { r.heures = local.heures }
        if r.materiel.count < local.materiel.count { r.materiel = local.materiel }
        if r.travaux.trimmingCharacters(in: .whitespaces).isEmpty { r.travaux = local.travaux }
        if local.deplacement != nil { r.deplacement = local.deplacement }
        return r
    }

    static func fusion(ia: BonLivraison, local: BonLivraison) -> BonLivraison {
        var b = local
        func vide(_ s: String?) -> Bool { (s ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        if vide(b.fournisseur) { b.fournisseur = ia.fournisseur }
        if vide(b.numero) { b.numero = ia.numero }
        if vide(b.date) { b.date = ia.date }
        if vide(b.commande) { b.commande = ia.commande }
        if vide(b.commission) { b.commission = ia.commission }
        if ia.articles.count > b.articles.count { b.articles = ia.articles }
        return b
    }

    private static func avecDelai<T: Sendable>(_ secondes: Int, _ travail: @escaping @Sendable () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { groupe in
            groupe.addTask { try? await travail() }
            groupe.addTask {
                try? await Task.sleep(for: .seconds(secondes))
                return nil
            }
            let premier = await groupe.next() ?? nil
            groupe.cancelAll()
            return premier
        }
    }

    // MARK: - Apple Intelligence

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct RegieIA {
        @Guide(description: "Travaux réalisés, en phrases courtes au passé composé, sans les heures ni les noms des personnes")
        var travaux: String
        @Guide(description: "Heures travaillées par personne. « moi », « je » ou « j’ai » désignent le patron")
        var heures: [HeuresIA]
        @Guide(description: "Matériel posé ou fourni, avec la quantité et l’unité ; vide si rien n’est cité")
        var materiel: [MaterielIA]
        @Guide(description: "Vrai si un déplacement est compté, faux si le patron dit sans déplacement")
        var deplacement: Bool
    }

    @available(iOS 26.0, *)
    @Generable
    struct HeuresIA {
        @Guide(description: "Prénom de la personne, ou « moi » pour le patron")
        var intervenant: String
        @Guide(description: "Durée en heures décimales : 2 h 30 = 2.5")
        var heures: Double
    }

    @available(iOS 26.0, *)
    @Generable
    struct MaterielIA {
        @Guide(description: "Désignation courte du matériel, avec marque et diamètre s’ils sont dits")
        var designation: String
        var quantite: Double
        @Guide(description: "Unité : pce, m, kg, l, rouleau, sac, boîte")
        var unite: String
    }

    @available(iOS 26.0, *)
    private static func regieIA(_ dictee: String, moi: String) async throws -> AnalyseurRegie.Resultat {
        let session = LanguageModelSession(instructions: """
            Tu remplis un bon de régie d’une entreprise de sanitaire et chauffage en Suisse romande, à partir de ce que le patron \
            a dicté sur le chantier. Ne jamais inventer : une information non dite reste vide. Aucun prix.
            """)
        let r = try await session.respond(to: "Dictée : « \(dictee) »", generating: RegieIA.self).content
        let heures = r.heures.compactMap { h -> AnalyseurRegie.Resultat.Paire? in
            guard h.heures > 0, h.heures <= 24 else { return nil }
            let nom = ["moi", "je", "patron", "j’ai", "j'ai"].contains(h.intervenant.lowercased()) || h.intervenant.isEmpty ? moi : h.intervenant
            return .init(intervenant: nom, heures: h.heures)
        }
        let materiel = r.materiel.compactMap { m -> AnalyseurRegie.Resultat.Article? in
            guard !m.designation.isEmpty, m.quantite > 0 else { return nil }
            return .init(designation: m.designation, quantite: m.quantite, unite: m.unite.isEmpty ? "pce" : m.unite)
        }
        return .init(travaux: r.travaux, heures: heures, materiel: materiel, deplacement: r.deplacement)
    }

    @available(iOS 26.0, *)
    @Generable
    struct DocumentIA {
        @Guide(description: "Nom du client tel qu’il est dit (« Mme Gander », « Régie Dubois »), vide s’il n’est pas dit")
        var client: String
        @Guide(description: "Objet court du document, sans le nom du client (« Remplacement du boiler 300 l »)")
        var objet: String
        @Guide(description: "Lignes du document : fournitures, main-d’œuvre, déplacement ; vide si rien de précis n’est dit")
        var lignes: [LigneIA]
    }

    @available(iOS 26.0, *)
    @Generable
    struct LigneIA {
        var designation: String
        @Guide(description: "Quantité, 0 si elle n’est pas dite")
        var quantite: Double
        @Guide(description: "Unité : pce, m, h, forfait, kg, l ; vide si inconnue")
        var unite: String
        @Guide(description: "Prix unitaire en francs hors taxe seulement s’il est dit explicitement, sinon 0")
        var prix: Double
    }

    @available(iOS 26.0, *)
    private static func documentIA(_ dictee: String, type: TypeDemandeDocument) async throws -> DocumentDicte {
        let session = LanguageModelSession(instructions: """
            Tu prépares \(type == .offre ? "une offre" : "une facture") d’une entreprise de sanitaire et chauffage en Suisse romande, \
            à partir de ce que le patron a dicté. Ne jamais inventer : ni client, ni prix, ni quantité non dits. \
            Les prix non dits restent à 0 : le bureau appliquera ses tarifs.
            """)
        let r = try await session.respond(to: "Dictée : « \(dictee) »", generating: DocumentIA.self).content
        let lignes = r.lignes.compactMap { l -> LigneDemandee? in
            let d = l.designation.trimmingCharacters(in: .whitespaces)
            guard !d.isEmpty else { return nil }
            return LigneDemandee(designation: d, quantite: l.quantite > 0 ? l.quantite : nil,
                                 unite: l.unite.isEmpty ? nil : l.unite, prixUnitaire: l.prix > 0 ? l.prix : nil)
        }
        return DocumentDicte(client: r.client, objet: r.objet, lignes: lignes)
    }

    @available(iOS 26.0, *)
    @Generable
    struct BonIA {
        @Guide(description: "Fournisseur qui livre (en-tête du bon), vide si illisible")
        var fournisseur: String
        @Guide(description: "Numéro du bon de livraison, vide si absent")
        var numero: String
        @Guide(description: "Date du bon au format AAAA-MM-JJ, vide si absente")
        var date: String
        @Guide(description: "Numéro de commande, vide si absent")
        var commande: String
        @Guide(description: "Commission, chantier ou référence client écrite sur le bon, vide si absente")
        var commission: String
        @Guide(description: "Lignes d’articles livrés, sans les prix ni les totaux")
        var articles: [ArticleIA]
    }

    @available(iOS 26.0, *)
    @Generable
    struct ArticleIA {
        @Guide(description: "Référence ou numéro d’article, vide si absent")
        var reference: String
        var designation: String
        var quantite: Double
        @Guide(description: "Unité : pce, m, kg, l, rouleau, sac, boîte, jeu")
        var unite: String
    }

    @available(iOS 26.0, *)
    private static func bonIA(_ texte: String) async throws -> BonLivraison {
        let session = LanguageModelSession(instructions: """
            Tu lis un bon de livraison d’un fournisseur de sanitaire et chauffage, reconnu par l’appareil photo. \
            Recopie fidèlement ; n’invente rien ; ignore les prix, les totaux, la TVA et les adresses.
            """)
        let extrait = texte.count > 6_000 ? String(texte.prefix(6_000)) : texte
        let r = try await session.respond(to: extrait, generating: BonIA.self).content
        func nonVide(_ s: String) -> String? { s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s }
        let articles = r.articles.compactMap { a -> ArticleLivre? in
            guard !a.designation.isEmpty else { return nil }
            return ArticleLivre(reference: nonVide(a.reference), designation: a.designation, quantite: a.quantite > 0 ? a.quantite : nil,
                                unite: nonVide(a.unite).map(LecteurBonLivraison.normaliserUnite))
        }
        return BonLivraison(fournisseur: nonVide(r.fournisseur), numero: nonVide(r.numero),
                            date: nonVide(r.date).flatMap { DateEndry.lire($0) != nil ? $0 : nil },
                            commande: nonVide(r.commande), commission: nonVide(r.commission), articles: articles, texteLu: texte)
    }
    #endif
}
