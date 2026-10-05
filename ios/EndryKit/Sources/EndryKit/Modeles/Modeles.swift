import Foundation

// MARK: - Session

/// Réponse de `POST /app/api/v1/session`.
public struct SessionOuverte: Decodable, Sendable, Equatable {
    public var jeton: String
    public var valableJours: Int?
    public var entreprise: String?
    /// v1.1 : identifiant de cet appareil (jeton par appareil).
    public var appareilId: String?
    /// v1.3 : `patron` (défaut) ou `ouvrier` (lien d'équipe).
    public var role: RoleAcces?
    /// v1.3 : nom de l'ouvrier.
    public var nom: String?

    public init(jeton: String, valableJours: Int? = nil, entreprise: String? = nil, appareilId: String? = nil,
                role: RoleAcces? = nil, nom: String? = nil) {
        self.jeton = jeton
        self.valableJours = valableJours
        self.entreprise = entreprise
        self.appareilId = appareilId
        self.role = role
        self.nom = nom
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
        role = c.texte("role").flatMap { RoleAcces(rawValue: $0.lowercased()) }
        nom = c.texte("nom")
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

public struct Piece: Codable, Sendable, Hashable, Identifiable {
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

    private enum Cles: String, CodingKey { case nom, url }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Cles.self)
        try c.encode(nom, forKey: .nom)
        try c.encode(url, forKey: .url)
    }

    /// Extension du fichier (« pdf », « xlsx »), d'après le nom puis l'adresse ; `pdf` pour un document du bureau.
    public var extensionFichier: String {
        let n = (nom as NSString).pathExtension.lowercased()
        if !n.isEmpty { return n }
        let u = ((URL(string: url)?.path ?? url) as NSString).pathExtension.lowercased()
        if !u.isEmpty { return u }
        return url.contains("/app/doc/") ? "pdf" : ""
    }

    /// Libellé du type (« PDF », « Excel », « Word »).
    public var libelleType: String {
        switch extensionFichier {
        case "pdf": "PDF"
        case "xlsx", "xls", "csv": "Excel"
        case "docx", "doc": "Word"
        case "png", "jpg", "jpeg", "heic": "Image"
        case "": "Document"
        default: extensionFichier.uppercased()
        }
    }

    static let extensionsDocument: Set<String> = ["pdf", "xlsx", "xls", "csv", "docx", "doc", "pptx", "png", "jpg", "jpeg", "heic", "txt", "zip"]

    /// Liens vers des documents dans une réponse en Markdown (`[Offre OF-00037.pdf](/app/doc/offre/OF-00037)`) :
    /// les documents trouvés, et le texte où chaque lien est remplacé par son seul libellé.
    public static func extraire(du texte: String) -> (texte: String, pieces: [Piece]) {
        guard texte.contains("](") else { return (texte, []) }
        var pieces: [Piece] = []
        var sortie = ""
        var reste = Substring(texte)
        while let ouvrant = reste.firstIndex(of: "[") {
            sortie += reste[..<ouvrant]
            let apres = reste[reste.index(after: ouvrant)...]
            guard let fermant = apres.firstIndex(of: "]"),
                  apres[fermant...].hasPrefix("]("),
                  let finLien = apres[apres.index(fermant, offsetBy: 2)...].firstIndex(of: ")") else {
                sortie += "["
                reste = apres
                continue
            }
            let libelle = String(apres[..<fermant])
            let adresse = String(apres[apres.index(fermant, offsetBy: 2)..<finLien]).trimmingCharacters(in: .whitespaces)
            let piece = Piece(nom: libelle.isEmpty ? (URL(string: adresse)?.lastPathComponent ?? "Document") : libelle, url: adresse)
            let estDocument = adresse.contains("/app/doc/") || adresse.contains("/documents/")
                || extensionsDocument.contains(piece.extensionFichier) && !adresse.lowercased().hasPrefix("mailto:")
            if estDocument {
                if !pieces.contains(where: { $0.url == adresse }) { pieces.append(piece) }
                sortie += libelle
            } else {
                sortie += reste[ouvrant...finLien]
            }
            reste = apres[apres.index(after: finLien)...]
        }
        sortie += reste
        return (sortie, pieces)
    }
}

/// Une décision à prendre par la direction (carte de validation ou question).
public struct Carte: Decodable, Sendable, Hashable, Identifiable {
    /// Repli (serveur v1.0, sans `envoi_tiers`) : outils dont le « Oui » fait partir quelque chose chez un tiers.
    public static let outilsEnvoi: Set<String> = [
        "mail_envoyer", "mail_repondre", "mail_transferer", "envoyer_facture", "envoyer_offre", "envoyer_rappel",
        "rappel_courrier", "relances_reactiver",
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
    /// Geste exigé pour « Oui » (`"glisser"`, v4) ; absent : la règle s'applique quand même.
    public var gesteRequis: String?
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
        gesteRequis = c.texte("geste_requis")
        chantierId = c.texte("chantier_id")
        documents = c.textes("documents")
    }

    /// Les références `Q-…` et les cartes de type question se répondent par texte ou voix.
    public var estQuestion: Bool {
        type == .question || reference.uppercased().hasPrefix("Q-")
    }

    /// Règle de la direction (28.09.2026) : **tout « Oui » se fait en glissant**, envoi à un tiers ou non.
    /// Seules les questions (`Q-…`) se répondent autrement (par écrit ou dicté).
    public var exigeGlisser: Bool { !estQuestion }

    /// « Glisser pour envoyer » quand quelque chose part chez un tiers, « Glisser pour valider » sinon.
    public var libelleGlisser: String { partChezUnTiers ? "Glisser pour envoyer" : "Glisser pour valider" }

    /// Vrai si « Oui » envoie un e-mail ou un document à un tiers.
    /// `envoi_tiers` (v1.1) fait foi ; à défaut, liste d'outils connus.
    public var partChezUnTiers: Bool {
        if let envoiTiers { return envoiTiers }
        guard let outil else { return false }
        return Self.outilsEnvoi.contains(outil)
    }

    public var dateCreation: Date? { cree.flatMap(DateEndry.lire) }
}

/// Le geste qui autorise un « Oui » : il n'y en a qu'un, le glissement à l'écran.
/// Ni la voix, ni Siri, ni une notification, ni un bouton ne peuvent en produire un.
public enum GesteValidation: Sendable, Equatable {
    case glissement
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
    /// `POST /saisie` : identifiant de la saisie créée, pour suivre son traitement.
    public var saisieId: String?

    public init(ok: Bool, message: String? = nil, saisieId: String? = nil) {
        self.ok = ok
        self.message = message
        self.saisieId = saisieId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        ok = c.booleen("ok") ?? false
        message = c.texte("message") ?? c.texte("resultat")
        saisieId = c.texte("saisie_id") ?? c.texte("id")
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
    /// v1.3 : dernier suivi préparé (`AAAA-MM-JJ`), pour ne pas proposer deux fois le même suivi.
    public var dernierSuivi: String?

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
        dernierSuivi = c.texte("dernier_suivi")
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
    /// v1.6 : mois au format `AAAA-MM` (pour demander le détail d'un autre mois).
    public var periode: String?
    /// v1.6 : détail des heures (date, tâche, durée, client).
    public var lignes: [LigneHeuresSecretariat]
    /// v1.6 : documents du bureau (relevé PDF, tableau Excel).
    public var documents: [DocumentHeures]
    /// v1.6 : tarif horaire HT appliqué.
    public var tarif: Double?
    /// v1.6 : autres mois disponibles (`AAAA-MM`), le plus récent d'abord.
    public var moisDisponibles: [String]

    public init(heures: Double, montant: Double? = nil, mois: String, periode: String? = nil, lignes: [LigneHeuresSecretariat] = [],
                documents: [DocumentHeures] = [], tarif: Double? = nil, moisDisponibles: [String] = []) {
        self.heures = heures
        self.montant = montant
        self.mois = mois
        self.periode = periode
        self.lignes = lignes
        self.documents = documents
        self.tarif = tarif
        self.moisDisponibles = moisDisponibles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        // v1.1 : `heures_decimal` (nombre) ; v1.0 : `heures` en texte (« 31 h 30 »).
        lignes = c.liste("lignes")
        heures = c.nombre("heures_decimal") ?? c.texte("heures").flatMap(Self.lireHeures) ?? lignes.reduce(0) { $0 + $1.heures }
        montant = c.nombre("montant")
        mois = c.texte("mois", defaut: "")
        periode = c.texte("periode")
        documents = c.liste("documents")
        tarif = c.nombre("tarif")
        moisDisponibles = c.textes("mois_disponibles")
    }

    /// Heures par catégorie de travail, la plus lourde d'abord.
    public var parCategorie: [(categorie: String, heures: Double)] {
        var ordre: [String] = []
        var total: [String: Double] = [:]
        for l in lignes {
            let cle = l.categorie ?? "Autres"
            if total[cle] == nil { ordre.append(cle) }
            total[cle, default: 0] += l.heures
        }
        return ordre.map { ($0, total[$0] ?? 0) }.sorted { $0.1 > $1.1 }
    }

    /// Un jour du relevé : ses lignes et son total.
    public struct Jour: Sendable, Hashable, Identifiable {
        public var date: String
        public var heures: Double
        public var lignes: [LigneHeuresSecretariat]
        public var id: String { date }
    }

    /// Lignes regroupées par jour (le plus récent d'abord), filtrées par travail et par texte cherché
    /// (tâche, client ou travail ; sans tenir compte des accents ni des majuscules).
    public func parJour(categorie: String? = nil, recherche: String = "") -> [Jour] {
        let cherche = recherche.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CH"))
        let retenues = lignes.filter { l in
            if let categorie, (l.categorie ?? "Autres") != categorie { return false }
            guard !cherche.isEmpty else { return true }
            return [l.libelle, l.client ?? "", l.categorie ?? ""].joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CH"))
                .contains(cherche)
        }
        var ordre: [String] = []
        var groupes: [String: [LigneHeuresSecretariat]] = [:]
        for l in retenues {
            if groupes[l.date] == nil { ordre.append(l.date) }
            groupes[l.date, default: []].append(l)
        }
        return ordre.sorted(by: >).map { d in
            let ls = groupes[d] ?? []
            return Jour(date: d, heures: ls.reduce(0) { $0 + $1.heures }, lignes: ls)
        }
    }

    /// Demande au Secrétariat (Claude, sur le PC) le relevé soigné du mois : c'est le bureau qui le produit.
    public var demandeReleve: String {
        "[Pour l’agent Secrétariat] Prépare le relevé des heures de secrétariat de \(mois) pour Endry SA : "
            + "1) un PDF mis en page (en-tête Endry SA, période, tableau jour par jour avec tâche, client, travail et durée, "
            + "sous-totaux par travail, total des heures, tarif et montant HT) ; "
            + "2) un tableau Excel (.xlsx) avec les mêmes colonnes, un onglet par travail et les totaux en formules. "
            + "Range-les avec les documents des heures du mois pour qu’ils apparaissent dans l’app. Rien n’est envoyé à personne."
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

/// Une ligne du relevé d'heures du secrétariat (v1.6).
public struct LigneHeuresSecretariat: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    /// `AAAA-MM-JJ`
    public var date: String
    public var libelle: String
    public var heures: Double
    public var client: String?
    public var categorie: String?

    public init(id: String = UUID().uuidString, date: String, libelle: String, heures: Double, client: String? = nil, categorie: String? = nil) {
        self.id = id
        self.date = date
        self.libelle = libelle
        self.heures = heures
        self.client = client
        self.categorie = categorie
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        date = c.texte("date", defaut: "")
        libelle = c.texte("libelle") ?? c.texte("tache") ?? ""
        guard !libelle.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "libellé manquant"))
        }
        heures = c.nombre("heures_decimal") ?? c.nombre("heures") ?? c.texte("heures").flatMap(HeuresSecretariat.lireHeures) ?? 0
        client = c.texte("client")
        categorie = c.texte("categorie")
        id = c.texte("id") ?? "\(date)-\(libelle)-\(heures)"
    }
}

/// Document du bureau : relevé PDF, tableau Excel.
public struct DocumentHeures: Decodable, Sendable, Hashable, Identifiable {
    public var nom: String
    /// `pdf`, `xlsx`, `csv`…
    public var format: String
    /// Chemin `/app/doc/…`
    public var chemin: String

    public var id: String { chemin }

    public init(nom: String, format: String, chemin: String) {
        self.nom = nom
        self.format = format
        self.chemin = chemin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        guard let chemin = c.texte("chemin") ?? c.texte("url") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "chemin manquant"))
        }
        self.chemin = chemin
        nom = c.texte("nom", defaut: (chemin as NSString).lastPathComponent)
        format = (c.texte("format") ?? (nom as NSString).pathExtension).lowercased()
    }
}

extension Requete {
    /// v1.6 : détail des heures du secrétariat d'un mois (`AAAA-MM`), le mois en cours sans paramètre.
    public static func heuresSecretariat(mois: String? = nil) -> Requete {
        .init(.get, "\(prefixe)/heures/secretariat", parametres: mois.map { [Parametre("mois", $0)] } ?? [], delai: 30)
    }
}

extension EndryAPI {
    public func heuresSecretariat(mois: String? = nil) async throws(ErreurAPI) -> HeuresSecretariat {
        try await charger(HeuresSecretariat.self, .heuresSecretariat(mois: mois))
    }
}

/// v1.10 : une étape de facturation d'un chantier (acompte ou facture finale) et son état.
public struct TrancheFacturation: Decodable, Sendable, Hashable, Identifiable {
    public enum Etat: String, Sendable {
        case payee = "payée"
        case facturee = "facturée"
        case aFacturer = "à facturer"
    }

    public var libelle: String
    public var montant: Double
    public var etat: Etat
    /// Numéro de la facture émise pour cette tranche (`RE-00039`), s'il y en a une.
    public var facture: String?

    public var id: String { libelle + "-" + (facture ?? "") }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        libelle = c.texte("libelle", defaut: "Facture")
        montant = c.nombre("montant") ?? 0
        etat = c.texte("etat").flatMap(Etat.init(rawValue:)) ?? .aFacturer
        facture = c.texte("facture")
    }
}

/// v1.10 : chantier dont le devis est accepté et pas encore entièrement facturé (un acompte ne solde pas un chantier).
public struct TravailAFacturer: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var client: String
    public var chantier: String
    /// Total des devis acceptés.
    public var devis: Double
    /// Déjà facturé (acomptes compris).
    public var facture: Double
    public var reste: Double
    /// Acomptes puis facture finale, dans l'ordre ; vide si le PC ne les envoie pas.
    public var tranches: [TrancheFacturation]

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        tranches = c.liste("tranches")
        client = c.texte("client", defaut: "")
        chantier = c.texte("chantier", defaut: "")
        devis = c.nombre("devis") ?? 0
        facture = c.nombre("facture") ?? 0
        reste = c.nombre("reste") ?? max(0, devis - facture)
        id = c.texte("dossier_id") ?? "\(client)-\(chantier)-\(devis)"
    }

    /// Titre lisible : le client, sinon le chantier.
    public var titre: String { client.isEmpty ? chantier : client }
}

/// v1.10 : compte du plan comptable qui porte des factures fournisseurs.
public struct CompteUtilise: Decodable, Sendable, Hashable, Identifiable {
    public var numero: String
    public var libelle: String
    public var factures: Int
    public var total: Double
    public var ouvert: Double

    public var id: String { numero }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        guard let numero = c.texte("numero") ?? c.texte("compte") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "numéro de compte manquant"))
        }
        self.numero = numero
        libelle = c.texte("libelle", defaut: "")
        factures = c.entier("factures") ?? 0
        total = c.nombre("total_chf") ?? c.nombre("total") ?? 0
        ouvert = c.nombre("ouvert_chf") ?? c.nombre("ouvert") ?? 0
    }
}

/// v1.10 : la comptabilité tenue par le bureau (`argent.comptabilite`) : ce qu'on nous doit en deux parts
/// (factures ouvertes, travaux acceptés restant à facturer), ce que nous devons, les comptes utilisés, les documents.
public struct Comptabilite: Decodable, Sendable, Hashable {
    public var aPayer: Double
    public var aPayerEnRetard: Double
    public var aEncaisser: Double
    public var aFacturer: Double
    public var nousDoit: Double
    public var travaux: [TravailAFacturer]
    public var comptes: [CompteUtilise]
    /// Plan comptable et suivi (PDF), classeur de comptabilité (Excel).
    public var documents: [DocumentHeures]
    public var etatAu: String?
    public var facturesOuvertes: Int?
    public var facturesAPayer: Int?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        facturesOuvertes = c.entier("factures_ouvertes")
        facturesAPayer = c.entier("factures_a_payer")
        travaux = c.liste("a_facturer")
        comptes = c.liste("comptes")
        documents = c.liste("documents")
        aPayer = c.nombre("a_payer_chf") ?? 0
        aPayerEnRetard = c.nombre("a_payer_en_retard_chf") ?? 0
        aEncaisser = c.nombre("a_encaisser_chf") ?? 0
        aFacturer = c.nombre("a_facturer_chf") ?? travaux.reduce(0) { $0 + $1.reste }
        nousDoit = c.nombre("nous_doit_chf") ?? (aEncaisser + aFacturer)
        etatAu = c.texte("etat_au")
    }

    /// Ce qu'on nous doit, moins ce que nous devons.
    public var solde: Double { nousDoit - aPayer }
}

/// Réponse de `GET /app/api/v1/argent`.
public struct Argent: Decodable, Sendable, Hashable {
    public var encaisser: Encaisser
    public var payer: Payer
    public var offres: Offres
    public var aRefacturer: ARefacturer
    public var versementsNonIdentifies: [VersementNonIdentifie]
    public var heuresSecretariat: HeuresSecretariat?
    /// v1.10 : absent tant que le PC ne l'envoie pas.
    public var comptabilite: Comptabilite?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        comptabilite = c.objet("comptabilite")
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
    /// Étape du chantier (`planifie`…), fournie par le PC.
    public var etape: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        etape = c.texte("etape").flatMap(Dossier.nonVide)
        titre = c.texte("titre", defaut: "Chantier")
        id = c.texte("id") ?? titre
        client = c.texte("client").flatMap(Dossier.nonVide)
        lieu = c.texte("lieu").flatMap(Dossier.nonVide)
        dates = c.texte("dates").flatMap(Dossier.nonVide)
        debut = (c.texte("debut") ?? c.texte("date_debut")).flatMap(Dossier.nonVide)
        fin = (c.texte("fin") ?? c.texte("date_fin")).flatMap(Dossier.nonVide)
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
    /// v1.1 : numéro lisible (« RE-00990 »). `ref` (« offre:37 ») est une clé interne.
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
