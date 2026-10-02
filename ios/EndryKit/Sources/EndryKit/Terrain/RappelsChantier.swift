import Foundation

/// Rappel à l'arrivée sur un chantier : seule la position de l'iPhone sert, elle ne quitte jamais l'appareil.
public struct RappelArrivee: Sendable, Hashable {
    public var chantierId: String
    public var titre: String
    public var corps: String
    public var elements: [String]
}

public enum RappelsChantier {
    /// iOS surveille 20 zones au plus par app.
    public static let maxZones = 20
    /// Rayon autour du chantier (mètres).
    public static let rayon: Double = 150

    private static let etapesActives: Set<String> = ["planifie", "en_cours", "commande", "realise", "accepte"]

    /// Chantiers à surveiller : ceux de la période (−3 j … +14 j) d'abord, puis les chantiers actifs ; avec un lieu.
    public static func zones(chantiers: [Dossier], semaine: [Semaine] = [], le date: Date = Date(), max: Int = maxZones) -> [Dossier] {
        let avecLieu = chantiers.filter { !($0.lieu ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        let idsSemaine = Set(semaine.map(\.id))
        func distance(_ d: Dossier) -> Int {
            if idsSemaine.contains(d.id) { return -1 }
            guard let debut = d.debut else { return etapesActives.contains(d.etape) ? 60 : 1_000 }
            let fin = d.fin ?? debut
            if DateEndry.jours(de: debut, a: date) >= 0 && DateEndry.jours(de: date, a: fin) >= 0 { return 0 }
            let ecart = min(abs(DateEndry.jours(de: date, a: debut)), abs(DateEndry.jours(de: date, a: fin)))
            return ecart
        }
        return avecLieu
            .map { ($0, distance($0)) }
            .filter { d, ecart in ecart <= 14 || (ecart < 1_000 && etapesActives.contains(d.etape)) }
            .sorted { $0.1 < $1.1 }
            .prefix(max)
            .map(\.0)
    }

    /// Adresse à géocoder : le lieu du chantier, en Suisse.
    public static func adresse(_ d: Dossier) -> String {
        "\(d.lieu ?? d.titre), Suisse"
    }

    /// Ce qui attend sur ce chantier (sans aucun montant : la notification peut s'afficher devant le client).
    public static func rappel(pour d: Dossier, decisions: [Carte], achats: [AchatARefacturer], le date: Date = Date()) -> RappelArrivee {
        var elements: [String] = []
        let aPrendre = decisions.filter { $0.chantierId == d.id }.count
        if aPrendre > 0 { elements.append(aPrendre == 1 ? "1 décision à prendre" : "\(aPrendre) décisions à prendre") }
        else if d.decisionEnAttente { elements.append("une décision attend au bureau") }
        let materiel = achats.filter { $0.dossierId == d.id }.count
        if materiel > 0 { elements.append(materiel == 1 ? "1 achat à refacturer" : "\(materiel) achats à refacturer") }
        if let note = d.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            elements.append("note : \(note)")
        }
        let titre = "\(d.client.isEmpty ? d.titre : d.client)\(d.lieu.map { " — \($0)" } ?? "")"
        let corps: String
        switch elements.count {
        case 0: corps = "Rien en attente. Touchez pour le dossier, un bon de régie ou une photo."
        case 1: corps = "Une chose vous attend : \(elements[0])."
        default: corps = "\(elements.count) choses vous attendent : " + elements.joined(separator: " ; ") + "."
        }
        return RappelArrivee(chantierId: d.id, titre: titre, corps: corps, elements: elements)
    }
}
