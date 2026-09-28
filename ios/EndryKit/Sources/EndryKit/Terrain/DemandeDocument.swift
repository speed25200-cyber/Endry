import Foundation

// MARK: - Nouvelle offre, nouvelle facture (contrat v1.5)
//
// Le patron décrit ce qu'il veut (dicté ou tapé) ; l'assistant du bureau prépare le document dans Bexio (brouillon)
// et en fait une décision d'envoi. Rien ne part chez le client sans le geste du patron sur cette décision.

public enum TypeDemandeDocument: String, Codable, Sendable, CaseIterable, Identifiable {
    case offre, facture

    public var id: String { rawValue }
    public var titre: String { self == .offre ? "Offre" : "Facture" }
    public var typeTerrain: TypeTerrain { self == .offre ? .demandeOffre : .demandeFacture }
}

/// Une ligne demandée. Sans prix : le bureau applique ses tarifs.
public struct LigneDemandee: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var designation: String
    public var quantite: Double?
    public var unite: String?
    /// Prix unitaire HT imposé par le patron (facultatif).
    public var prixUnitaire: Double?

    public init(id: UUID = UUID(), designation: String, quantite: Double? = nil, unite: String? = nil, prixUnitaire: Double? = nil) {
        self.id = id
        self.designation = designation
        self.quantite = quantite
        self.unite = unite
        self.prixUnitaire = prixUnitaire
    }

    enum CodingKeys: String, CodingKey { case designation, quantite, unite, prixUnitaire }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        designation = try c.decode(String.self, forKey: .designation)
        quantite = try c.decodeIfPresent(Double.self, forKey: .quantite)
        unite = try c.decodeIfPresent(String.self, forKey: .unite)
        prixUnitaire = try c.decodeIfPresent(Double.self, forKey: .prixUnitaire)
    }

    public var texte: String {
        var t = ""
        if let q = quantite { t += FormatQuantite.texte(q) + (unite.map { " \($0)" } ?? "") + " " }
        t += designation
        if let p = prixUnitaire { t += " à \(FormatSuisse.chf(p)) HT" }
        return t
    }
}

public struct DemandeDocument: Codable, Sendable, Hashable {
    public var type: TypeDemandeDocument
    public var chantierId: String?
    public var chantier: String?
    public var client: String
    public var clientEmail: String?
    public var clientAdresse: String?
    /// Objet du document (« Remplacement du boiler 300 l »).
    public var objet: String
    public var lignes: [LigneDemandee]
    /// Ce que le patron a dit ou écrit, tel quel : l'assistant s'en sert pour tout ce qui n'est pas dans les lignes.
    public var consignes: String
    /// Offre : validité en jours.
    public var validiteJours: Int?
    /// Facture : offre acceptée sur laquelle elle se base.
    public var offreNumero: String?
    /// Facture : acompte en pour cent (sinon facture complète).
    public var acomptePourcent: Int?
    /// Facture : délai de paiement en jours.
    public var delaiPaiementJours: Int?
    /// `AAAA-MM-JJ`
    public var date: String

    public init(type: TypeDemandeDocument, chantierId: String? = nil, chantier: String? = nil, client: String = "",
                clientEmail: String? = nil, clientAdresse: String? = nil, objet: String = "", lignes: [LigneDemandee] = [],
                consignes: String = "", validiteJours: Int? = nil, offreNumero: String? = nil, acomptePourcent: Int? = nil,
                delaiPaiementJours: Int? = nil, date: String = DateEndry.iso(Date())) {
        self.type = type
        self.chantierId = chantierId
        self.chantier = chantier
        self.client = client
        self.clientEmail = clientEmail
        self.clientAdresse = clientAdresse
        self.objet = objet
        self.lignes = lignes
        self.consignes = consignes
        self.validiteJours = validiteJours ?? (type == .offre ? 30 : nil)
        self.offreNumero = offreNumero
        self.acomptePourcent = acomptePourcent
        self.delaiPaiementJours = delaiPaiementJours ?? (type == .facture ? 30 : nil)
        self.date = date
    }

    private static func vide(_ s: String?) -> Bool { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Ce qui manque avant de transmettre.
    public var manques: [String] {
        var m: [String] = []
        if Self.vide(client) && chantierId == nil { m.append("le client ou le chantier") }
        let lignesUtiles = lignes.filter { !Self.vide($0.designation) }
        if Self.vide(objet) && lignesUtiles.isEmpty && Self.vide(consignes) && offreNumero == nil {
            m.append(type == .offre ? "ce qu’il faut offrir" : "ce qu’il faut facturer")
        }
        return m
    }

    public var resume: String {
        let nom = type == .offre ? "Nouvelle offre" : "Nouvelle facture"
        let pour = Self.vide(client) ? (chantier ?? "le chantier") : client
        var p = ["\(nom) à préparer pour \(pour)\(Self.vide(objet) ? "" : " : \(objet)")."]
        if let chantier, !Self.vide(client), chantier != client { p.append("Chantier : \(chantier).") }
        if let e = clientEmail, !Self.vide(e) { p.append("E-mail du client : \(e).") }
        if let a = clientAdresse, !Self.vide(a) { p.append("Adresse : \(a).") }
        if let n = offreNumero { p.append("Sur la base de l’offre \(n).") }
        if let a = acomptePourcent, a > 0, a < 100 { p.append("Facture d’acompte de \(a) %.") }
        let lignesUtiles = lignes.filter { !Self.vide($0.designation) }
        if !lignesUtiles.isEmpty { p.append("Lignes : " + lignesUtiles.map(\.texte).joined(separator: " ; ") + ".") }
        if !Self.vide(consignes) { p.append("Consignes : \(consignes.trimmingCharacters(in: .whitespacesAndNewlines))") }
        if type == .offre, let v = validiteJours { p.append("Validité \(v) jours.") }
        if type == .facture, let d = delaiPaiementJours { p.append("Paiement à \(d) jours.") }
        p.append("Prix : tarifs du bureau sauf indication. Préparer le brouillon dans Bexio et une décision d’envoi ; rien ne part au client sans mon accord.")
        return p.joined(separator: " ")
    }

    public func envoi(photos: [FormulaireMultipart.Fichier] = [], cle: String = UUID().uuidString) -> EnvoiTerrain {
        EnvoiTerrain(type: type.typeTerrain, chantierId: chantierId, resume: resume, donnees: EnvoiTerrain.json(self),
                     fichiers: photos, cle: cle)
    }

    /// Facture préparée depuis une offre signée.
    public static func facture(depuis o: OffreSignee, acompte: Int? = nil) -> DemandeDocument {
        DemandeDocument(type: .facture, chantierId: o.chantierId, chantier: o.chantier, client: o.client,
                        objet: o.titre ?? "", offreNumero: o.numero, acomptePourcent: acompte)
    }
}

// MARK: - Offres signées (reçues par e-mail, courrier, dans Bexio)

public struct OffreSignee: Decodable, Sendable, Hashable, Identifiable {
    public enum Source: String, Sendable, Hashable {
        case email, courrier, bexio, app, inconnue

        public var libelle: String {
            switch self {
            case .email: "par e-mail"
            case .courrier: "par courrier"
            case .bexio: "dans Bexio"
            case .app: "dans l’app"
            case .inconnue: ""
            }
        }

        public var icone: String {
            switch self {
            case .email: "envelope.fill"
            case .courrier: "envelope.open.fill"
            case .bexio: "building.columns.fill"
            case .app: "iphone"
            case .inconnue: "checkmark.seal.fill"
            }
        }
    }

    /// Où en est l'offre signée : à planifier, planifiée, acompte facturé, facturée.
    public enum Suite: String, Sendable, Hashable, CaseIterable {
        case aPlanifier = "a_planifier"
        case planifiee
        case acompte = "acompte_facture"
        case facturee

        public var libelle: String {
            switch self {
            case .aPlanifier: "À planifier"
            case .planifiee: "Planifiée"
            case .acompte: "Acompte facturé"
            case .facturee: "Facturée"
            }
        }
    }

    public var id: String
    public var numero: String?
    public var titre: String?
    public var client: String
    public var chantierId: String?
    public var chantier: String?
    public var montant: Double?
    /// `AAAA-MM-JJ`
    public var signeeLe: String?
    /// Réception de la signature (`AAAA-MM-JJ` ou horodatage).
    public var recueLe: String?
    public var source: Source
    /// Expéditeur de l'e-mail de retour (client, gérance…).
    public var expediteur: String?
    /// Chemin `/app/doc/…` du document signé reçu.
    public var documentSigne: String?
    /// Chemin de l'offre d'origine.
    public var document: String?
    public var suite: Suite
    public var decisionReference: String?
    /// Vrai si l'élément vient du repli (étape « acceptée » d'un chantier) et non du PC.
    public var deduite: Bool

    public init(id: String, numero: String? = nil, titre: String? = nil, client: String, chantierId: String? = nil,
                chantier: String? = nil, montant: Double? = nil, signeeLe: String? = nil, recueLe: String? = nil,
                source: Source = .inconnue, expediteur: String? = nil, documentSigne: String? = nil, document: String? = nil,
                suite: Suite = .aPlanifier, decisionReference: String? = nil, deduite: Bool = false) {
        self.id = id
        self.numero = numero
        self.titre = titre
        self.client = client
        self.chantierId = chantierId
        self.chantier = chantier
        self.montant = montant
        self.signeeLe = signeeLe
        self.recueLe = recueLe
        self.source = source
        self.expediteur = expediteur
        self.documentSigne = documentSigne
        self.document = document
        self.suite = suite
        self.decisionReference = decisionReference
        self.deduite = deduite
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        numero = c.texte("numero")
        guard let id = c.texte("id") ?? c.texte("offre_id") ?? numero else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "id manquant"))
        }
        self.id = id
        titre = c.texte("titre")
        client = c.texte("client", defaut: "Client")
        chantierId = c.texte("chantier_id")
        chantier = c.texte("chantier")
        montant = c.nombre("montant")
        signeeLe = c.texte("signee_le")
        recueLe = c.texte("recue_le")
        source = c.texte("source").flatMap { Source(rawValue: $0.lowercased()) } ?? .inconnue
        expediteur = c.texte("expediteur")
        documentSigne = c.texte("document_signe")
        document = c.texte("document") ?? c.texte("pdf")
        suite = c.texte("suite").flatMap(Suite.init(rawValue:)) ?? .aPlanifier
        decisionReference = c.texte("decision_reference")
        deduite = false
    }

    /// Date de classement : réception, sinon signature.
    public var date: Date? { (recueLe ?? signeeLe).flatMap(DateEndry.lire) }

    /// Repli : un chantier à l'étape « acceptée » (offre signée, sans le détail de sa réception).
    public static func deduite(de d: Dossier) -> OffreSignee {
        OffreSignee(id: "chantier-" + d.id, titre: d.titre, client: d.client, chantierId: d.id, chantier: d.titre,
                    montant: d.montant, suite: d.etape == "planifie" ? .planifiee : .aPlanifier, deduite: true)
    }
}

struct ListeOffresSignees: Decodable {
    var offres: [OffreSignee]

    init(from decoder: Decoder) throws {
        if let liste = try? [ElementTolerantPublic<OffreSignee>](from: decoder) {
            offres = liste.compactMap(\.valeur)
        } else {
            offres = try decoder.champs().liste("offres")
        }
    }
}

extension Requete {
    public static let offresSignees = Requete(.get, "\(prefixe)/offres/signees", delai: 30)
}

extension EndryAPI {
    /// Offres signées reçues (v1.5). 404 tant que le PC ne l'a pas.
    public func offresSignees() async throws(ErreurAPI) -> [OffreSignee] {
        try await charger(ListeOffresSignees.self, .offresSignees).offres
    }
}
