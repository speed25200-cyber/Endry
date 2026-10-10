import Foundation

/// Dernier état connu de chaque écran, pour la consultation hors ligne (lecture seule).
///
/// Les réponses brutes sont rangées dans « Application Support », protégées par le chiffrement iOS
/// (accessibles après le premier déverrouillage), exclues des sauvegardes iCloud, et effacées à la déconnexion.
public actor CacheHorsLigne {
    private let dossier: URL?
    private var memoire: [String: (Data, Date)] = [:]

    /// `dossier == nil` : cache en mémoire seulement (tests, aperçus).
    public init(dossier: URL?) {
        self.dossier = dossier
    }

    public static func parDefaut() -> CacheHorsLigne {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return CacheHorsLigne(dossier: base?.appendingPathComponent("cache-hors-ligne", isDirectory: true))
    }

    private func fichier(_ cle: String) -> URL? {
        let nom = cle.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return dossier?.appendingPathComponent(nom + ".json")
    }

    public func enregistrer(_ data: Data, cle: String, le date: Date = Date()) {
        memoire[cle] = (data, date)
        guard let dossier, let url = fichier(cle) else { return }
        do {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: [.atomic])
            #endif
            var valeurs = URLResourceValues()
            valeurs.isExcludedFromBackup = true
            var dossierModifiable = dossier
            try? dossierModifiable.setResourceValues(valeurs)
        } catch {
            // Cache facultatif : une écriture ratée n'empêche rien.
        }
    }

    public func lire(cle: String) -> (data: Data, date: Date)? {
        if let (data, date) = memoire[cle] { return (data, date) }
        guard let url = fichier(cle),
              let data = try? Data(contentsOf: url),
              let attributs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributs[.modificationDate] as? Date else { return nil }
        memoire[cle] = (data, date)
        return (data, date)
    }

    public func effacer() {
        memoire.removeAll()
        if let dossier { try? FileManager.default.removeItem(at: dossier) }
    }
}

/// Résultat d'un chargement : valeur fraîche, ou dernier état en cache si le serveur est injoignable.
public struct Charge<T: Sendable>: Sendable {
    public var valeur: T
    public var majLe: Date
    public var depuisCache: Bool
    /// Erreur rencontrée lorsque la valeur vient du cache.
    public var erreur: ErreurAPI?
}

extension EndryAPI {
    /// Lecture réseau avec repli sur le cache hors ligne.
    public func charger<T: Decodable & Sendable>(
        _ type: T.Type, _ requete: Requete, cache: CacheHorsLigne?
    ) async throws(ErreurAPI) -> Charge<T> {
        do {
            let data = try await envoyer(requete)
            let valeur = try decoder(T.self, depuis: data)
            if let cache, let cle = requete.cleCache {
                await cache.enregistrer(data, cle: cle)
            }
            return Charge(valeur: valeur, majLe: Date(), depuisCache: false, erreur: nil)
        } catch {
            switch error {
            case .injoignable, .horsLigne, .nonAuthentifie, .delaiDepasse:
                if let cache, let cle = requete.cleCache, let enCache = await cache.lire(cle: cle),
                   let valeur = try? decoder(T.self, depuis: enCache.data) {
                    return Charge(valeur: valeur, majLe: enCache.date, depuisCache: true, erreur: error)
                }
                throw error
            default:
                throw error
            }
        }
    }
}
