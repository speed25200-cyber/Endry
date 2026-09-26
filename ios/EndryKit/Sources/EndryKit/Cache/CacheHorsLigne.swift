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
            case .injoignable, .horsLigne, .nonAuthentifie:
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

/// Résumé partagé avec le widget via le groupe d'apps (pas de secret dedans).
public struct ResumeWidget: Codable, Sendable, Equatable {
    public var decisions: Int
    public var aEncaisser: Double
    public var enRetardPlus30: Double
    public var prochaineDecision: String?
    public var majLe: Date

    public init(decisions: Int, aEncaisser: Double, enRetardPlus30: Double, prochaineDecision: String?, majLe: Date) {
        self.decisions = decisions
        self.aEncaisser = aEncaisser
        self.enRetardPlus30 = enRetardPlus30
        self.prochaineDecision = prochaineDecision
        self.majLe = majLe
    }

    public init(accueil: Accueil, majLe: Date = Date()) {
        self.init(
            decisions: accueil.decisions.count,
            aEncaisser: accueil.encaisser.total,
            enRetardPlus30: accueil.encaisser.anciennete.plus30,
            prochaineDecision: accueil.decisions.first?.titre,
            majLe: majLe
        )
    }

    public static let exemple = ResumeWidget(decisions: 5, aEncaisser: 46_109.70, enRetardPlus30: 22_242.10,
                                             prochaineDecision: "Réponse à Mme Bersier — offre salle de bains", majLe: Date())

    public static let cle = "resume-widget"

    public static func lire(groupe: String) -> ResumeWidget? {
        guard let data = UserDefaults(suiteName: groupe)?.data(forKey: cle) else { return nil }
        return try? JSONDecoder().decode(ResumeWidget.self, from: data)
    }

    public func enregistrer(groupe: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: groupe)?.set(data, forKey: Self.cle)
    }

    public static func effacer(groupe: String) {
        UserDefaults(suiteName: groupe)?.removeObject(forKey: cle)
    }
}
