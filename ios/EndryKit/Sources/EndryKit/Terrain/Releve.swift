import Foundation

/// Relevé d'une pièce (RoomPlan sur iPhone Pro, capteur LiDAR) : murs, ouvertures, sol, équipements.
/// Les dimensions sont en mètres. Le fichier 3D (USDZ) et le plan 2D partent avec.
public struct ReleveMesures: Codable, Sendable, Hashable {
    public struct Mur: Codable, Sendable, Hashable {
        public var largeur: Double
        public var hauteur: Double
        public init(largeur: Double, hauteur: Double) { self.largeur = largeur; self.hauteur = hauteur }
    }

    public enum TypeOuverture: String, Codable, Sendable { case porte, fenetre, ouverture }

    public struct Ouverture: Codable, Sendable, Hashable {
        public var type: TypeOuverture
        public var largeur: Double
        public var hauteur: Double
        public init(type: TypeOuverture, largeur: Double, hauteur: Double) {
            self.type = type
            self.largeur = largeur
            self.hauteur = hauteur
        }
    }

    public struct Point: Codable, Sendable, Hashable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public struct Objet: Codable, Sendable, Hashable {
        /// Catégorie RoomPlan (`toilet`, `bathtub`, `sink`…).
        public var categorie: String
        public var largeur: Double
        public var profondeur: Double
        public var hauteur: Double
        public init(categorie: String, largeur: Double, profondeur: Double, hauteur: Double) {
            self.categorie = categorie
            self.largeur = largeur
            self.profondeur = profondeur
            self.hauteur = hauteur
        }

        public var nom: String { ReleveMesures.nomObjet(categorie) }
    }

    public var piece: String
    public var chantierId: String?
    public var chantier: String?
    /// `AAAA-MM-JJ`
    public var date: String
    public var murs: [Mur]
    public var ouvertures: [Ouverture]
    /// Contour du sol vu de dessus (sens quelconque), s'il est connu.
    public var contourSol: [Point]
    public var objets: [Objet]
    public var remarques: String
    /// Prénom de l'ouvrier qui a fait le relevé (lien d'équipe) ; absent quand c'est le patron.
    public var relevePar: String?

    public init(piece: String, chantierId: String? = nil, chantier: String? = nil, date: String, murs: [Mur] = [],
                ouvertures: [Ouverture] = [], contourSol: [Point] = [], objets: [Objet] = [], remarques: String = "",
                relevePar: String? = nil) {
        self.piece = piece
        self.chantierId = chantierId
        self.chantier = chantier
        self.date = date
        self.murs = murs
        self.ouvertures = ouvertures
        self.contourSol = contourSol
        self.objets = objets
        self.remarques = remarques
        self.relevePar = relevePar
    }

    public var perimetre: Double { murs.reduce(0) { $0 + $1.largeur } }
    public var hauteur: Double? { murs.map(\.hauteur).max() }

    /// Surface du sol : contour (formule du lacet), sinon rectangle des deux plus longs murs perpendiculaires.
    public var surfaceSol: Double? {
        if contourSol.count >= 3 {
            var s = 0.0
            for i in contourSol.indices {
                let a = contourSol[i], b = contourSol[(i + 1) % contourSol.count]
                s += a.x * b.y - b.x * a.y
            }
            return abs(s) / 2
        }
        let tries = murs.map(\.largeur).sorted(by: >)
        guard murs.count == 4, tries.count == 4 else { return nil }
        return tries[0] * tries[2]
    }

    /// Surface des murs, ouvertures déduites (carrelage, peinture).
    public var surfaceMursNette: Double {
        let brute = murs.reduce(0) { $0 + $1.largeur * $1.hauteur }
        let trous = ouvertures.reduce(0) { $0 + $1.largeur * $1.hauteur }
        return max(0, brute - trous)
    }

    /// Équipements groupés : « 1 WC, 1 baignoire, 2 lavabos ».
    public var equipements: [(nom: String, nombre: Int)] {
        var ordre: [String] = []
        var n: [String: Int] = [:]
        for o in objets {
            let nom = o.nom
            if n[nom] == nil { ordre.append(nom) }
            n[nom, default: 0] += 1
        }
        return ordre.map { ($0, n[$0] ?? 0) }
    }

    public var resume: String {
        var p = ["Relevé 3D — \(piece)\(chantier.map { ", chantier \($0)" } ?? "") (\(DateEndry.courte(date)))."]
        var mesures: [String] = []
        if let s = surfaceSol { mesures.append("sol \(Self.m2(s))") }
        if perimetre > 0 { mesures.append("périmètre \(Self.m(perimetre))") }
        if let h = hauteur { mesures.append("hauteur \(Self.m(h))") }
        if !murs.isEmpty { mesures.append("murs \(Self.m2(surfaceMursNette)) nets") }
        if !mesures.isEmpty { p.append(mesures.joined(separator: ", ").prefix(1).uppercased() + mesures.joined(separator: ", ").dropFirst() + ".") }
        let portes = ouvertures.filter { $0.type == .porte }.count
        let fenetres = ouvertures.filter { $0.type == .fenetre }.count
        if portes + fenetres > 0 {
            p.append("Ouvertures : \(portes) porte\(portes > 1 ? "s" : ""), \(fenetres) fenêtre\(fenetres > 1 ? "s" : "").")
        }
        if !equipements.isEmpty {
            p.append("Équipements : " + equipements.map { "\($0.nombre) \($0.nombre > 1 ? Self.pluriel($0.nom) : $0.nom)" }.joined(separator: ", ") + ".")
        }
        if !remarques.isEmpty { p.append("Remarques : \(remarques)") }
        if let relevePar {
            p.append("Relevé par \(relevePar) (équipe). Plan et fichier 3D joints. Préparer l’offre à partir de ces mesures ; rien ne part au client sans l’accord du patron.")
        } else {
            p.append("Plan et fichier 3D joints. Préparer l’offre à partir de ces mesures ; ne rien envoyer au client sans mon accord.")
        }
        return p.joined(separator: " ")
    }

    public func envoi(usdz: Data?, plan: Data?, photos: [FormulaireMultipart.Fichier] = [], cle: String = UUID().uuidString) -> EnvoiTerrain {
        var fichiers: [FormulaireMultipart.Fichier] = []
        let base = "releve-\(date)-\(piece.lowercased().replacingOccurrences(of: " ", with: "-"))"
        if let plan { fichiers.append(.init(champ: "pieces", nomFichier: "\(base)-plan.png", typeMIME: "image/png", donnees: plan)) }
        if let usdz { fichiers.append(.init(champ: "pieces", nomFichier: "\(base).usdz", typeMIME: "model/vnd.usdz+zip", donnees: usdz)) }
        fichiers += photos
        return EnvoiTerrain(type: .releve, chantierId: chantierId, resume: resume, donnees: EnvoiTerrain.json(self), fichiers: fichiers, cle: cle)
    }

    // MARK: - Libellés

    public static func nomObjet(_ categorie: String) -> String {
        switch categorie.lowercased() {
        case "toilet": "WC"
        case "bathtub": "baignoire"
        case "sink": "lavabo"
        case "washerdryer": "lave-linge"
        case "dishwasher": "lave-vaisselle"
        case "stove", "oven": "cuisinière"
        case "refrigerator": "frigo"
        case "fireplace": "cheminée"
        case "stairs": "escalier"
        case "storage": "meuble"
        case "table": "table"
        case "bed": "lit"
        case "sofa": "canapé"
        case "chair": "chaise"
        case "television": "télévision"
        default: categorie
        }
    }

    static func pluriel(_ nom: String) -> String {
        switch nom {
        case "WC", "frigo": nom
        case "lave-linge", "lave-vaisselle": nom
        default: nom.hasSuffix("s") ? nom : nom + "s"
        }
    }

    public static func m(_ v: Double) -> String { String(format: "%.2f m", v).replacingOccurrences(of: ".", with: ",") }
    public static func m2(_ v: Double) -> String { String(format: "%.2f m²", v).replacingOccurrences(of: ".", with: ",") }
}
