import Foundation

public struct Parametre: Sendable, Hashable {
    public var nom: String
    public var valeur: String

    public init(_ nom: String, _ valeur: String) {
        self.nom = nom
        self.valeur = valeur
    }
}

/// Une requête vers le serveur de l'assistant, indépendante du transport (réseau réel ou démo).
public struct Requete: Sendable, Hashable {
    public enum Methode: String, Sendable { case get = "GET", post = "POST", delete = "DELETE" }

    public enum Corps: Sendable, Hashable {
        case json(Data)
        case multipart(FormulaireMultipart)
    }

    public var methode: Methode
    /// Chemin absolu (`/app/api/v1/accueil`) ou URL complète (pièces jointes).
    public var chemin: String
    public var parametres: [Parametre]
    public var corps: Corps?
    /// Délai d'attente : court pour les lectures, plus long pour les envois de photos.
    public var delai: TimeInterval

    public init(_ methode: Methode, _ chemin: String, parametres: [Parametre] = [], corps: Corps? = nil, delai: TimeInterval = 20) {
        self.methode = methode
        self.chemin = chemin
        self.parametres = parametres
        self.corps = corps
        self.delai = delai
    }

    /// Clé du cache hors ligne (lectures uniquement).
    public var cleCache: String? {
        guard methode == .get, chemin.hasPrefix("/app/api/") else { return nil }
        let suffixe = parametres.map { "\($0.nom)=\($0.valeur)" }.joined(separator: "&")
        return suffixe.isEmpty ? chemin : "\(chemin)?\(suffixe)"
    }
}

extension Requete {
    static let prefixe = "/app/api/v1"

    /// v1.1 : `appareil` fournit un jeton propre à cet iPhone ; v1.0 l'ignore.
    public static func session(acces: String, appareil: (nom: String, modele: String)? = nil) -> Requete {
        var corps: [String: Any] = ["acces": acces]
        if let appareil { corps["appareil"] = ["nom": appareil.nom, "modele": appareil.modele] }
        return .init(.post, "\(prefixe)/session", corps: .json(jsonObjet(corps)))
    }

    /// Délai généreux : le PC peut interroger Bexio et Zoho avant de répondre.
    public static let accueil = Requete(.get, "\(prefixe)/accueil", delai: 45)
    public static let decisions = Requete(.get, "\(prefixe)/decisions")
    public static let argent = Requete(.get, "\(prefixe)/argent", delai: 45)
    public static let actualiser = Requete(.post, "\(prefixe)/actualiser", delai: 90)

    public static func action(_ action: ActionDecision, reference: String, consignes: String?) -> Requete {
        let ref = reference.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? reference
        var corps: [String: String] = [:]
        if let consignes, !consignes.isEmpty { corps["consignes"] = consignes }
        return .init(.post, "\(prefixe)/decisions/\(ref)/\(action.rawValue)", corps: .json(json(corps)), delai: 45)
    }

    public static func chantiers(etape: String = "tous") -> Requete {
        .init(.get, "\(prefixe)/chantiers", parametres: [Parametre("etape", etape)])
    }

    public static func chantier(id: String) -> Requete {
        let ident = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return .init(.get, "\(prefixe)/chantiers/\(ident)")
    }

    public static func saisie(_ formulaire: FormulaireMultipart) -> Requete {
        .init(.post, "\(prefixe)/saisie", corps: .multipart(formulaire), delai: 120)
    }

    public static func appareil(jetonAPNs: String, nom: String, environnement: String) -> Requete {
        .init(.post, "\(prefixe)/appareils", corps: .json(json([
            "jeton_apns": jetonAPNs, "nom": nom, "environnement": environnement,
        ])))
    }

    public static func document(_ chemin: String) -> Requete {
        .init(.get, chemin, delai: 60)
    }

    // MARK: v1.1

    public static let appareils = Requete(.get, "\(prefixe)/appareils")

    public static func supprimerAppareil(_ id: String) -> Requete {
        .init(.delete, "\(prefixe)/appareils/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)")
    }

    public static let saisies = Requete(.get, "\(prefixe)/saisies", parametres: [Parametre("limite", "30")])
    public static let etatAssistant = Requete(.get, "\(prefixe)/assistant/etat")
    public static let pause = Requete(.post, "\(prefixe)/assistant/pause")
    public static let reprise = Requete(.post, "\(prefixe)/assistant/reprise")
    public static let sessionVoix = Requete(.post, "\(prefixe)/voix/session", delai: 15)
    public static let evenements = Requete(.get, "\(prefixe)/evenements", delai: 3_600)

    static func jsonObjet(_ objet: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: objet, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    static func json(_ dictionnaire: [String: String]) -> Data {
        (try? JSONSerialization.data(withJSONObject: dictionnaire, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}

/// Corps `multipart/form-data` pour la saisie terrain (texte + photos / scans).
public struct FormulaireMultipart: Sendable, Hashable {
    public struct Fichier: Sendable, Hashable {
        public var champ: String
        public var nomFichier: String
        public var typeMIME: String
        public var donnees: Data

        public init(champ: String = "photos", nomFichier: String, typeMIME: String, donnees: Data) {
            self.champ = champ
            self.nomFichier = nomFichier
            self.typeMIME = typeMIME
            self.donnees = donnees
        }
    }

    public static let tailleMaxFichier = 15 * 1024 * 1024

    public var frontiere: String
    public var champs: [Parametre]
    public var fichiers: [Fichier]

    public init(frontiere: String = "EndryFrontiere-\(UUID().uuidString)", champs: [Parametre] = [], fichiers: [Fichier] = []) {
        self.frontiere = frontiere
        self.champs = champs
        self.fichiers = fichiers
    }

    public var typeContenu: String { "multipart/form-data; boundary=\(frontiere)" }

    public func corps() -> Data {
        var d = Data()
        func ligne(_ s: String) { d.append(Data((s + "\r\n").utf8)) }
        for champ in champs {
            ligne("--\(frontiere)")
            ligne("Content-Disposition: form-data; name=\"\(echapper(champ.nom))\"")
            ligne("Content-Type: text/plain; charset=utf-8")
            ligne("")
            ligne(champ.valeur)
        }
        for f in fichiers {
            ligne("--\(frontiere)")
            ligne("Content-Disposition: form-data; name=\"\(echapper(f.champ))\"; filename=\"\(echapper(f.nomFichier))\"")
            ligne("Content-Type: \(f.typeMIME)")
            ligne("")
            d.append(f.donnees)
            ligne("")
        }
        ligne("--\(frontiere)--")
        return d
    }

    private func echapper(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    }

    /// Fichiers qui dépassent la limite du serveur (15 Mo).
    public var fichiersTropGros: [Fichier] { fichiers.filter { $0.donnees.count > Self.tailleMaxFichier } }
}
