import Foundation
#if canImport(Security)
import Security
#endif

/// Ce qui permet de parler au serveur : adresse de base + jeton.
public struct Identifiants: Codable, Sendable, Equatable {
    public var base: URL
    public var jeton: String
    public var entreprise: String?
    public var expireLe: Date?
    /// v1.1 : identifiant de l'appareil côté PC (absent avec l'ancien jeton commun).
    public var appareilId: String?
    /// Migration vers un jeton propre à l'appareil déjà tentée (réussie, déjà faite, ou serveur trop ancien).
    public var migrationTentee: Bool?
    /// v1.3 : rôle donné par le lien d'accès (`nil` : patron, comme avant).
    public var role: RoleAcces?
    /// v1.3 : nom de l'ouvrier (lien d'équipe).
    public var nom: String?

    /// L'app s'ouvre en mode équipe : chantiers du jour, heures, photos. Jamais l'argent ni les décisions.
    public var estOuvrier: Bool { role == .ouvrier }
    /// v1.12 : accès directeur — les montants et « Poser une question », en lecture seule.
    public var estDirecteur: Bool { role == .directeur }

    public init(base: URL, jeton: String, entreprise: String? = nil, expireLe: Date? = nil, appareilId: String? = nil) {
        self.base = base
        self.jeton = jeton
        self.entreprise = entreprise
        self.expireLe = expireLe
        self.appareilId = appareilId
    }

    public var estExpire: Bool {
        guard let expireLe else { return false }
        return expireLe < Date()
    }
}

/// Stockage du jeton. En production : uniquement le trousseau iOS.
public protocol CoffreJeton: Sendable {
    func lire() -> Identifiants?
    func enregistrer(_ identifiants: Identifiants) throws
    func effacer()
}

/// Coffre en mémoire (mode démo, tests, aperçus).
public final class CoffreMemoire: CoffreJeton, @unchecked Sendable {
    private let verrou = NSLock()
    private var valeur: Identifiants?

    public init(_ valeur: Identifiants? = nil) {
        self.valeur = valeur
    }

    public func lire() -> Identifiants? {
        verrou.lock(); defer { verrou.unlock() }
        return valeur
    }

    public func enregistrer(_ identifiants: Identifiants) throws {
        verrou.lock(); defer { verrou.unlock() }
        valeur = identifiants
    }

    public func effacer() {
        verrou.lock(); defer { verrou.unlock() }
        valeur = nil
    }
}

#if canImport(Security)
public enum ErreurTrousseau: Error, Equatable, Sendable {
    case statut(Int32)
}

/// Jeton rangé dans le trousseau iOS, accessible après le premier déverrouillage, jamais synchronisé ni sauvegardé
/// hors de l'appareil (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
///
public struct CoffreTrousseau: CoffreJeton {
    public let service: String
    public let compte: String
    public let groupe: String?

    /// Groupe de trousseau partagé avec le widget d'Endry. Présent seulement quand l'app est signée avec
    /// l'extension (clé `EndryGroupeTrousseau` de l'Info.plist) ; sinon le trousseau propre à l'app.
    public static var groupePartage: String? {
        guard let g = Bundle.main.object(forInfoDictionaryKey: "EndryGroupeTrousseau") as? String,
              !g.isEmpty, !g.contains("$(") else { return nil }
        return g
    }

    public init(service: String = "com.endrysa.endry", compte: String = "session", groupe: String? = CoffreTrousseau.groupePartage) {
        self.service = service
        self.compte = compte
        self.groupe = groupe
    }

    private func requeteDeBase(groupe: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte,
        ]
        if let groupe { q[kSecAttrAccessGroup as String] = groupe }
        return q
    }

    private func lireElement(groupe: String?) -> (Identifiants, String?)? {
        var q = requeteDeBase(groupe: groupe)
        q[kSecReturnData as String] = true
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultat: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &resultat) == errSecSuccess,
              let attributs = resultat as? [String: Any], let data = attributs[kSecValueData as String] as? Data,
              let identifiants = try? JSONDecoder().decode(Identifiants.self, from: data) else { return nil }
        return (identifiants, attributs[kSecAttrAccessGroup as String] as? String)
    }

    public func lire() -> Identifiants? {
        if let element = lireElement(groupe: groupe) { return element.0 }
        // Jeton rangé avant le widget : relu, puis déplacé dans le groupe partagé (une fois).
        guard let groupe, let ancien = lireElement(groupe: nil), ancien.1 != groupe else { return nil }
        if (try? ajouter(ancien.0, groupe: groupe)) != nil, let groupeAncien = ancien.1 {
            SecItemDelete(requeteDeBase(groupe: groupeAncien) as CFDictionary)
        }
        return ancien.0
    }

    public func enregistrer(_ identifiants: Identifiants) throws {
        do {
            try ajouter(identifiants, groupe: groupe)
        } catch ErreurTrousseau.statut(let statut) where statut == errSecMissingEntitlement && groupe != nil {
            // Build sans l'extension (groupe non signé) : trousseau propre à l'app.
            try ajouter(identifiants, groupe: nil)
        }
    }

    private func ajouter(_ identifiants: Identifiants, groupe: String?) throws {
        let data = try JSONEncoder().encode(identifiants)
        let q = requeteDeBase(groupe: groupe)
        let attributs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var statut = SecItemUpdate(q as CFDictionary, attributs as CFDictionary)
        if statut == errSecItemNotFound {
            var ajout = q
            ajout.merge(attributs) { _, nouveau in nouveau }
            statut = SecItemAdd(ajout as CFDictionary, nil)
        }
        guard statut == errSecSuccess else { throw ErreurTrousseau.statut(statut) }
    }

    /// Efface le jeton partout (groupe partagé et ancien emplacement).
    public func effacer() {
        SecItemDelete(requeteDeBase(groupe: nil) as CFDictionary)
        if let groupe { SecItemDelete(requeteDeBase(groupe: groupe) as CFDictionary) }
    }
}
#endif
