import Foundation

/// Agents de Claude sur le PC. La question part vers Claude avec l'agent visé ; c'est le PC qui la confie
/// à cet agent (secrétariat, comptabilité…). Le contrat ne change pas : l'agent est écrit dans la saisie.
public enum AgentBureau: String, CaseIterable, Sendable, Hashable {
    case secretariat, comptabilite, chantiers, offres, achats

    public var nom: String {
        switch self {
        case .secretariat: "Secrétariat"
        case .comptabilite: "Comptabilité"
        case .chantiers: "Chantiers"
        case .offres: "Offres"
        case .achats: "Achats"
        }
    }

    public var icone: String {
        switch self {
        case .secretariat: "envelope.fill"
        case .comptabilite: "banknote.fill"
        case .chantiers: "hammer.fill"
        case .offres: "doc.richtext.fill"
        case .achats: "shippingbox.fill"
        }
    }

    /// Ce que couvre l'agent (repris dans les consignes des modèles vocaux).
    public var domaine: String {
        switch self {
        case .secretariat: "e-mails, courrier, téléphone, rendez-vous, agenda"
        case .comptabilite: "Bexio, factures, paiements, encaissements, TVA, salaires"
        case .chantiers: "dossiers de chantier, planning, équipes, avancement"
        case .offres: "offres, devis, soumissions, variantes"
        case .achats: "fournisseurs, commandes, livraisons, matériel"
        }
    }

    /// Mots qui désignent l'agent lui-même (« demande au secrétariat », « la compta »).
    var appellations: [String] {
        switch self {
        case .secretariat: ["secretariat", "secretaire"]
        case .comptabilite: ["compta", "comptabilite", "comptable"]
        case .chantiers: ["agent chantier", "agent chantiers", "conducteur de travaux"]
        case .offres: ["agent offre", "agent offres", "agent devis"]
        case .achats: ["agent achat", "agent achats", "achats"]
        }
    }

    /// Mots du domaine, quand l'agent n'est pas nommé.
    var motsCles: [String] {
        switch self {
        case .secretariat: ["mail", "mails", "courriel", "courriels", "courrier", "lettre", "telephone", "appel", "appele", "rappele",
                            "rendez", "agenda", "message", "messages"]
        case .comptabilite: ["bexio", "facture", "factures", "paiement", "paiements", "paye", "payer", "encaisse", "encaisser",
                             "banque", "tva", "salaire", "salaires", "versement"]
        case .chantiers: ["chantier", "chantiers", "planning", "equipe", "monteur", "monteurs", "avancement"]
        case .offres: ["offre", "offres", "devis", "soumission", "variante"]
        case .achats: ["fournisseur", "fournisseurs", "commande", "commandes", "livraison", "materiel", "stock"]
        }
    }

    public init?(nom: String) {
        let n = RepondeurLocal.normaliser(nom)
        guard !n.isEmpty, let agent = AgentBureau.allCases.first(where: { a in
            a.rawValue == n || RepondeurLocal.normaliser(a.nom) == n || a.appellations.contains(n) || n.hasPrefix(String(a.rawValue.prefix(5)))
        }) else { return nil }
        self = agent
    }

    /// Agent nommé dans la question, sinon celui dont le domaine revient le plus.
    public static func detecter(_ question: String) -> AgentBureau? {
        let q = " " + RepondeurLocal.normaliser(question) + " "
        if let nomme = allCases.first(where: { a in a.appellations.contains { q.contains(" \($0) ") } }) { return nomme }
        let mots = Set(q.split(separator: " ").map(String.init))
        let notes = allCases.map { a in (a, a.motsCles.filter { mots.contains($0) }.count) }
        guard let meilleur = notes.max(by: { $0.1 < $1.1 }), meilleur.1 > 0 else { return nil }
        return meilleur.0
    }

    /// Consigne pour les modèles vocaux : les agents et leurs domaines.
    public static var consigne: String {
        "Agents de Claude sur le PC : " + allCases.map { "\($0.nom) (\($0.domaine))" }.joined(separator: " ; ") + "."
    }
}
