import Foundation

/// Vocabulaire métier injecté dans la reconnaissance (temps réel et locale).
///
/// La dictée d'Apple (`DictationTranscriber`, iOS 26 et suivants) accepte au plus 100 expressions courtes :
/// les termes du métier d'abord, puis les noms du moment (chantiers de la semaine, clients, fournisseurs, lieux).
public enum VocabulaireMetier {
    public static let termes: [String] = [
        "Endry", "SN 592000", "Mapress", "Sanipex", "Geberit", "Buderus", "Meier Tobler", "Debrunner Acifer", "Hoval", "Viessmann",
        "boiler", "nourrice", "vase d’expansion", "chauffage au sol", "régie", "débouchage", "TVA", "Bexio", "Zoho",
        "secrétariat", "comptabilité", "offre", "acompte", "métré",
        "Bussy", "Estavayer", "Epalinges", "Neuchâtel", "Moudon", "Payerne", "Romont", "Lausanne",
    ]

    /// Limite d'Apple pour l'ensemble des expressions.
    public static let limite = 100

    /// Termes du métier, puis `noms` dans l'ordre donné : nettoyés, sans doublons, `limite` au plus.
    public static func pour(noms: [String]) -> [String] {
        var vus = Set<String>()
        var resultat: [String] = []
        for brut in termes + noms {
            guard resultat.count < limite, let terme = nettoyer(brut) else { continue }
            let cle = terme.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CH"))
            if vus.insert(cle).inserted { resultat.append(terme) }
        }
        return resultat
    }

    /// Noms utiles à reconnaître, les plus probables d'abord : chantiers de la semaine, chantiers, clients à encaisser,
    /// fournisseurs. Les montants ne servent jamais : seuls les noms entrent dans la reconnaissance.
    public static func noms(semaine: [Semaine], chantiers: [Dossier], argent: Argent?) -> [String] {
        var noms: [String] = []
        for s in semaine { noms += [s.client, s.lieu].compactMap { $0 } }
        for d in chantiers { noms += [d.client, d.lieu].compactMap { $0 } }
        if let argent {
            noms += argent.encaisser.factures.map(\.client)
            noms += argent.offres.offres.map(\.client)
            noms += argent.payer.factures.map(\.fournisseur)
            noms += argent.aRefacturer.achats.compactMap(\.fournisseur)
        }
        return noms
    }

    /// Une expression courte (quatre mots au plus), sans ponctuation de liste ; `nil` si inutilisable.
    static func nettoyer(_ brut: String) -> String? {
        let terme = brut
            .components(separatedBy: CharacterSet(charactersIn: ",;/()\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard terme.count >= 2, terme.count <= 40 else { return nil }
        guard terme.split(separator: " ").count <= 4 else { return nil }
        guard terme.contains(where: \.isLetter) else { return nil }
        return terme
    }
}

/// Vocabulaire courant, partagé entre l'app (qui connaît les données) et les transcripteurs.
public final class VocabulaireVocal: @unchecked Sendable {
    public static let partage = VocabulaireVocal()

    private let verrou = NSLock()
    private var courant = VocabulaireMetier.pour(noms: [])

    public init() {}

    public var termes: [String] {
        verrou.withLock { courant }
    }

    public func mettreAJour(noms: [String]) {
        let termes = VocabulaireMetier.pour(noms: noms)
        verrou.withLock { courant = termes }
    }
}
