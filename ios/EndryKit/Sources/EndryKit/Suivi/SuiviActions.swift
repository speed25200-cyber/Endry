import Foundation

// MARK: - Suivi de ce que le patron a décidé ou transmis (v1.4)
//
// Chaque geste (Oui, Non, Corriger, Répondre, saisie, envoi terrain) devient une ligne suivie : ce que vous avez fait,
// ce que le bureau a fait ensuite (étapes de l'assistant), le résultat (fichiers produits, envois à des tiers) ou
// l'erreur. Sources, de la plus sûre à la plus fragile :
// 1. `GET /suivi` (contrat v1.4, à appliquer par le PC) : compte rendu structuré, fait foi ;
// 2. `GET /journal` (v1.2, en production) : entrées rapprochées par `decision_reference`, `saisie_id`, ou le numéro
//    de document cité (« AN-00024 ») après le geste ;
// 3. `GET /saisies` (v1.1) : statut et résumé des saisies, questions et envois terrain.

public enum EtatSuivi: String, Codable, Sendable, Hashable, CaseIterable {
    /// Le geste est parti ; le bureau n'a encore rien consigné.
    case transmis
    /// Le bureau a pris la main (assistant au travail).
    case enCours = "en_cours"
    case fait
    case erreur
    /// « Non » : rien n'est fait, rien n'est envoyé.
    case ecarte
    /// « Corriger » : une nouvelle version sera proposée.
    case corrige

    public var libelle: String {
        switch self {
        case .transmis: "Transmis"
        case .enCours: "En cours"
        case .fait: "Fait"
        case .erreur: "Erreur"
        case .ecarte: "Écarté"
        case .corrige: "À corriger"
        }
    }

    /// Plus rien ne bougera sans nouveau geste.
    public var termine: Bool { [.fait, .erreur, .ecarte].contains(self) }

    init?(pc: String) {
        switch pc.lowercased() {
        case "transmis", "en_attente", "recu", "reçu", "valide", "validee", "validée": self = .transmis
        case "en_cours", "encours", "execution", "en_execution": self = .enCours
        case "fait", "termine", "terminé", "traite", "traité", "ok", "succes", "succès": self = .fait
        case "erreur", "echec", "échec": self = .erreur
        case "ecarte", "écarté", "refuse", "refusé", "non", "annule", "annulé": self = .ecarte
        case "corrige", "corriger", "a_corriger": self = .corrige
        default: return nil
        }
    }
}

public enum NatureSuivi: String, Codable, Sendable, Hashable {
    case decision, saisie, question, terrain
}

/// D'où vient ce que l'app affiche : le compte rendu du PC fait foi, le journal est rapproché.
public enum SourceSuivi: String, Codable, Sendable, Hashable {
    case geste, journal, saisies, pc
}

public struct EtapeSuivi: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var le: Date?
    /// `vous`, `bureau` ou l'identifiant d'un domaine de l'assistant (`achats`…).
    public var qui: String
    /// `geste`, `reponse`, ou un type du journal (`action`, `erreur`…).
    public var type: String
    public var titre: String
    public var detail: String?

    public init(id: String, le: Date?, qui: String, type: String, titre: String, detail: String? = nil) {
        self.id = id
        self.le = le
        self.qui = qui
        self.type = type
        self.titre = titre
        self.detail = detail
    }

    public var estErreur: Bool { type == TypeEntree.erreur.rawValue || type == "erreur" }
}

/// Fichier produit par le bureau (« Bureau › 00 À traiter › Commandes › Commande AN-00024.txt »).
public struct FichierProduit: Codable, Sendable, Hashable, Identifiable {
    public var nom: String
    /// Dossier lisible sur le PC.
    public var emplacement: String?
    /// Chemin `/app/doc/…` pour l'ouvrir dans l'app (v1.4), s'il existe.
    public var document: String?

    public var id: String { (emplacement ?? "") + "/" + nom }

    public init(nom: String, emplacement: String? = nil, document: String? = nil) {
        self.nom = nom
        self.emplacement = emplacement
        self.document = document
    }
}

/// Quelque chose est parti chez un tiers (e-mail, courrier, Bexio).
public struct EnvoiEffectue: Codable, Sendable, Hashable, Identifiable {
    public var destinataire: String
    public var objet: String?
    public var canal: String?
    public var le: Date?

    public var id: String { destinataire + "|" + (objet ?? "") + "|" + (le.map { DateEndry.horodatage($0) } ?? "") }

    public init(destinataire: String, objet: String? = nil, canal: String? = nil, le: Date? = nil) {
        self.destinataire = destinataire
        self.objet = objet
        self.canal = canal
        self.le = le
    }
}

public struct ActionSuivie: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var nature: NatureSuivi
    /// Référence de la décision (`V-…`, `Q-…`).
    public var reference: String?
    public var saisieId: String?
    public var titre: String
    public var genre: String?
    public var outil: String?
    /// `oui`, `non`, `corriger`, `repondre`, `transmis`.
    public var geste: String
    public var le: Date
    public var chantierId: String?
    public var agent: String?
    /// La décision prévoyait un envoi à un tiers.
    public var envoiTiersPrevu: Bool
    public var destinatairesPrevus: [String]
    public var consignes: String?
    /// Réponse immédiate du PC au geste (« Validé. L'assistant s'en occupe. »).
    public var reponse: String?
    public var etat: EtatSuivi
    public var source: SourceSuivi
    public var etapes: [EtapeSuivi]
    public var resume: String?
    public var fichiers: [FichierProduit]
    public var envois: [EnvoiEffectue]
    /// Décision préparée à la suite (saisie traitée, correction).
    public var decisionPreparee: String?
    public var majLe: Date

    public init(id: String, nature: NatureSuivi, reference: String? = nil, saisieId: String? = nil, titre: String,
                genre: String? = nil, outil: String? = nil, geste: String, le: Date, chantierId: String? = nil,
                agent: String? = nil, envoiTiersPrevu: Bool = false, destinatairesPrevus: [String] = [],
                consignes: String? = nil, reponse: String? = nil, etat: EtatSuivi = .transmis, source: SourceSuivi = .geste,
                etapes: [EtapeSuivi] = [], resume: String? = nil, fichiers: [FichierProduit] = [],
                envois: [EnvoiEffectue] = [], decisionPreparee: String? = nil) {
        self.id = id
        self.nature = nature
        self.reference = reference
        self.saisieId = saisieId
        self.titre = titre
        self.genre = genre
        self.outil = outil
        self.geste = geste
        self.le = le
        self.chantierId = chantierId
        self.agent = agent
        self.envoiTiersPrevu = envoiTiersPrevu
        self.destinatairesPrevus = destinatairesPrevus
        self.consignes = consignes
        self.reponse = reponse
        self.etat = etat
        self.source = source
        self.etapes = etapes
        self.resume = resume
        self.fichiers = fichiers
        self.envois = envois
        self.decisionPreparee = decisionPreparee
        self.majLe = le
    }

    /// « Oui · 09:12 », « Transmis · 14:03 ».
    public var libelleGeste: String {
        let g = switch geste {
        case "oui": "Validé"
        case "non": "Écarté"
        case "corriger": "Corrigé"
        case "repondre": "Répondu"
        default: nature == .question ? "Demandé" : "Transmis"
        }
        return "\(g) · \(DateEndry.heure(le))"
    }

    /// Ligne de résultat pour la liste.
    public var ligneResultat: String {
        switch etat {
        case .ecarte: return "Rien n’a été fait, rien n’est parti."
        case .corrige: return decisionPreparee.map { "Nouvelle version prête (\($0))." } ?? "Vos consignes sont chez l’assistant : une nouvelle version sera proposée."
        case .erreur:
            return etapes.last(where: \.estErreur).map { $0.detail ?? $0.titre } ?? resume ?? "Le bureau signale une erreur."
        case .fait, .enCours, .transmis:
            if let resume, !resume.isEmpty { return resume }
            if let f = fichiers.first { return "Fichier : \(f.nom)" }
            if let e = etapes.last(where: { $0.qui != "vous" && $0.type != "reponse" }) { return e.titre }
            if etat == .transmis { return reponse ?? "En attente du compte rendu du bureau." }
            return reponse ?? ""
        }
    }
}

// MARK: - Compte rendu du PC (v1.4, `GET /suivi`)

public struct SuiviPC: Decodable, Sendable, Hashable {
    public var reference: String?
    public var saisieId: String?
    public var titre: String?
    public var genre: String?
    public var outil: String?
    public var chantierId: String?
    public var geste: String?
    public var gesteLe: String?
    public var etat: EtatSuivi?
    public var agent: String?
    public var etapes: [EntreeJournal]
    public var resume: String?
    public var fichiers: [FichierProduit]
    public var envois: [EnvoiEffectue]
    public var erreur: String?
    public var decisionPreparee: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        reference = c.texte("reference") ?? c.texte("decision_reference")
        saisieId = c.texte("saisie_id")
        guard reference != nil || saisieId != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "référence manquante"))
        }
        titre = c.texte("titre")
        genre = c.texte("genre")
        outil = c.texte("outil")
        chantierId = c.texte("chantier_id")
        geste = c.texte("geste")
        gesteLe = c.texte("geste_le") ?? c.texte("valide_le")
        etat = c.texte("etat").flatMap(EtatSuivi.init(pc:))
        agent = c.texte("agent")
        etapes = c.liste("etapes")
        erreur = c.texte("erreur")
        decisionPreparee = c.texte("decision_preparee")
        let resultat: ResultatPC? = c.objet("resultat")
        resume = resultat?.resume ?? c.texte("resume")
        fichiers = resultat?.fichiers ?? []
        envois = resultat?.envois ?? []
    }

    struct ResultatPC: Decodable {
        var resume: String?
        var fichiers: [FichierProduit]
        var envois: [EnvoiEffectue]

        init(from decoder: Decoder) throws {
            let c = try decoder.champs()
            resume = c.texte("resume")
            fichiers = c.liste("fichiers", FichierPC.self).map(\.fichier)
            envois = c.liste("envois", EnvoiPC.self).map(\.envoi)
        }
    }

    struct FichierPC: Decodable {
        var fichier: FichierProduit
        init(from decoder: Decoder) throws {
            let c = try decoder.champs()
            let nom = c.texte("nom", defaut: "")
            guard !nom.isEmpty else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "nom manquant"))
            }
            fichier = FichierProduit(nom: nom, emplacement: c.texte("emplacement"), document: c.texte("document"))
        }
    }

    struct EnvoiPC: Decodable {
        var envoi: EnvoiEffectue
        init(from decoder: Decoder) throws {
            let c = try decoder.champs()
            let dest = c.texte("destinataire", defaut: "")
            guard !dest.isEmpty else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "destinataire manquant"))
            }
            envoi = EnvoiEffectue(destinataire: dest, objet: c.texte("objet"), canal: c.texte("canal"),
                                  le: c.texte("horodatage").flatMap(DateEndry.lire))
        }
    }
}

struct ListeSuiviPC: Decodable {
    var suivis: [SuiviPC]

    init(from decoder: Decoder) throws {
        if let liste = try? [ElementTolerantPublic<SuiviPC>](from: decoder) {
            suivis = liste.compactMap(\.valeur)
        } else {
            suivis = try decoder.champs().liste("suivis")
        }
    }
}

extension Requete {
    public static func suivi(limite: Int = 50) -> Requete {
        .init(.get, "\(prefixe)/suivi", parametres: [Parametre("limite", String(limite))], delai: 20)
    }
}

extension EndryAPI {
    /// Compte rendu des gestes récents (v1.4). 404 tant que le PC ne l'a pas.
    public func suivis(limite: Int = 50) async throws(ErreurAPI) -> [SuiviPC] {
        try await charger(ListeSuiviPC.self, .suivi(limite: limite)).suivis
    }
}

// MARK: - Rapprochement

public enum RapprochementSuivi {
    /// Numéros de documents cités dans un titre : « AN-00024 », « RE-00036 », « RG-20260928-1432 ».
    public static func reperes(_ texte: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"\b[A-Z]{1,4}-[0-9]{3,}(?:-[0-9]+)?\b"#) else { return [] }
        let ns = texte as NSString
        return re.matches(in: texte, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// Entrées du journal qui concernent cette action.
    public static func entrees(pour action: ActionSuivie, dans journal: [EntreeJournal]) -> [EntreeJournal] {
        let reperes = Set(reperes(action.titre) + [action.reference].compactMap { $0 })
        return journal.filter { e in
            if let ref = action.reference, e.decisionReference == ref { return true }
            if let s = action.saisieId, e.saisieId == s { return true }
            // Numéro de document cité, seulement après le geste (sinon : l'historique d'un autre dossier).
            guard !reperes.isEmpty, let d = e.date, d >= action.le.addingTimeInterval(-60) else { return false }
            let texte = e.titre + " " + (e.detail ?? "")
            return reperes.contains { texte.contains($0) }
        }
    }

    /// Fichiers cités : « Bureau › 00 À traiter › Commandes › « Commande AN-00024 Villa Morel.txt » ».
    public static func fichiers(dans texte: String) -> [FichierProduit] {
        guard let re = try? NSRegularExpression(pattern: #"((?:[^\n›«»:.;]+ › )+)?[«"“]\s*([^»"”\n]+?\.[A-Za-z0-9]{2,5})\s*[»"”]"#) else { return [] }
        let ns = texte as NSString
        return re.matches(in: texte, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let nom = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            var emplacement: String?
            if m.range(at: 1).location != NSNotFound {
                emplacement = ns.substring(with: m.range(at: 1))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ›"))
                    .components(separatedBy: " › ").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.joined(separator: " › ")
                let dernier = emplacement?.components(separatedBy: CharacterSet(charactersIn: ",")).last
                emplacement = dernier?.trimmingCharacters(in: .whitespaces)
                if emplacement?.isEmpty == true { emplacement = nil }
            }
            return FichierProduit(nom: nom, emplacement: emplacement)
        }
    }

    /// Envois cités : « E-mail envoyé à Mme Rey », « Réponse partie à … ».
    public static func envoi(depuis e: EntreeJournal) -> EnvoiEffectue? {
        let texte = e.titre.lowercased()
        let verbes = ["envoyé", "envoyée", "envoyés", "partie", "parti ", "expédié", "expédiée", "transmis au client", "transmise au client"]
        guard e.type != .emailPrepare, e.type != .erreur, verbes.contains(where: { texte.contains($0) }) else { return nil }
        guard !texte.contains("pas envoy"), !texte.contains("non envoy"), !texte.contains("aucun envoi") else { return nil }
        var destinataire = "un tiers"
        for marqueur in [" à ", " a "] {
            if let r = e.titre.range(of: marqueur, options: [.backwards]) {
                let suite = e.titre[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " .;:"))
                if !suite.isEmpty, suite.count < 80 { destinataire = suite; break }
            }
        }
        return EnvoiEffectue(destinataire: destinataire, objet: e.detail, canal: "e-mail", le: e.date)
    }

    public static func etape(_ e: EntreeJournal) -> EtapeSuivi {
        EtapeSuivi(id: "j-" + e.id, le: e.date, qui: e.agent ?? "bureau", type: e.type.rawValue, titre: e.titre, detail: e.detail)
    }

    /// Complète l'action avec le journal (source 2). Sans effet si le PC a déjà donné son compte rendu (source 1).
    public static func appliquer(journal: [EntreeJournal], a action: ActionSuivie) -> ActionSuivie {
        guard action.source != .pc else { return action }
        let trouvees = entrees(pour: action, dans: journal)
        guard !trouvees.isEmpty else { return action }
        var a = action
        var etapes = a.etapes.filter { !$0.id.hasPrefix("j-") }
        etapes += trouvees.map(etape)
        a.etapes = trier(etapes)
        // Ce qui s'est passé après le geste décide de l'état.
        let apres = trouvees.filter { ($0.date ?? .distantFuture) >= action.le.addingTimeInterval(-30) }
        var fichiers = a.fichiers
        var envois = a.envois
        for e in apres {
            for f in Self.fichiers(dans: e.titre + "\n" + (e.detail ?? "")) where !fichiers.contains(where: { $0.nom == f.nom }) {
                fichiers.append(f)
            }
            if let envoi = envoi(depuis: e), !envois.contains(where: { $0.destinataire == envoi.destinataire && $0.le == envoi.le }) {
                envois.append(envoi)
            }
            if a.agent == nil { a.agent = e.agent }
        }
        a.fichiers = fichiers
        a.envois = envois
        if a.etat != .ecarte {
            if apres.contains(where: { $0.type == .erreur }) {
                a.etat = .erreur
            } else if apres.contains(where: { [.action, .reponse].contains($0.type) }) {
                a.etat = a.etat == .corrige ? .corrige : .fait
            } else if !apres.isEmpty, a.etat == .transmis {
                a.etat = .enCours
            }
            if a.etat == .corrige, let nouvelle = apres.first(where: { $0.type == .decision && $0.decisionReference != nil
                                                                      && $0.decisionReference != a.reference }) {
                a.decisionPreparee = nouvelle.decisionReference
            }
        }
        if a.resume == nil, a.etat == .fait, let derniere = apres.last(where: { [.action, .reponse].contains($0.type) }) {
            a.resume = derniere.titre
        }
        a.source = .journal
        return a
    }

    /// Saisies, questions et envois terrain : statut et résumé de `GET /saisies` (source 3).
    public static func appliquer(saisie s: SaisieHistorique, a action: ActionSuivie) -> ActionSuivie {
        guard action.source != .pc else { return action }
        var a = action
        switch s.statut {
        case .attente, .transmis: break
        case .enCours: a.etat = .enCours
        case .traite: a.etat = .fait
        case .erreur: a.etat = .erreur
        }
        if let r = s.resume, !r.isEmpty { a.resume = r }
        if let ref = s.decisionReference { a.decisionPreparee = ref }
        if a.agent == nil { a.agent = s.agent }
        if a.source == .geste { a.source = .saisies }
        return a
    }

    /// Compte rendu du PC (source 1) : il fait foi.
    public static func appliquer(pc s: SuiviPC, a action: ActionSuivie) -> ActionSuivie {
        var a = action
        if let e = s.etat { a.etat = e }
        a.agent = s.agent ?? a.agent
        a.resume = s.resume ?? s.erreur ?? a.resume
        a.fichiers = s.fichiers
        a.envois = s.envois
        a.decisionPreparee = s.decisionPreparee ?? a.decisionPreparee
        a.chantierId = a.chantierId ?? s.chantierId
        var etapes = a.etapes.filter { $0.qui == "vous" || $0.type == "reponse" }
        etapes += s.etapes.map(etape)
        if let err = s.erreur, !s.etapes.contains(where: { $0.type == .erreur }) {
            etapes.append(EtapeSuivi(id: "pc-erreur", le: nil, qui: s.agent ?? "bureau", type: "erreur", titre: "Erreur", detail: err))
        }
        a.etapes = trier(etapes)
        a.source = .pc
        return a
    }

    static func trier(_ etapes: [EtapeSuivi]) -> [EtapeSuivi] {
        var vus = Set<String>()
        return etapes.filter { vus.insert($0.id).inserted }
            .enumerated()
            .sorted { ($0.element.le ?? .distantFuture, $0.offset) < ($1.element.le ?? .distantFuture, $1.offset) }
            .map(\.element)
    }

    /// Une action créée depuis un compte rendu du PC (geste fait ailleurs : montre, notification, PC).
    public static func action(depuis s: SuiviPC) -> ActionSuivie {
        let le = s.gesteLe.flatMap(DateEndry.lire) ?? s.etapes.compactMap(\.date).min() ?? Date()
        let nature: NatureSuivi = s.reference.map { $0.uppercased().hasPrefix("Q-") ? .question : .decision } ?? .saisie
        var a = ActionSuivie(id: s.reference.map { "D:" + $0 } ?? "S:" + (s.saisieId ?? UUID().uuidString), nature: nature,
                             reference: s.reference, saisieId: s.saisieId, titre: s.titre ?? s.reference ?? "Saisie",
                             genre: s.genre, outil: s.outil, geste: s.geste ?? "oui", le: le, chantierId: s.chantierId, agent: s.agent)
        a.etapes = [EtapeSuivi(id: "geste", le: le, qui: "vous", type: "geste", titre: a.libelleGeste.components(separatedBy: " · ")[0])]
        return appliquer(pc: s, a: a)
    }
}
