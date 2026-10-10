import Foundation

/// Heures d'un intervenant sur une régie.
public struct LigneHeures: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var intervenant: String
    public var heures: Double

    public init(id: String = UUID().uuidString, intervenant: String, heures: Double) {
        self.id = id
        self.intervenant = intervenant
        self.heures = heures
    }
}

/// Matériel posé sur une régie (sans prix : c'est le bureau qui facture).
public struct LigneMateriel: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var designation: String
    public var quantite: Double
    public var unite: String

    public init(id: String = UUID().uuidString, designation: String, quantite: Double = 1, unite: String = "pce") {
        self.id = id
        self.designation = designation
        self.quantite = quantite
        self.unite = unite
    }

    /// « 2 pce raccord Mapress 22 », « 4 m tube multicouche 16 ».
    public var libelle: String {
        "\(FormatQuantite.texte(quantite)) \(unite) \(designation)"
    }
}

/// Bon de régie rempli sur le chantier et signé par le client.
/// Aucun prix : le client voit le travail, les heures et le matériel ; le bureau prépare la facture.
public struct BonRegie: Codable, Sendable, Hashable {
    public var numero: String
    public var chantierId: String?
    public var chantier: String
    public var client: String
    public var lieu: String?
    /// `AAAA-MM-JJ`
    public var date: String
    public var travaux: String
    public var heures: [LigneHeures]
    public var materiel: [LigneMateriel]
    public var deplacement: Bool
    public var remarques: String
    public var signataire: String?
    /// Horodatage de la signature (`AAAA-MM-JJTHH:MM:SS`, heure suisse).
    public var signeLe: String?

    public init(numero: String, chantierId: String? = nil, chantier: String, client: String, lieu: String? = nil, date: String,
                travaux: String = "", heures: [LigneHeures] = [], materiel: [LigneMateriel] = [], deplacement: Bool = true,
                remarques: String = "", signataire: String? = nil, signeLe: String? = nil) {
        self.numero = numero
        self.chantierId = chantierId
        self.chantier = chantier
        self.client = client
        self.lieu = lieu
        self.date = date
        self.travaux = travaux
        self.heures = heures
        self.materiel = materiel
        self.deplacement = deplacement
        self.remarques = remarques
        self.signataire = signataire
        self.signeLe = signeLe
    }

    /// Nouveau bon pour un chantier (numéro local unique : `RG-AAAAMMJJ-HHMM`).
    public static func nouveau(pour dossier: Dossier?, le date: Date = Date()) -> BonRegie {
        let jour = DateEndry.iso(date)
        return BonRegie(
            numero: "RG-\(jour.replacingOccurrences(of: "-", with: ""))-\(DateEndry.hhmm(date))",
            chantierId: dossier?.id, chantier: dossier?.titre ?? "", client: dossier?.client ?? "", lieu: dossier?.lieu, date: jour
        )
    }

    public var totalHeures: Double { heures.reduce(0) { $0 + max(0, $1.heures) } }
    public var estSigne: Bool { signeLe != nil && !(signataire ?? "").isEmpty }

    /// Ce qui manque avant de faire signer (vide : prêt).
    public var manques: [String] {
        var m: [String] = []
        if client.trimmingCharacters(in: .whitespaces).isEmpty && chantier.trimmingCharacters(in: .whitespaces).isEmpty {
            m.append("Choisissez le chantier ou le client.")
        }
        if travaux.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { m.append("Décrivez les travaux.") }
        if heures.isEmpty && materiel.isEmpty { m.append("Ajoutez des heures ou du matériel.") }
        if heures.contains(where: { $0.heures <= 0 || $0.heures > 24 }) { m.append("Vérifiez les heures (entre 0 et 24 h).") }
        return m
    }

    /// Signature du client : horodatée à l'instant du geste.
    public mutating func signer(par nom: String, le date: Date = Date()) {
        signataire = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        signeLe = DateEndry.horodatage(date)
    }

    /// Résumé en français, repris par l'assistant du PC pour préparer la facture.
    public var resume: String {
        var parties: [String] = []
        let ou = [client, lieu].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        parties.append("Régie \(numero) du \(DateEndry.courte(date)) — \(chantier.isEmpty ? client : chantier)\(ou.isEmpty ? "" : " (\(ou))").")
        if !travaux.isEmpty { parties.append("Travaux : \(travaux.trimmingCharacters(in: .whitespacesAndNewlines))") }
        if !heures.isEmpty {
            let detail = heures.map { "\($0.intervenant) \(FormatSuisse.heures($0.heures))" }.joined(separator: ", ")
            parties.append("Heures : \(detail) (total \(FormatSuisse.heures(totalHeures))).")
        }
        if !materiel.isEmpty { parties.append("Matériel : " + materiel.map(\.libelle).joined(separator: " ; ") + ".") }
        parties.append(deplacement ? "Déplacement : oui." : "Sans déplacement.")
        if !remarques.isEmpty { parties.append("Remarques : \(remarques)") }
        if estSigne, let signataire, let signeLe, let d = DateEndry.lire(signeLe) {
            parties.append("Signé sur place par \(signataire) le \(DateEndry.courte(d)) à \(DateEndry.heure(d)).")
        } else {
            parties.append("Non signé.")
        }
        parties.append("Préparer la facture de régie pour validation ; ne rien envoyer au client.")
        return parties.joined(separator: " ")
    }

    /// Envoi au bureau : données structurées, PDF signé et photos.
    public func envoi(pdf: Data?, signature: Data?, photos: [FormulaireMultipart.Fichier]) -> EnvoiTerrain {
        var fichiers: [FormulaireMultipart.Fichier] = []
        if let pdf { fichiers.append(.init(champ: "pieces", nomFichier: "\(numero).pdf", typeMIME: "application/pdf", donnees: pdf)) }
        if let signature {
            fichiers.append(.init(champ: "pieces", nomFichier: "\(numero)-signature.png", typeMIME: "image/png", donnees: signature))
        }
        fichiers += photos
        return EnvoiTerrain(type: .regie, chantierId: chantierId, resume: resume, donnees: EnvoiTerrain.json(self), fichiers: fichiers,
                            cle: numero)
    }
}

/// Quantités lisibles : `2` → « 2 », `2.5` → « 2,5 ».
public enum FormatQuantite {
    public static func texte(_ q: Double) -> String {
        if q == q.rounded() { return String(Int(q)) }
        return String(format: "%.2f", q)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: ".", with: ",")
    }
}
