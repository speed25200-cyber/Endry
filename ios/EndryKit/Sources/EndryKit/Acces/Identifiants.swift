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

    public init(service: String = "com.endrysa.endry", compte: String = "session", groupe: String? = nil) {
        self.service = service
        self.compte = compte
        self.groupe = groupe
    }

    private func requeteDeBase() -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte,
        ]
        if let groupe { q[kSecAttrAccessGroup as String] = groupe }
        return q
    }

    public func lire() -> Identifiants? {
        var q = requeteDeBase()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultat: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &resultat) == errSecSuccess,
              let data = resultat as? Data else { return nil }
        return try? JSONDecoder().decode(Identifiants.self, from: data)
    }

    public func enregistrer(_ identifiants: Identifiants) throws {
        let data = try JSONEncoder().encode(identifiants)
        let q = requeteDeBase()
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

    public func effacer() {
        SecItemDelete(requeteDeBase() as CFDictionary)
    }
}
#endif
