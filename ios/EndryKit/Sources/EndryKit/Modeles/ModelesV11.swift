import Foundation

// Objets ajoutés par le serveur v1.1. Tout est facultatif à la lecture.

/// Un appareil connecté (`GET /appareils`).
public struct Appareil: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var nom: String
    public var modele: String?
    public var cree: String?
    public var vu: String?
    public var actuel: Bool

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        guard let id = c.texte("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "id manquant"))
        }
        self.id = id
        nom = c.texte("nom", defaut: "Appareil")
        modele = c.texte("modele")
        cree = c.texte("cree")
        vu = c.texte("vu")
        actuel = c.booleen("actuel") ?? false
    }

    public var dernierPassage: Date? { vu.flatMap(DateEndry.lire) }
}

/// Liste d'appareils : tableau nu ou `{appareils: [...]}`.
public struct ListeAppareils: Decodable, Sendable, Equatable {
    public var appareils: [Appareil]

    public init(from decoder: Decoder) throws {
        if let liste = try? [ElementTolerantPublic<Appareil>](from: decoder) {
            appareils = liste.compactMap(\.valeur)
        } else {
            appareils = try decoder.champs().liste("appareils")
        }
    }
}

public enum StatutSaisie: String, Sendable, Hashable {
    case attente, transmis, enCours = "en_cours", traite, erreur

    public var libelle: String {
        switch self {
        case .attente: "En attente de réseau"
        case .transmis: "Transmis"
        case .enCours: "En cours"
        case .traite: "Traité"
        case .erreur: "Erreur"
        }
    }

    /// Étape dans la frise Transmis → En cours → Traité → Décision prête.
    public var etape: Int {
        switch self {
        case .attente: 0
        case .transmis: 1
        case .enCours: 2
        case .traite, .erreur: 3
        }
    }
}

/// Une saisie terrain et son traitement par l'assistant (`GET /saisies`).
public struct SaisieHistorique: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var cree: String?
    public var texte: String
    public var photos: Int
    public var statut: StatutSaisie
    public var resume: String?
    public var decisionReference: String?

    public init(id: String, cree: String?, texte: String, photos: Int, statut: StatutSaisie, resume: String? = nil, decisionReference: String? = nil) {
        self.id = id
        self.cree = cree
        self.texte = texte
        self.photos = photos
        self.statut = statut
        self.resume = resume
        self.decisionReference = decisionReference
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        guard let id = c.texte("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "id manquant"))
        }
        self.id = id
        cree = c.texte("cree")
        texte = c.texte("texte", defaut: "")
        photos = c.entier("photos") ?? 0
        statut = c.texte("statut").flatMap(StatutSaisie.init(rawValue:)) ?? .transmis
        resume = c.texte("resume")
        decisionReference = c.texte("decision_reference").flatMap { $0.isEmpty ? nil : $0 }
    }

    /// « Décision prête » : traitée et une décision attend le patron.
    public var decisionPrete: Bool { statut == .traite && decisionReference != nil }
}

public struct ListeSaisies: Decodable, Sendable, Equatable {
    public var saisies: [SaisieHistorique]

    public init(from decoder: Decoder) throws {
        if let liste = try? [ElementTolerantPublic<SaisieHistorique>](from: decoder) {
            saisies = liste.compactMap(\.valeur)
        } else {
            saisies = try decoder.champs().liste("saisies")
        }
    }
}

/// `GET /assistant/etat`.
public struct EtatAssistant: Decodable, Sendable, Equatable {
    public var pause: Bool
    public var file: Int
    public var derniereActivite: String?

    public init(pause: Bool, file: Int = 0, derniereActivite: String? = nil) {
        self.pause = pause
        self.file = file
        self.derniereActivite = derniereActivite
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        pause = c.booleen("pause") ?? false
        file = c.entier("file") ?? 0
        derniereActivite = c.texte("derniere_activite")
    }
}

/// Outil exposé au modèle vocal (`POST /voix/session`).
public struct OutilVoix: Decodable, Sendable, Hashable {
    public var nom: String
    public var description: String
    /// Schéma JSON des paramètres, tel que fourni par le PC.
    public var parametres: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        nom = c.texte("name") ?? c.texte("nom") ?? ""
        description = c.texte("description", defaut: "")
        if let brut = try? c.decodeIfPresent(JSONBrut.self, forKey: CleJSON("parameters")) {
            parametres = brut.texte
        } else {
            parametres = nil
        }
    }
}

/// Session vocale éphémère délivrée par le PC. L'app ne détient jamais de clé permanente.
public struct SessionVoix: Decodable, Sendable, Equatable {
    public var disponible: Bool
    public var fournisseur: String?
    public var clientSecret: String?
    public var modele: String?
    public var voix: String?
    public var expire: String?
    public var instructions: String?
    public var outils: [OutilVoix]

    public init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        clientSecret = c.texte("client_secret")
            ?? (try? c.nestedContainer(keyedBy: CleJSON.self, forKey: CleJSON("client_secret")))?.texte("value")
        disponible = (c.booleen("disponible") ?? false) && clientSecret != nil
        fournisseur = c.texte("fournisseur")
        modele = c.texte("modele")
        voix = c.texte("voix")
        expire = c.texte("expire")
        instructions = c.texte("instructions")
        outils = c.liste("outils")
    }
}

/// Élément de tableau tolérant, public pour les listes nues.
public struct ElementTolerantPublic<T: Decodable>: Decodable {
    public let valeur: T?

    public init(from decoder: Decoder) throws {
        valeur = try? T(from: decoder)
    }
}

/// Garde n'importe quelle valeur JSON sous forme de texte (schémas d'outils).
struct JSONBrut: Decodable {
    let texte: String

    init(from decoder: Decoder) throws {
        let valeur = try JSONBrut.lire(decoder)
        let data = (try? JSONSerialization.data(withJSONObject: valeur, options: [.sortedKeys, .fragmentsAllowed])) ?? Data()
        texte = String(decoding: data, as: UTF8.self)
    }

    private struct N: Decodable {
        let v: Any
        init(from decoder: Decoder) throws { v = try JSONBrut.lire(decoder) }
    }

    static func lire(_ decoder: Decoder) throws -> Any {
        if let c = try? decoder.container(keyedBy: CleJSON.self) {
            var d: [String: Any] = [:]
            for k in c.allKeys { d[k.stringValue] = (try? c.decode(N.self, forKey: k))?.v ?? NSNull() }
            return d
        }
        if var u = try? decoder.unkeyedContainer() {
            var a: [Any] = []
            while !u.isAtEnd { a.append((try? u.decode(N.self))?.v ?? NSNull()) }
            return a
        }
        let s = try decoder.singleValueContainer()
        if s.decodeNil() { return NSNull() }
        if let b = try? s.decode(Bool.self) { return b }
        if let i = try? s.decode(Int.self) { return i }
        if let d = try? s.decode(Double.self) { return d }
        return try s.decode(String.self)
    }
}

extension EndryAPI {
    public func appareils() async throws(ErreurAPI) -> [Appareil] { try await charger(ListeAppareils.self, .appareils).appareils }

    public func supprimerAppareil(_ id: String) async throws(ErreurAPI) {
        _ = try await envoyer(.supprimerAppareil(id))
    }

    public func saisies() async throws(ErreurAPI) -> [SaisieHistorique] { try await charger(ListeSaisies.self, .saisies).saisies }
    public func etatAssistant() async throws(ErreurAPI) -> EtatAssistant { try await charger(EtatAssistant.self, .etatAssistant) }

    public func mettreEnPause(_ pause: Bool) async throws(ErreurAPI) {
        _ = try await envoyer(pause ? .pause : .reprise)
    }

    public func sessionVoix() async throws(ErreurAPI) -> SessionVoix { try await charger(SessionVoix.self, .sessionVoix) }
}
