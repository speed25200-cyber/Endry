import Foundation

public enum ErreurLien: Error, Equatable, Sendable {
    case vide
    case pasUnLienEndry
    case secretManquant

    public var message: String {
        switch self {
        case .vide: "Collez le lien d’accès reçu par e-mail."
        case .pasUnLienEndry: "Ce texte ne contient pas de lien d’accès Endry (…/app/acces/…)."
        case .secretManquant: "Le lien est incomplet : la partie après « /app/acces/ » manque."
        }
    }
}

/// Lien d'accès envoyé à la direction : `https://<hôte>/app/acces/<secret>`.
///
/// L'app en tire l'adresse du serveur (jamais codée en dur) et le secret à échanger contre un jeton.
public struct LienAcces: Equatable, Sendable {
    public static let marqueur = "/app/acces/"

    /// Adresse de base du serveur, sans barre finale (ex. `https://abc.trycloudflare.com`, `http://100.64.1.2:8080`).
    public var base: URL
    public var secret: String

    public init(base: URL, secret: String) {
        self.base = base
        self.secret = secret
    }

    /// Accepte un lien seul, un e-mail collé en entier, un QR code, avec ou sans `https://`.
    public static func analyser(_ texte: String) throws(ErreurLien) -> LienAcces {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { throw .vide }

        guard let plage = propre.range(of: marqueur, options: .caseInsensitive) else { throw .pasUnLienEndry }

        // Partie hôte : on remonte jusqu'au début du « mot » qui contient le lien.
        let avant = propre[..<plage.lowerBound]
        let debutMot = avant.lastIndex(where: { $0.isWhitespace || "<>\"'()[]".contains($0) })
            .map { avant.index(after: $0) } ?? avant.startIndex
        var hote = String(avant[debutMot...])

        // Partie secrète : jusqu'au premier séparateur.
        let apres = propre[plage.upperBound...]
        let finSecret = apres.firstIndex(where: { $0.isWhitespace || "/?#<>\"'()[]".contains($0) }) ?? apres.endIndex
        let secretBrut = String(apres[..<finSecret])
        let secret = (secretBrut.removingPercentEncoding ?? secretBrut)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!"))
        guard !secret.isEmpty else { throw .secretManquant }

        if hote.lowercased().hasPrefix("webcal://") {
            hote = "https://" + hote.dropFirst("webcal://".count)
        }
        if !hote.lowercased().hasPrefix("http://"), !hote.lowercased().hasPrefix("https://") {
            // Sans schéma : http pour une adresse IP privée (Tailscale), https sinon.
            hote = (estAdresseIP(hote) ? "http://" : "https://") + hote
        }
        while hote.hasSuffix("/") { hote.removeLast() }

        guard let url = URL(string: hote), let host = url.host, !host.isEmpty, host.contains(".") || host == "localhost" else {
            throw .pasUnLienEndry
        }
        return LienAcces(base: url, secret: secret)
    }

    private static func estAdresseIP(_ hote: String) -> Bool {
        let sansPort = hote.split(separator: "/").first.map(String.init) ?? hote
        let partieHote = sansPort.split(separator: ":").first.map(String.init) ?? sansPort
        let octets = partieHote.split(separator: ".")
        return octets.count == 4 && octets.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }

    /// Nom d'hôte lisible pour l'interface (« abc.trycloudflare.com »).
    public var hoteAffiche: String {
        var s = base.host ?? base.absoluteString
        if let port = base.port { s += ":\(port)" }
        return s
    }
}
