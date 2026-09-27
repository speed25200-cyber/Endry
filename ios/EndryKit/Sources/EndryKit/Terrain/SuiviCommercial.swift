import Foundation

// MARK: - Offres sans réponse

/// Offre émise depuis longtemps, sans réponse du client : à suivre (jamais une relance de facture).
public struct OffreASuivre: Sendable, Hashable, Identifiable {
    public var offre: Offre
    /// Jours depuis l'émission.
    public var jours: Int
    /// Jours avant la fin de validité (négatif : expirée).
    public var expireDans: Int?

    public var id: String { offre.id }

    public var urgence: String {
        if let expireDans, expireDans < 0 { return "Validité dépassée" }
        if let expireDans, expireDans <= 7 { return expireDans == 0 ? "Expire aujourd’hui" : "Expire dans \(expireDans) j" }
        return "Émise il y a \(jours) jours"
    }
}

public enum SuiviOffres {
    public static let seuilParDefaut = 15

    /// Offres émises depuis au moins `seuil` jours, non écartées et sans suivi préparé depuis `seuil` jours,
    /// les plus proches de l'expiration d'abord.
    public static func aSuivre(_ offres: [Offre], le date: Date = Date(), seuil: Int = seuilParDefaut,
                               ecartees: Set<String> = []) -> [OffreASuivre] {
        offres.compactMap { o -> OffreASuivre? in
            guard !ecartees.contains(o.id), let emise = o.emiseLe.flatMap(DateEndry.lire) else { return nil }
            let jours = DateEndry.jours(de: emise, a: date)
            guard jours >= seuil else { return nil }
            if let suivi = o.dernierSuivi.flatMap(DateEndry.lire), DateEndry.jours(de: suivi, a: date) < seuil { return nil }
            let expire = o.valableJusquAu.flatMap(DateEndry.lire).map { DateEndry.jours(de: date, a: $0) }
            // Offre expirée depuis plus d'un mois : elle n'est plus à suivre.
            if let expire, expire < -30 { return nil }
            return OffreASuivre(offre: o, jours: jours, expireDans: expire)
        }
        .sorted { ($0.expireDans ?? Int.max, -$0.jours) < ($1.expireDans ?? Int.max, -$1.jours) }
    }

    /// Texte de repli (PC sans `/offres/{id}/suivi`) : demande de préparation, rien ne part.
    public static func texteSaisie(_ a: OffreASuivre, consignes: String) -> String {
        let c = consignes.trimmingCharacters(in: .whitespacesAndNewlines)
        return "[Pour l’agent Offres] Préparer un message de suivi pour l’offre \(a.offre.numero) (\(a.offre.client), \(a.offre.titre)), "
            + "émise il y a \(a.jours) jours, sans réponse. Le proposer en décision à valider ; ne rien envoyer sans mon accord."
            + (c.isEmpty ? "" : " Consignes : \(c)")
    }
}

// MARK: - Entretiens récurrents

public enum StatutEntretien: String, Sendable, Hashable {
    case aPlanifier = "a_planifier"
    case propose
    case planifie
    case autre

    public var libelle: String {
        switch self {
        case .aPlanifier: "À planifier"
        case .propose: "Proposition prête"
        case .planifie: "Planifié"
        case .autre: "Suivi"
        }
    }
}

/// Appareil sous entretien périodique (chaudière, boiler, adoucisseur…), repéré par l'assistant dans Bexio.
public struct Entretien: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var client: String
    public var lieu: String?
    public var appareil: String
    public var periodicite: String?
    /// Dernier entretien (`AAAA-MM-JJ`).
    public var dernier: String?
    /// Échéance du prochain (`AAAA-MM-JJ`).
    public var echeance: String?
    public var statut: StatutEntretien
    public var decisionReference: String?
    public var chantierId: String?

    public init(id: String, client: String, lieu: String? = nil, appareil: String, periodicite: String? = nil, dernier: String? = nil,
                echeance: String? = nil, statut: StatutEntretien = .aPlanifier, decisionReference: String? = nil, chantierId: String? = nil) {
        self.id = id
        self.client = client
        self.lieu = lieu
        self.appareil = appareil
        self.periodicite = periodicite
        self.dernier = dernier
        self.echeance = echeance
        self.statut = statut
        self.decisionReference = decisionReference
        self.chantierId = chantierId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        guard let id = c.texte("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "id manquant"))
        }
        self.id = id
        client = c.texte("client", defaut: "Client")
        lieu = c.texte("lieu")
        appareil = c.texte("appareil") ?? c.texte("type") ?? "Installation"
        periodicite = c.texte("periodicite")
        dernier = c.texte("dernier")
        echeance = c.texte("echeance")
        statut = c.texte("statut").flatMap(StatutEntretien.init(rawValue:)) ?? .autre
        decisionReference = c.texte("decision_reference")
        chantierId = c.texte("chantier_id")
    }

    public var dateEcheance: Date? { echeance.flatMap(DateEndry.lire) }
    public var peutProposer: Bool { statut == .aPlanifier || statut == .autre }
}

/// `GET /entretiens` → `{entretiens: [...]}`.
public struct ListeEntretiens: Decodable, Sendable, Equatable {
    public var entretiens: [Entretien]

    public init(entretiens: [Entretien]) { self.entretiens = entretiens }

    public init(from decoder: Decoder) throws {
        if let liste = try? decoder.singleValueContainer().decode([Entretien].self) {
            entretiens = liste
            return
        }
        entretiens = try decoder.champs().liste("entretiens")
    }
}

public enum GroupesEntretiens {
    public struct Groupe: Sendable, Hashable, Identifiable {
        public var titre: String
        public var entretiens: [Entretien]
        public var id: String { titre }
    }

    /// En retard, ce mois-ci, le mois prochain, plus tard ; triés par échéance.
    public static func grouper(_ entretiens: [Entretien], le date: Date = Date()) -> [Groupe] {
        let tries = entretiens.sorted { ($0.dateEcheance ?? .distantFuture) < ($1.dateEcheance ?? .distantFuture) }
        let prochain = DateEndry.moisSuivant(date)
        var retard: [Entretien] = [], ceMois: [Entretien] = [], moisProchain: [Entretien] = [], plusTard: [Entretien] = []
        for e in tries {
            guard let d = e.dateEcheance else { plusTard.append(e); continue }
            if DateEndry.jours(de: date, a: d) < 0 { retard.append(e) }
            else if DateEndry.memeMois(d, date) { ceMois.append(e) }
            else if DateEndry.memeMois(d, prochain) { moisProchain.append(e) }
            else { plusTard.append(e) }
        }
        return [
            Groupe(titre: "En retard", entretiens: retard),
            Groupe(titre: "Ce mois-ci", entretiens: ceMois),
            Groupe(titre: "En \(DateEndry.nomMois(prochain))", entretiens: moisProchain),
            Groupe(titre: "Plus tard", entretiens: plusTard),
        ].filter { !$0.entretiens.isEmpty }
    }

    public static func texteSaisie(_ e: Entretien, consignes: String) -> String {
        let c = consignes.trimmingCharacters(in: .whitespacesAndNewlines)
        let quand = e.echeance.map { " (échéance \(DateEndry.courte($0)))" } ?? ""
        return "[Pour l’agent Secrétariat] Préparer une proposition de rendez-vous d’entretien pour \(e.client)"
            + "\(e.lieu.map { ", \($0)" } ?? "") : \(e.appareil)\(quand). La proposer en décision à valider ; ne rien envoyer sans mon accord."
            + (c.isEmpty ? "" : " Consignes : \(c)")
    }
}

// MARK: - Requêtes v1.3

/// Réponse de `POST /entretiens/{id}/proposer` et `POST /offres/{id}/suivi` : `{ok, message, decision_reference?}`.
public struct ReponsePreparation: Decodable, Sendable, Equatable {
    public var ok: Bool
    public var message: String?
    public var decisionReference: String?
    /// Passée par la saisie (PC sans la route v1.3).
    public var parSaisie: Bool

    public init(ok: Bool, message: String? = nil, decisionReference: String? = nil, parSaisie: Bool = false) {
        self.ok = ok
        self.message = message
        self.decisionReference = decisionReference
        self.parSaisie = parSaisie
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        ok = c.booleen("ok") ?? false
        message = c.texte("message")
        decisionReference = c.texte("decision_reference")
        parSaisie = false
    }
}

extension Requete {
    public static let entretiens = Requete(.get, "\(prefixe)/entretiens", delai: 45)

    public static func proposerEntretien(_ id: String, consignes: String) -> Requete {
        let ident = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return .init(.post, "\(prefixe)/entretiens/\(ident)/proposer", corps: .json(json(consignes.isEmpty ? [:] : ["consignes": consignes])), delai: 45)
    }

    public static func suiviOffre(_ id: String, consignes: String) -> Requete {
        let ident = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return .init(.post, "\(prefixe)/offres/\(ident)/suivi", corps: .json(json(consignes.isEmpty ? [:] : ["consignes": consignes])), delai: 45)
    }
}

extension EndryAPI {
    public func entretiens() async throws(ErreurAPI) -> [Entretien] {
        try await charger(ListeEntretiens.self, .entretiens).entretiens
    }

    /// Demande au bureau de préparer la proposition (décision à valider) ; repli par saisie sur un PC plus ancien.
    public func proposerEntretien(_ e: Entretien, consignes: String) async throws(ErreurAPI) -> ReponsePreparation {
        try await preparer(.proposerEntretien(e.id, consignes: consignes), repli: GroupesEntretiens.texteSaisie(e, consignes: consignes))
    }

    public func preparerSuivi(_ a: OffreASuivre, consignes: String) async throws(ErreurAPI) -> ReponsePreparation {
        try await preparer(.suiviOffre(a.offre.id, consignes: consignes), repli: SuiviOffres.texteSaisie(a, consignes: consignes))
    }

    private func preparer(_ requete: Requete, repli: String) async throws(ErreurAPI) -> ReponsePreparation {
        do throws(ErreurAPI) {
            let reponse = try await charger(ReponsePreparation.self, requete)
            guard reponse.ok else { throw ErreurAPI.refus(reponse.message ?? "Le bureau n’a pas accepté la demande.") }
            return reponse
        } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
            let simple = try await saisie(texte: repli, fichiers: [])
            return ReponsePreparation(ok: true, message: simple.message, parSaisie: true)
        }
    }
}
