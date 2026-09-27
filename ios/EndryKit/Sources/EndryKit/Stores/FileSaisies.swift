import Foundation

/// Saisie terrain mise en file : texte + pièces, persistée tant qu'elle n'est pas transmise.
public struct SaisieEnAttente: Codable, Sendable, Identifiable, Equatable {
    public struct Fichier: Codable, Sendable, Equatable {
        public var nom: String
        public var typeMIME: String
        /// Nom du fichier sur disque, dans le dossier de la saisie.
        public var chemin: String
    }

    public var id: String
    public var cree: Date
    public var texte: String
    public var fichiers: [Fichier]
    public var tentatives: Int
}

/// File persistante des saisies : dictées et photos survivent à la perte de réseau et au redémarrage,
/// et partent dès que le serveur répond. Fichiers protégés par iOS, exclus des sauvegardes.
public actor FileSaisies {
    private let dossier: URL?
    private var enMemoire: [SaisieEnAttente] = []
    private var donneesEnMemoire: [String: Data] = [:]

    /// `dossier == nil` : file en mémoire (tests, démo).
    public init(dossier: URL?) {
        self.dossier = dossier
        enMemoire = Self.lireIndex(dossier)
    }

    public static func parDefaut() -> FileSaisies {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return FileSaisies(dossier: base?.appendingPathComponent("file-saisies", isDirectory: true))
    }

    public var saisies: [SaisieEnAttente] { enMemoire }
    public var nombre: Int { enMemoire.count }

    /// Ajoute une saisie à la file et l'écrit sur disque.
    @discardableResult
    public func ajouter(texte: String, fichiers: [FormulaireMultipart.Fichier], le date: Date = Date()) -> SaisieEnAttente {
        let id = UUID().uuidString
        var decrits: [SaisieEnAttente.Fichier] = []
        for (i, f) in fichiers.enumerated() {
            let chemin = "\(id)-\(i)"
            ecrire(f.donnees, sous: chemin)
            decrits.append(.init(nom: f.nomFichier, typeMIME: f.typeMIME, chemin: chemin))
        }
        let saisie = SaisieEnAttente(id: id, cree: date, texte: texte, fichiers: decrits, tentatives: 0)
        enMemoire.append(saisie)
        sauverIndex()
        return saisie
    }

    /// Envoie les saisies en attente, dans l'ordre. S'arrête à la première panne réseau.
    /// Retourne le nombre de saisies transmises.
    @discardableResult
    public func vider(avec api: any EndryAPI) async -> Int {
        var transmises = 0
        while let saisie = enMemoire.first {
            let fichiers = saisie.fichiers.compactMap { f -> FormulaireMultipart.Fichier? in
                guard let data = lire(f.chemin) else { return nil }
                return .init(champ: "photos", nomFichier: f.nom, typeMIME: f.typeMIME, donnees: data)
            }
            do {
                _ = try await api.saisie(texte: saisie.texte, fichiers: fichiers)
                retirer(saisie)
                transmises += 1
            } catch {
                if error.estProblemeReseau { break }
                // Refus du serveur : on garde la saisie, marquée, et on passe à la suivante au prochain essai.
                if let i = enMemoire.firstIndex(where: { $0.id == saisie.id }) {
                    enMemoire[i].tentatives += 1
                    if enMemoire[i].tentatives >= 5 {
                        retirer(saisie)
                    } else {
                        sauverIndex()
                    }
                }
                break
            }
        }
        return transmises
    }

    public func effacer() {
        enMemoire.removeAll()
        donneesEnMemoire.removeAll()
        if let dossier { try? FileManager.default.removeItem(at: dossier) }
    }

    // MARK: - Disque

    private func retirer(_ saisie: SaisieEnAttente) {
        for f in saisie.fichiers {
            donneesEnMemoire[f.chemin] = nil
            if let url = dossier?.appendingPathComponent(f.chemin) { try? FileManager.default.removeItem(at: url) }
        }
        enMemoire.removeAll { $0.id == saisie.id }
        sauverIndex()
    }

    private func ecrire(_ data: Data, sous chemin: String) {
        guard let dossier else { donneesEnMemoire[chemin] = data; return }
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let url = dossier.appendingPathComponent(chemin)
        #if os(iOS)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: url, options: [.atomic])
        #endif
        var valeurs = URLResourceValues()
        valeurs.isExcludedFromBackup = true
        var d = dossier
        try? d.setResourceValues(valeurs)
    }

    private func lire(_ chemin: String) -> Data? {
        guard let dossier else { return donneesEnMemoire[chemin] }
        return try? Data(contentsOf: dossier.appendingPathComponent(chemin))
    }

    private func sauverIndex() {
        guard let dossier, let data = try? JSONEncoder().encode(enMemoire) else { return }
        ecrire(data, sous: "index.json")
        _ = dossier
    }

    private static func lireIndex(_ dossier: URL?) -> [SaisieEnAttente] {
        guard let url = dossier?.appendingPathComponent("index.json"), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SaisieEnAttente].self, from: data)) ?? []
    }
}
