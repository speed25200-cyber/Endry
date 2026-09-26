import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ErreurAPI: Error, Equatable, Sendable {
    /// 401 sur la session : lien invalide ou révoqué.
    case lienInvalide(String?)
    /// 401 ailleurs : jeton expiré, révoqué, ou serveur remplacé.
    case nonAuthentifie(String?)
    /// 400 : le serveur refuse l'action (ex. consignes manquantes).
    case refus(String)
    /// Pas de réseau, délai dépassé, hôte introuvable (souvent : l'adresse du tunnel a changé).
    case injoignable(String)
    case serveur(statut: Int, message: String?)
    case decodage(String)
    case horsLigne

    public var message: String {
        switch self {
        case .lienInvalide(let m):
            m ?? "Ce lien d’accès n’est plus valable. Demandez un nouveau lien au bureau."
        case .nonAuthentifie:
            "Connexion perdue : collez le nouveau lien."
        case .refus(let m):
            m
        case .injoignable:
            "Serveur injoignable. Si l’adresse a changé, collez le nouveau lien."
        case .serveur(let statut, let m):
            m ?? "Le serveur a répondu une erreur (\(statut))."
        case .decodage:
            "Réponse inattendue du serveur."
        case .horsLigne:
            "Hors ligne : action impossible sans réseau."
        }
    }

    /// Faut-il proposer de coller un nouveau lien ?
    public var demandeNouveauLien: Bool {
        switch self {
        case .lienInvalide, .nonAuthentifie, .injoignable: true
        default: false
        }
    }

    /// Faut-il basculer sur le cache hors ligne ?
    public var estProblemeReseau: Bool {
        switch self {
        case .injoignable, .horsLigne: true
        default: false
        }
    }
}

/// Tout ce que l'app sait faire avec le serveur passe par ici : réseau réel ou mode démo.
public protocol EndryAPI: Sendable {
    /// Envoie la requête et renvoie le corps d'une réponse 2xx, ou lève une `ErreurAPI`.
    func envoyer(_ requete: Requete) async throws(ErreurAPI) -> Data
    /// URL complète (pour l'abonnement calendrier `webcal://`).
    func urlAbsolue(_ chemin: String) -> URL?
}

extension EndryAPI {
    public func decoder<T: Decodable>(_ type: T.Type, depuis data: Data) throws(ErreurAPI) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw .decodage(String(describing: error))
        }
    }

    public func charger<T: Decodable>(_ type: T.Type, _ requete: Requete) async throws(ErreurAPI) -> T {
        try decoder(T.self, depuis: await envoyer(requete))
    }

    public func accueil() async throws(ErreurAPI) -> Accueil { try await charger(Accueil.self, .accueil) }
    public func decisions() async throws(ErreurAPI) -> ReponseDecisions { try await charger(ReponseDecisions.self, .decisions) }
    public func argent() async throws(ErreurAPI) -> Argent { try await charger(Argent.self, .argent) }

    public func chantiers(etape: String = "tous") async throws(ErreurAPI) -> ReponseChantiers {
        try await charger(ReponseChantiers.self, .chantiers(etape: etape))
    }

    public func chantier(id: String) async throws(ErreurAPI) -> Dossier {
        try await charger(Dossier.self, .chantier(id: id))
    }

    public func agir(_ action: ActionDecision, sur reference: String, consignes: String? = nil) async throws(ErreurAPI) -> ReponseAction {
        let reponse = try await charger(ReponseAction.self, .action(action, reference: reference, consignes: consignes))
        guard reponse.ok else { throw .refus(reponse.message) }
        return reponse
    }

    public func saisie(texte: String, fichiers: [FormulaireMultipart.Fichier]) async throws(ErreurAPI) -> ReponseSimple {
        let formulaire = FormulaireMultipart(champs: [Parametre("texte", texte)], fichiers: fichiers)
        let reponse = try await charger(ReponseSimple.self, .saisie(formulaire))
        guard reponse.ok else { throw .refus(reponse.message ?? "La saisie n’a pas été acceptée.") }
        return reponse
    }

    public func actualiser() async throws(ErreurAPI) -> ReponseSimple { try await charger(ReponseSimple.self, .actualiser) }

    public func enregistrerAppareil(jetonAPNs: String, nom: String, environnement: String) async throws(ErreurAPI) -> ReponseSimple {
        try await charger(ReponseSimple.self, .appareil(jetonAPNs: jetonAPNs, nom: nom, environnement: environnement))
    }

    /// Télécharge un document (PDF) et le range dans un fichier temporaire pour QuickLook.
    public func telechargerDocument(_ chemin: String, nom: String) async throws(ErreurAPI) -> URL {
        let data = try await envoyer(.document(chemin))
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("documents", isDirectory: true)
        let nomPropre = nom.replacingOccurrences(of: "/", with: "-").isEmpty ? "document.pdf" : nom.replacingOccurrences(of: "/", with: "-")
        let fichier = dossier.appendingPathComponent(nomPropre.lowercased().hasSuffix(".pdf") ? nomPropre : nomPropre + ".pdf")
        do {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            try data.write(to: fichier, options: [.atomic])
        } catch {
            throw .serveur(statut: 0, message: "Impossible d’enregistrer le document.")
        }
        return fichier
    }
}

// MARK: - Transport

public protocol TransportHTTP: Sendable {
    func executer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct TransportURLSession: TransportHTTP {
    public let session: URLSession

    public init(session: URLSession = TransportURLSession.sessionParDefaut()) {
        self.session = session
    }

    /// Pas de cache disque d'URLSession (données financières), pas de cookies.
    public static func sessionParDefaut() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        #if !canImport(FoundationNetworking)
        configuration.waitsForConnectivity = false
        #endif
        configuration.timeoutIntervalForResource = 180
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    public func executer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, reponse) = try await session.data(for: requete)
        guard let http = reponse as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

// MARK: - Client réel

/// Client de l'API v1 de l'assistant. L'adresse de base vient toujours du lien d'accès.
public struct ClientAPI: EndryAPI {
    public let base: URL
    public let jeton: String?
    public let transport: TransportHTTP

    public init(base: URL, jeton: String?, transport: TransportHTTP = TransportURLSession()) {
        self.base = base
        self.jeton = jeton
        self.transport = transport
    }

    public init(identifiants: Identifiants, transport: TransportHTTP = TransportURLSession()) {
        self.init(base: identifiants.base, jeton: identifiants.jeton, transport: transport)
    }

    /// Échange le secret du lien contre un jeton.
    public static func ouvrirSession(_ lien: LienAcces, transport: TransportHTTP = TransportURLSession()) async throws(ErreurAPI) -> Identifiants {
        let client = ClientAPI(base: lien.base, jeton: nil, transport: transport)
        let data: Data
        do {
            data = try await client.envoyer(.session(acces: lien.secret))
        } catch .nonAuthentifie(let message) {
            throw .lienInvalide(message)
        }
        let session = try client.decoder(SessionOuverte.self, depuis: data)
        let expiration = session.valableJours.map { Date().addingTimeInterval(TimeInterval($0) * 86_400) }
        return Identifiants(base: lien.base, jeton: session.jeton, entreprise: session.entreprise, expireLe: expiration)
    }

    public func urlAbsolue(_ chemin: String) -> URL? {
        if chemin.lowercased().hasPrefix("http://") || chemin.lowercased().hasPrefix("https://") {
            return URL(string: chemin)
        }
        let cheminPropre = chemin.hasPrefix("/") ? chemin : "/" + chemin
        return URL(string: base.absoluteString + cheminPropre)
    }

    /// Le jeton n'est envoyé qu'au serveur du lien d'accès, jamais à un autre hôte.
    func memeServeur(_ url: URL) -> Bool {
        url.host?.lowercased() == base.host?.lowercased() && url.port == base.port && url.scheme == base.scheme
    }

    func construire(_ requete: Requete) throws(ErreurAPI) -> URLRequest {
        guard var url = urlAbsolue(requete.chemin) else { throw .serveur(statut: 0, message: "Adresse invalide.") }
        if !requete.parametres.isEmpty, var composants = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            composants.queryItems = (composants.queryItems ?? []) + requete.parametres.map { URLQueryItem(name: $0.nom, value: $0.valeur) }
            url = composants.url ?? url
        }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requete.delai)
        r.httpMethod = requete.methode.rawValue
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("fr-CH", forHTTPHeaderField: "Accept-Language")
        if let jeton, memeServeur(url) {
            r.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
        }
        switch requete.corps {
        case .json(let data):
            r.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            r.httpBody = data
        case .multipart(let formulaire):
            r.setValue(formulaire.typeContenu, forHTTPHeaderField: "Content-Type")
            r.httpBody = formulaire.corps()
        case nil:
            break
        }
        return r
    }

    public func envoyer(_ requete: Requete) async throws(ErreurAPI) -> Data {
        let urlRequete = try construire(requete)
        let data: Data
        let reponse: HTTPURLResponse
        do {
            (data, reponse) = try await transport.executer(urlRequete)
        } catch let erreur as URLError {
            switch erreur.code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                throw .horsLigne
            default:
                throw .injoignable(erreur.localizedDescription)
            }
        } catch is CancellationError {
            throw .injoignable("annulé")
        } catch {
            throw .injoignable(String(describing: error))
        }

        let corpsErreur = try? JSONDecoder().decode(CorpsErreur.self, from: data)
        switch reponse.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            if corpsErreur?.erreur == "lien_invalide" { throw .lienInvalide(corpsErreur?.message) }
            throw .nonAuthentifie(corpsErreur?.message)
        case 400, 409, 422:
            throw .refus(corpsErreur?.message ?? "Action refusée par le serveur.")
        case 502, 503, 504, 530:
            // Tunnel Cloudflare sans serveur derrière : l'adresse a probablement changé.
            throw .injoignable("statut \(reponse.statusCode)")
        default:
            throw .serveur(statut: reponse.statusCode, message: corpsErreur?.message)
        }
    }
}
