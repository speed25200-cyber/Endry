import Foundation

/// Clé de décodage dynamique : permet de lire n'importe quel champ par son nom.
public struct CleJSON: CodingKey, Hashable, Sendable {
    public var stringValue: String
    public var intValue: Int?

    public init(_ nom: String) {
        stringValue = nom
        intValue = nil
    }

    public init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    public init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Élément d'un tableau qui ne fait jamais échouer le tableau entier.
private struct ElementTolerant<T: Decodable>: Decodable {
    let valeur: T?

    init(from decoder: Decoder) throws {
        valeur = try? T(from: decoder)
    }
}

/// Lecture tolérante : un champ absent, nul ou d'un type inattendu ne casse jamais le décodage.
/// Le serveur est un assistant Python qui peut évoluer ; l'app doit rester lisible.
extension KeyedDecodingContainer where Key == CleJSON {
    public func texte(_ nom: String) -> String? {
        let cle = CleJSON(nom)
        if let s = try? decodeIfPresent(String.self, forKey: cle) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: cle) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: cle) { return String(d) }
        return nil
    }

    public func texte(_ nom: String, defaut: String) -> String {
        texte(nom) ?? defaut
    }

    public func nombre(_ nom: String) -> Double? {
        let cle = CleJSON(nom)
        if let d = try? decodeIfPresent(Double.self, forKey: cle) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: cle) { return Double.depuisTexteSuisse(s) }
        return nil
    }

    public func entier(_ nom: String) -> Int? {
        let cle = CleJSON(nom)
        if let i = try? decodeIfPresent(Int.self, forKey: cle) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: cle) { return Int(d.rounded()) }
        if let s = try? decodeIfPresent(String.self, forKey: cle) { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    public func booleen(_ nom: String) -> Bool? {
        let cle = CleJSON(nom)
        if let b = try? decodeIfPresent(Bool.self, forKey: cle) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: cle) { return i != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: cle) {
            switch s.lowercased() {
            case "true", "oui", "1", "yes": return true
            case "false", "non", "0", "no", "": return false
            default: return nil
            }
        }
        return nil
    }

    /// Tableau tolérant : les éléments illisibles sont ignorés.
    public func liste<T: Decodable>(_ nom: String, _ type: T.Type = T.self) -> [T] {
        guard let elements = try? decodeIfPresent([ElementTolerant<T>].self, forKey: CleJSON(nom)) else { return [] }
        return elements.compactMap(\.valeur)
    }

    public func textes(_ nom: String) -> [String] {
        let cle = CleJSON(nom)
        if let s = try? decodeIfPresent(String.self, forKey: cle) {
            return s.isEmpty ? [] : [s]
        }
        return liste(nom, String.self)
    }

    public func objet<T: Decodable>(_ nom: String, _ type: T.Type = T.self) -> T? {
        (try? decodeIfPresent(T.self, forKey: CleJSON(nom))) ?? nil
    }
}

extension Decoder {
    /// Conteneur à clés dynamiques, ou conteneur vide si le JSON n'est pas un objet.
    public func champs() throws -> KeyedDecodingContainer<CleJSON> {
        try container(keyedBy: CleJSON.self)
    }
}

extension Double {
    /// Lit « 13'695.45 », « 13’695,45 », « CHF 1 200.– »…
    public static func depuisTexteSuisse(_ texte: String) -> Double? {
        var s = texte
            .replacingOccurrences(of: "CHF", with: "")
            .replacingOccurrences(of: "Fr.", with: "")
            .replacingOccurrences(of: ".–", with: "")
            .replacingOccurrences(of: ".-", with: "")
        for separateur in ["'", "’", " ", "\u{00A0}", "\u{202F}"] {
            s = s.replacingOccurrences(of: separateur, with: "")
        }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.contains(","), !s.contains(".") {
            s = s.replacingOccurrences(of: ",", with: ".")
        }
        return Double(s)
    }
}
