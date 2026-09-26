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
    public enum Methode: String, Sendable { case get = "GET", post = "POST" }

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

    public static func session(acces: String) -> Requete {
        .init(.post, "\(prefixe)/session", corps: .json(json(["acces": acces])))
    }

    public static let accueil = Requete(.get, "\(prefixe)/accueil")
    public static let decisions = Requete(.get, "\(prefixe)/decisions")
    public static let argent = Requete(.get, "\(prefixe)/argent")
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
