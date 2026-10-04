import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Client HTTP du Kit (issu du skill app-pilotage-entreprise) : une seule URLSession chaude, erreurs typées
// avec un message humain, jeton envoyé seulement à l'hôte du lien d'accès. L'app (et la démo) ne voient que
// le protocole `{{PREFIXE}}API`.

public enum ErreurAPI: Error, Equatable, Sendable {
    case lienInvalide(String?)
    case nonAuthentifie(String?)
    case refus(String)
    case injoignable(String)
    case horsLigne
    /// Le PC répond trop lentement : l'action a peut-être abouti.
    case delaiDepasse
    case serveur(statut: Int, message: String?)
    case decodage(String)

    public var message: String {
        switch self {
        case .lienInvalide(let m): m ?? "Ce lien d’accès n’est plus valable. Demandez un nouveau lien au bureau."
        case .nonAuthentifie: "Connexion perdue : collez le nouveau lien."
        case .refus(let m): m
        case .injoignable: "Le bureau est injoignable. Si l’adresse a changé, collez le nouveau lien."
        case .horsLigne: "Pas de connexion : dernières données affichées."
        case .delaiDepasse: "Le bureau met plus de temps que prévu : vérifiez dans un instant."
        case .serveur(let statut, let m): m ?? "Le bureau a répondu une erreur (\(statut))."
        case .decodage: "Réponse inattendue du bureau."
        }
    }
}

public struct Requete: Sendable, Hashable {
    public enum Methode: String, Sendable { case get = "GET", post = "POST", delete = "DELETE" }

    public var methode: Methode
    /// Chemin absolu (`/app/api/v1/accueil`) ou URL complète (documents).
    public var chemin: String
    public var parametres: [String: String]
    public var corps: Data?
    /// Délai propre à la requête : 20 s en lecture, 45 s pour les agrégats lents, au-delà pour l'ERP.
    public var delai: TimeInterval

    public init(_ methode: Methode, _ chemin: String, parametres: [String: String] = [:], corps: Data? = nil,
                delai: TimeInterval = 20) {
        self.methode = methode
        self.chemin = chemin
        self.parametres = parametres
        self.corps = corps
        self.delai = delai
    }

    static let prefixe = "/app/api/v1"

    public static let accueil = Requete(.get, "\(prefixe)/accueil", delai: 45)
    public static let decisions = Requete(.get, "\(prefixe)/decisions")
    public static let evenements = Requete(.get, "\(prefixe)/evenements", delai: 24 * 3_600)

    /// Long-poll : le PC répond dès que la réponse est prête, au plus après `attente` secondes.
    public static func suiviQuestion(_ id: String, attente: Int? = nil) -> Requete {
        var r = Requete(.get, "\(prefixe)/questions/\(id)")
        if let attente {
            r.parametres["attendre"] = String(attente)
            r.delai = TimeInterval(attente) + 10
        }
        return r
    }

    public static func question(_ texte: String, agent: String? = nil) -> Requete {
        var objet = ["question": texte]
        if let agent { objet["agent"] = agent }
        return Requete(.post, "\(prefixe)/assistant/question", corps: try? JSONEncoder().encode(objet))
    }
}

public protocol {{PREFIXE}}API: Sendable {
    func envoyer(_ requete: Requete) async throws(ErreurAPI) -> Data
}

extension {{PREFIXE}}API {
    public func lire<T: Decodable>(_ type: T.Type, _ requete: Requete) async throws(ErreurAPI) -> T {
        let data = try await envoyer(requete)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw .decodage(String(describing: error))
        }
    }
}

public struct ClientAPI: {{PREFIXE}}API {
    public let base: URL
    public let jeton: String?

    public init(base: URL, jeton: String?) {
        self.base = base
        self.jeton = jeton
    }

    /// Une seule session pour toute l'app (requêtes et flux SSE) : connexion TLS chaude, aucune poignée de main
    /// avant une question. Éphémère : pas de cache disque (données financières), pas de cookies.
    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        #if !canImport(FoundationNetworking)
        configuration.waitsForConnectivity = false
        #endif
        configuration.timeoutIntervalForResource = 24 * 3_600
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func url(_ chemin: String) -> URL? {
        if chemin.lowercased().hasPrefix("https://") || chemin.lowercased().hasPrefix("http://") { return URL(string: chemin) }
        return URL(string: base.absoluteString + (chemin.hasPrefix("/") ? chemin : "/" + chemin))
    }

    /// Le jeton ne part jamais vers un autre hôte que celui du lien d'accès.
    func memeServeur(_ url: URL) -> Bool {
        url.host?.lowercased() == base.host?.lowercased() && url.port == base.port && url.scheme == base.scheme
    }

    public func construire(_ requete: Requete) throws(ErreurAPI) -> URLRequest {
        guard var adresse = url(requete.chemin) else { throw .serveur(statut: 0, message: "Adresse invalide.") }
        if !requete.parametres.isEmpty, var composants = URLComponents(url: adresse, resolvingAgainstBaseURL: false) {
            composants.queryItems = (composants.queryItems ?? [])
                + requete.parametres.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            adresse = composants.url ?? adresse
        }
        var r = URLRequest(url: adresse, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requete.delai)
        r.httpMethod = requete.methode.rawValue
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("fr-CH", forHTTPHeaderField: "Accept-Language")
        if let jeton, memeServeur(adresse) { r.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization") }
        if let corps = requete.corps {
            r.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            r.httpBody = corps
        }
        return r
    }

    public func envoyer(_ requete: Requete) async throws(ErreurAPI) -> Data {
        let urlRequete = try construire(requete)
        let data: Data
        let reponse: URLResponse
        do {
            (data, reponse) = try await Self.session.data(for: urlRequete)
        } catch let erreur as URLError {
            switch erreur.code {
            case .notConnectedToInternet, .dataNotAllowed: throw .horsLigne
            case .timedOut: throw .delaiDepasse
            default: throw .injoignable(erreur.localizedDescription)
            }
        } catch {
            throw .injoignable(String(describing: error))
        }
        guard let http = reponse as? HTTPURLResponse else { throw .injoignable("réponse non HTTP") }
        let message = (try? JSONDecoder().decode([String: String].self, from: data))?["message"]
        switch http.statusCode {
        case 200..<300: return data
        case 400: throw .refus(message ?? "Le bureau refuse cette action.")
        case 401: throw .nonAuthentifie(message)
        default: throw .serveur(statut: http.statusCode, message: message)
        }
    }
}
