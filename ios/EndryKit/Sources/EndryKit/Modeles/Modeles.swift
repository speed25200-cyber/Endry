import Foundation

// MARK: - Session

/// Réponse de `POST /app/api/v1/session`.
public struct SessionOuverte: Decodable, Sendable, Equatable {
    public var jeton: String
    public var valableJours: Int?
    public var entreprise: String?
    /// v1.1 : identifiant de cet appareil (jeton par appareil).
    public var appareilId: String?

    public init(jeton: String, valableJours: Int? = nil, entreprise: String? = nil, appareilId: String? = nil) {
        self.jeton = jeton
        self.valableJours = valableJours
        self.entreprise = entreprise
        self.appareilId = appareilId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        guard let jeton = c.texte("jeton"), !jeton.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "jeton manquant"))
        }
        self.jeton = jeton
        valableJours = c.entier("valable_jours")
        entreprise = c.texte("entreprise")
        appareilId = c.texte("appareil_id")
    }
}

/// Corps d'erreur renvoyé par le serveur : `{"erreur": "...", "message": "..."}`.
public struct CorpsErreur: Decodable, Sendable, Equatable {
    public var erreur: String?
    public var message: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        erreur = c.texte("erreur")
        message = c.texte("message") ?? c.texte("detail")
    }
}

// MARK: - Décisions

public enum TypeCarte: String, Sendable, Hashable {
    case validation
    case question
    case autre
}

public struct PointAVerifier: Decodable, Sendable, Hashable {
    public var controle: String
    public var detail: String
    public var document: String?

    public init(controle: String, detail: String, document: String? = nil) {
        self.controle = controle
        self.detail = detail
        self.document = document
    }

    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            controle = s
            detail = ""
            document = nil
            return
        }
        let c = try decoder.champs()
        controle = c.texte("controle", defaut: "Point à vérifier")
        detail = c.texte("detail", defaut: "")
        document = c.texte("document")
    }
}

public struct Controle: Decodable, Sendable, Hashable {
    public var ok: Bool
    public var resume: String
    public var pointsAVerifier: [PointAVerifier]

    public init(ok: Bool, resume: String, pointsAVerifier: [PointAVerifier] = []) {
        self.ok = ok
        self.resume = resume
        self.pointsAVerifier = pointsAVerifier
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        pointsAVerifier = c.liste("points_a_verifier")
        ok = c.booleen("ok") ?? pointsAVerifier.isEmpty
        resume = c.texte("resume", defaut: ok ? "Contrôle qualité réussi" : "Points à vérifier")
    }
}

public struct Piece: Decodable, Sendable, Hashable, Identifiable {
    public var nom: String
    public var url: String

    public var id: String { url }

    public init(nom: String, url: String) {
        self.nom = nom
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        url = c.texte("url") ?? c.texte("pdf") ?? ""
        nom = c.texte("nom") ?? URL(string: url)?.lastPathComponent ?? "Document"
    }

    public var estPDF: Bool {
        nom.lowercased().hasSuffix(".pdf") || url.contains("/app/doc/") || url.lowercased().hasSuffix(".pdf")
    }
}

/// Une décision à prendre par la direction (carte de validation ou question).
public struct Carte: Decodable, Sendable, Hashable, Identifiable {
    /// Repli (serveur v1.0, sans `envoi_tiers`) : outils dont le « Oui » fait partir quelque chose chez un tiers.
    public static let outilsEnvoi: Set<String> = [
        "mail_envoyer", "mail_repondre", "mail_transferer", "envoyer_facture", "envoyer_offre", "envoyer_rappel",
    ]

    public var type: TypeCarte
    public var reference: String
    public var genre: String
    public var titre: String
    public var motif: String
    public var cree: String?
    public var controle: Controle?
    public var texte: String?
    public var destinataires: [String]
    public var objet: String?
    public var pieces: [Piece]
    public var outil: String?
    public var modifiable: Bool
    /// v1.1 : vrai si « Oui » envoie quelque chose à un tiers (fait foi s'il est présent).
    public var envoiTiers: Bool?
    /// v1.1 : chantier concerné (regroupement des notifications, lien vers le dossier).
    public var chantierId: String?
    /// Noms des documents joints (v1.0).
    public var documents: [String]

    public var id: String { reference }

    public init(
        type: TypeCarte, reference: String, genre: String, titre: String, motif: String,
        cree: String? = nil, controle: Controle? = nil, texte: String? = nil, destinataires: [String] = [],
        objet: String? = nil, pieces: [Piece] = [], outil: String? = nil, modifiable: Bool = true,
        envoiTiers: Bool? = nil, chantierId: String? = nil, documents: [String] = []
    ) {
        self.type = type
        self.reference = reference
        self.genre = genre
        self.titre = titre
        self.motif = motif
        self.cree = cree
        self.controle = controle
        self.texte = texte
        self.destinataires = destinataires
        self.objet = objet
        self.pieces = pieces
        self.outil = outil
        self.modifiable = modifiable
        self.envoiTiers = envoiTiers
        self.chantierId = chantierId
        self.documents = documents
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        guard let reference = c.texte("reference"), !reference.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "référence manquante"))
        }
        self.reference = reference
        let typeBrut = c.texte("type")?.lowercased()
        if let typeBrut, let t = TypeCarte(rawValue: typeBrut) {
            type = t
        } else {
            type = reference.uppercased().hasPrefix("Q-") ? .question : (typeBrut == nil ? .validation : .autre)
        }
        genre = c.texte("genre") ?? (type == .question ? "Question" : "Décision")
        titre = c.texte("titre", defaut: "Sans titre")
        motif = c.texte("motif", defaut: "")
        cree = c.texte("cree")
        controle = c.objet("controle")
        texte = c.texte("texte")
        destinataires = c.textes("destinataires")
        objet = c.texte("objet")
        pieces = c.liste("pieces")
        outil = c.texte("outil")
        modifiable = c.booleen("modifiable") ?? true
        envoiTiers = c.booleen("envoi_tiers")
        chantierId = c.texte("chantier_id")
        documents = c.textes("documents")
    }

    /// Les références `Q-…` et les cartes de type question se répondent par texte ou voix.
    public var estQuestion: Bool {
        type == .question || reference.uppercased().hasPrefix("Q-")
    }

    /// Vrai si « Oui » envoie un e-mail ou un document à un tiers : geste « Glisser pour envoyer » obligatoire.
    /// `envoi_tiers` (v1.1) fait foi ; à défaut, liste d'outils connus.
    public var exigeGlisser: Bool {
        if let envoiTiers { return envoiTiers }
        guard let outil else { return false }
        return Self.outilsEnvoi.contains(outil)
    }

    public var dateCreation: Date? { cree.flatMap(DateEndry.lire) }
}

public enum ActionDecision: String, Sendable, CaseIterable {
    case oui
    case non
    case corriger
    /// Réponse écrite à une question (`Q-…`), avec `consignes`.
    case repondre
}

/// Réponse de `GET /app/api/v1/decisions`.
public struct ReponseDecisions: Decodable, Sendable, Equatable {
    public var decisions: [Carte]
    public var decisionsAutorisees: Bool

    public init(decisions: [Carte], decisionsAutorisees: Bool = true) {
        self.decisions = decisions
        self.decisionsAutorisees = decisionsAutorisees
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        decisions = c.liste("decisions")
        decisionsAutorisees = c.booleen("decisions_autorisees") ?? true
    }
}

/// Réponse d'une action Oui / Non / Corriger.
public struct ReponseAction: Decodable, Sendable, Equatable {
    public var ok: Bool
    public var message: String
    public var decisionsRestantes: Int?

    public init(ok: Bool, message: String, decisionsRestantes: Int? = nil) {
        self.ok = ok
        self.message = message
        self.decisionsRestantes = decisionsRestantes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        ok = c.booleen("ok") ?? false
        message = c.texte("message", defaut: ok ? "C'est fait." : "Action refusée.")
        decisionsRestantes = c.entier("decisions_restantes")
    }
}

/// Réponse simple `{"ok", "message"}` ou `{"ok", "resultat"}`.
public struct ReponseSimple: Decodable, Sendable, Equatable {
    public var ok: Bool
    public var message: String?

    public init(ok: Bool, message: String? = nil) {
        self.ok = ok
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        ok = c.booleen("ok") ?? false
        message = c.texte("message") ?? c.texte("resultat")
    }
}

// MARK: - Argent

public struct Anciennete: Decodable, Sendable, Hashable {
    public var aEchoir: Double
    public var jours0a30: Double
    public var jours31a60: Double
    public var plus60: Double

    public init(aEchoir: Double = 0, jours0a30: Double = 0, jours31a60: Double = 0, plus60: Double = 0) {
        self.aEchoir = aEchoir
        self.jours0a30 = jours0a30
        self.jours31a60 = jours31a60
        self.plus60 = plus60
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        aEchoir = c.nombre("a_echoir") ?? 0
        jours0a30 = c.nombre("0_30") ?? 0
        jours31a60 = c.nombre("31_60") ?? 0
        plus60 = c.nombre("plus_60") ?? 0
    }

    public var total: Double { aEchoir + jours0a30 + jours31a60 + plus60 }
    /// Tout ce qui a plus de 30 jours de retard.
    public var plus30: Double { jours31a60 + plus60 }
}

public struct FactureClient: Decodable, Sendable, Hashable, Identifiable {
    public var factureId: String
    public var numero: String
    public var titre: String
    public var client: String
    public var montant: Double
    public var echeance: String?
    public var retardJours: Int

    public var id: String { factureId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        numero = c.texte("numero", defaut: "")
        factureId = c.texte("facture_id") ?? c.texte("id") ?? numero
        titre = c.texte("titre", defaut: "")
        client = c.texte("client", defaut: "Client")
        montant = c.nombre("montant") ?? 0
        echeance = c.texte("echeance")
        retardJours = c.entier("retard_jours") ?? 0
    }

    public var cheminPDF: String { "/app/doc/facture/\(factureId)" }
}

public struct Encaisser: Decodable, Sendable, Hashable {
    public var factures: [FactureClient]
    public var total: Double
    public var anciennete: Anciennete

    public init(factures: [FactureClient] = [], total: Double = 0, anciennete: Anciennete = .init()) {
        self.factures = factures
        self.total = total
        self.anciennete = anciennete
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        factures = c.liste("factures")
        total = c.nombre("total") ?? factures.reduce(0) { $0 + $1.montant }
        anciennete = c.objet("anciennete") ?? Anciennete()
    }

    /// Montants regroupés par client, du plus gros au plus petit.
    public var parClient: [GroupeClient] {
        var groupes: [String: [FactureClient]] = [:]
        for facture in factures {
            groupes[facture.client, default: []].append(facture)
        }
        let resultat: [GroupeClient] = groupes.map { client, liste in
            GroupeClient(client: client, factures: liste.sorted { $0.retardJours > $1.retardJours })
        }
        return resultat.sorted { $0.montant > $1.montant }
    }
}

public struct GroupeClient: Sendable, Hashable, Identifiable {
    public var client: String
    public var factures: [FactureClient]

    public var id: String { client }
    public var montant: Double { factures.reduce(0) { $0 + $1.montant } }
    public var retardMax: Int { factures.map(\.retardJours).max() ?? 0 }
}

public struct FactureFournisseur: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var fournisseur: String
    public var numero: String
    public var montant: Double
    public var echeance: String?
    public var objet: String?
    public var statut: String?
    public var joursRestants: Int?
    /// Téléphone du fournisseur, si le PC le fournit (facultatif, toute version).
    public var telephone: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        numero = c.texte("numero", defaut: "")
        fournisseur = c.texte("fournisseur", defaut: "Fournisseur")
        telephone = c.texte("telephone") ?? c.texte("fournisseur_telephone")
        id = c.texte("id") ?? "\(fournisseur)-\(numero)"
        montant = c.nombre("montant") ?? 0
        echeance = c.texte("echeance")
        objet = c.texte("objet")
        statut = c.texte("statut")
        joursRestants = c.entier("jours_restants")
    }
}

public struct Payer: Decodable, Sendable, Hashable {
    public var factures: [FactureFournisseur]
    public var total: Double
    public var cetteSemaine: [FactureFournisseur]
    public var totalSemaine: Double

    public init(factures: [FactureFournisseur] = [], total: Double = 0, cetteSemaine: [FactureFournisseur] = [], totalSemaine: Double = 0) {
        self.factures = factures
        self.total = total
        self.cetteSemaine = cetteSemaine
        self.totalSemaine = totalSemaine
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        factures = c.liste("factures")
        total = c.nombre("total") ?? factures.reduce(0) { $0 + $1.montant }
        cetteSemaine = c.liste("cette_semaine")
        totalSemaine = c.nombre("total_semaine") ?? cetteSemaine.reduce(0) { $0 + $1.montant }
    }
}

public struct Offre: Decodable, Sendable, Hashable, Identifiable {
    public var offreId: String
    public var numero: String
    public var titre: String
    public var client: String
    public var montant: Double
    public var emiseLe: String?
    public var valableJusquAu: String?

    public var id: String { offreId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        numero = c.texte("numero", defaut: "")
        offreId = c.texte("offre_id") ?? c.texte("id") ?? numero
        titre = c.texte("titre", defaut: "")
        client = c.texte("client", defaut: "Client")
        montant = c.nombre("montant") ?? 0
        emiseLe = c.texte("emise_le")
        valableJusquAu = c.texte("valable_jusqu_au")
    }

    public var cheminPDF: String { "/app/doc/offre/\(offreId)" }
}

public struct Offres: Decodable, Sendable, Hashable {
    public var offres: [Offre]
    public var total: Double

    public init(offres: [Offre] = [], total: Double = 0) {
        self.offres = offres
        self.total = total
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        offres = c.liste("offres")
        total = c.nombre("total") ?? offres.reduce(0) { $0 + $1.montant }
    }
}

/// Achat à refacturer. v1.0 : `{dossier_id, dossier, achat, montant, date}` ;
/// v1.1 ajoute `{id, libelle, fournisseur, chantier}`. Les deux formes sont lues.
public struct AchatARefacturer: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var fournisseur: String?
    public var libelle: String
    public var chantier: String?
    public var dossierId: String?
    public var montant: Double
    public var date: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        libelle = c.texte("libelle") ?? c.texte("achat") ?? c.texte("objet") ?? c.texte("titre") ?? "Achat"
        fournisseur = c.texte("fournisseur")
        chantier = c.texte("chantier") ?? c.texte("dossier") ?? c.texte("client")
        dossierId = c.texte("dossier_id")
        montant = c.nombre("montant") ?? 0
        date = c.texte("date")
        id = c.texte("id") ?? c.texte("ref") ?? "\(dossierId ?? "")-\(libelle)-\(date ?? "")-\(montant)"
    }
}

public struct ARefacturer: Decodable, Sendable, Hashable {
    public var achats: [AchatARefacturer]
    public var total: Double

    public init(achats: [AchatARefacturer] = [], total: Double = 0) {
        self.achats = achats
        self.total = total
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        achats = c.liste("achats")
        total = c.nombre("total") ?? achats.reduce(0) { $0 + $1.montant }
    }
}

/// Versement reçu sans facture correspondante : `{cle, date, montant, contrepartie, texte, reference}`.
public struct VersementNonIdentifie: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var date: String?
    public var montant: Double
    /// Qui a payé.
    public var contrepartie: String?
    /// Communication bancaire.
    public var texte: String?
    public var reference: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        date = c.texte("date")
        montant = c.nombre("montant") ?? 0
        contrepartie = c.texte("contrepartie") ?? c.texte("donneur")
        texte = c.texte("texte") ?? c.texte("communication") ?? c.texte("libelle")
        reference = c.texte("reference")
        id = c.texte("cle") ?? c.texte("id") ?? "\(date ?? "")-\(montant)-\(contrepartie ?? texte ?? "")"
    }

    /// Titre lisible : la contrepartie, sinon la communication.
    public var titre: String { contrepartie ?? texte ?? "Versement" }
}

public struct HeuresSecretariat: Decodable, Sendable, Hashable {
    public var heures: Double
    public var montant: Double?
    public var mois: String

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        // v1.1 : `heures_decimal` (nombre) ; v1.0 : `heures` en texte (« 31 h 30 »).
        heures = c.nombre("heures_decimal") ?? c.texte("heures").flatMap(Self.lireHeures) ?? 0
        montant = c.nombre("montant")
        mois = c.texte("mois", defaut: "")
    }

    /// « 31 h 30 », « 31h30 », « 31:30 », « 31.5 », « 31,5 h » → 31.5
    public static func lireHeures(_ texte: String) -> Double? {
        let s = texte.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "min", with: "")
        for separateur in ["h", ":"] where s.contains(separateur) {
            let morceaux = s.split(separator: Character(separateur), omittingEmptySubsequences: false)
            guard let h = Double(morceaux[0].replacingOccurrences(of: ",", with: ".")) else { return nil }
            let m = morceaux.count > 1 ? Double(morceaux[1]) ?? 0 : 0
            return h + m / 60
        }
        return Double(s.replacingOccurrences(of: ",", with: "."))
    }
}

/// Réponse de `GET /app/api/v1/argent`.
public struct Argent: Decodable, Sendable, Hashable {
    public var encaisser: Encaisser
    public var payer: Payer
    public var offres: Offres
    public var aRefacturer: ARefacturer
    public var versementsNonIdentifies: [VersementNonIdentifie]
    public var heuresSecretariat: HeuresSecretariat?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        encaisser = c.objet("encaisser") ?? Encaisser()
        payer = c.objet("payer") ?? Payer()
        offres = c.objet("offres") ?? Offres()
        aRefacturer = c.objet("a_refacturer") ?? ARefacturer()
        versementsNonIdentifies = c.liste("versements_non_identifies")
        heuresSecretariat = c.objet("heures_secretariat")
    }
}

// MARK: - Chantiers

/// Chantier de la semaine (`chantiers_7_jours`, `semaine`) : un `ChantierResume` côté serveur.
public struct Semaine: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var titre: String
    public var client: String?
    public var lieu: String?
    public var dates: String?
    public var debut: String?
    public var fin: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        titre = c.texte("titre", defaut: "Chantier")
        id = c.texte("id") ?? titre
        client = c.texte("client").flatMap(Dossier.nonVide)
        lieu = c.texte("lieu").flatMap(Dossier.nonVide)
        dates = c.texte("dates").flatMap(Dossier.nonVide)
        debut = (c.texte("debut") ?? c.texte("date_debut")).flatMap(Dossier.nonVide)
        fin = c.texte("date_fin").flatMap(Dossier.nonVide)
    }

    public var dateDebut: Date? { debut.flatMap(DateEndry.lire) }
    public var dateFin: Date? { (fin ?? debut).flatMap(DateEndry.lire) }
}

public enum TypeElement: String, Sendable, Hashable {
    case offre, facture, achat, autre
}

public struct ElementDossier: Decodable, Sendable, Hashable, Identifiable {
    public var type: TypeElement
    public var ref: String
    public var libelle: String
    public var montant: Double?
    public var date: String?
    public var statut: String?
    public var echeance: String?
    public var pdf: String?
    /// v1.1 : numéro lisible (« RE-00036 »). `ref` (« offre:37 ») est une clé interne.
    public var numero: String?

    public var id: String { "\(type.rawValue)-\(ref)" }

    /// Numéro à afficher : `numero` (v1.1), sinon `ref` s'il n'est pas une clé interne.
    public var numeroAffiche: String? {
        if let numero, !numero.isEmpty { return numero }
        return ref.isEmpty || ref.contains(":") ? nil : ref
    }

    /// Montant à afficher (jamais « CHF 0 »).
    public var montantAffiche: Double? { montant.flatMap { $0 > 0 ? $0 : nil } }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        type = c.texte("type").flatMap { TypeElement(rawValue: $0.lowercased()) } ?? .autre
        ref = c.texte("ref") ?? c.texte("numero") ?? ""
        libelle = c.texte("libelle") ?? c.texte("titre") ?? ref
        montant = c.nombre("montant")
        date = c.texte("date")
        statut = c.texte("statut")
        echeance = c.texte("echeance")
        pdf = c.texte("pdf").flatMap { $0.isEmpty ? nil : $0 }
        numero = c.texte("numero")
    }
}

/// Un dossier chantier.
public struct Dossier: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var titre: String
    public var client: String
    public var lieu: String?
    public var etape: String
    public var etapeLibelle: String
    public var etapeIndex: Int
    public var statut: String?
    public var montant: Double?
    public var note: String?
    public var dateDebut: String?
    public var dateFin: String?
    public var dates: String?
    public var decisionEnAttente: Bool
    public var referenceDecision: String?
    public var elements: [ElementDossier]
    public var facturesFournisseurs: [FactureFournisseur]
    public var misAJour: String?

    static func nonVide(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    public var debut: Date? { dateDebut.flatMap(DateEndry.lire) }
    public var fin: Date? { (dateFin ?? dateDebut).flatMap(DateEndry.lire) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        guard let id = c.texte("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "id manquant"))
        }
        self.id = id
        titre = c.texte("titre", defaut: "Chantier")
        client = c.texte("client", defaut: "")
        lieu = c.texte("lieu")
        let index = c.entier("etape_index")
        let cle = c.texte("etape")?.lowercased()
        let etapeConnue = cle.flatMap(EtapeChantier.init(rawValue:)) ?? index.flatMap(EtapeChantier.depuisIndex)
        etape = cle ?? etapeConnue?.rawValue ?? "demande"
        etapeIndex = min(max(index ?? etapeConnue?.index ?? 0, 0), EtapeChantier.allCases.count - 1)
        etapeLibelle = c.texte("etape_libelle") ?? etapeConnue?.libelle ?? etape.capitalized
        statut = c.texte("statut")
        montant = c.nombre("montant").flatMap { $0 > 0 ? $0 : nil }
        note = c.texte("note").flatMap(Self.nonVide)
        dateDebut = c.texte("date_debut").flatMap(Self.nonVide)
        dateFin = c.texte("date_fin").flatMap(Self.nonVide)
        dates = c.texte("dates").flatMap(Self.nonVide)
        misAJour = c.texte("mis_a_jour")
        if let b = c.booleen("decision_en_attente") {
            decisionEnAttente = b
            referenceDecision = nil
        } else if let ref = c.texte("decision_en_attente"), !ref.isEmpty {
            decisionEnAttente = true
            referenceDecision = ref
        } else {
            decisionEnAttente = false
            referenceDecision = nil
        }
        elements = c.liste("elements")
        facturesFournisseurs = c.liste("factures_fournisseurs")
    }

    /// Nom court pour la saisie vocale : « Chantier Rochat — Épalinges : ».
    public var prefixeSaisie: String {
        let lieuTexte = lieu.map { " — \($0)" } ?? ""
        return "Chantier \(client.isEmpty ? titre : client)\(lieuTexte) : "
    }

    public var documents: [ElementDossier] { elements.filter { $0.type == .offre || $0.type == .facture } }
    public var achats: [ElementDossier] { elements.filter { $0.type == .achat } }
}

public enum EtapeChantier: String, Sendable, CaseIterable, Identifiable {
    case demande, offre, acceptee, planifie, realise, facture, paye

    public var id: String { rawValue }

    public var libelle: String {
        switch self {
        case .demande: "Demande"
        case .offre: "Offre"
        case .acceptee: "Acceptée"
        case .planifie: "Planifié"
        case .realise: "Réalisé"
        case .facture: "Facturé"
        case .paye: "Payé"
        }
    }

    public var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static func depuisIndex(_ i: Int) -> EtapeChantier? {
        allCases.indices.contains(i) ? allCases[i] : nil
    }
}

public struct CompteurEtape: Decodable, Sendable, Hashable, Identifiable {
    public var cle: String
    public var libelle: String
    public var nombre: Int

    public var id: String { cle }

    public init(cle: String, libelle: String, nombre: Int) {
        self.cle = cle
        self.libelle = libelle
        self.nombre = nombre
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        cle = c.texte("cle", defaut: "tous")
        libelle = c.texte("libelle") ?? EtapeChantier(rawValue: cle)?.libelle ?? cle.capitalized
        nombre = c.entier("nombre") ?? 0
    }
}

/// Réponse de `GET /app/api/v1/chantiers`.
public struct ReponseChantiers: Decodable, Sendable, Hashable {
    public var etapes: [CompteurEtape]
    public var chantiers: [Dossier]
    public var semaine: [Semaine]
    public var calendrierICS: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        etapes = c.liste("etapes")
        chantiers = c.liste("chantiers")
        semaine = c.liste("semaine")
        calendrierICS = c.texte("calendrier_ics")
    }
}

// MARK: - Accueil

/// Réponse de `GET /app/api/v1/accueil`.
public struct Accueil: Decodable, Sendable, Hashable {
    public var salut: String
    public var date: String
    public var pause: Bool
    public var decisions: [Carte]
    public var encaisser: Encaisser
    public var offres: Offres
    public var payer: Payer
    public var chantiers7Jours: [Semaine]

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        salut = c.texte("salut", defaut: "Bonjour")
        date = c.texte("date", defaut: "")
        pause = c.booleen("pause") ?? false
        decisions = c.liste("decisions")
        encaisser = c.objet("encaisser") ?? Encaisser()
        offres = c.objet("offres") ?? Offres()
        payer = c.objet("payer") ?? Payer()
        chantiers7Jours = c.liste("chantiers_7_jours")
    }
}
