import Foundation
import Observation

/// Mode équipe (lien d'ouvrier, v1.3) : chantiers du jour, pointage, envoi de la journée.
/// Jamais d'argent ni de décisions : le jeton d'ouvrier ne les ouvre pas, et l'app ne les demande pas.
@MainActor
@Observable
public final class ModeleEquipe {
    public private(set) var journee: JourneeEquipe?
    public private(set) var etat: EtatChargement = .initial
    public private(set) var feuille: FeuilleJournee
    /// Journée déjà envoyée au bureau (on peut encore la corriger et la renvoyer : même clé).
    public private(set) var envoyee = false

    @ObservationIgnored private let api: any EndryAPI
    @ObservationIgnored private let fichier: URL?

    public init(api: any EndryAPI, ouvrier: String, fichier: URL? = nil, le date: Date = Date()) {
        self.api = api
        self.fichier = fichier
        let jour = DateEndry.iso(date)
        if let fichier, let data = try? Data(contentsOf: fichier),
           let enregistree = try? JSONDecoder().decode(FeuilleEnregistree.self, from: data), enregistree.feuille.date == jour {
            feuille = enregistree.feuille
            envoyee = enregistree.envoyee
        } else {
            feuille = FeuilleJournee(date: jour, ouvrier: ouvrier)
        }
    }

    private struct FeuilleEnregistree: Codable {
        var feuille: FeuilleJournee
        var envoyee: Bool
    }

    public var chantiers: [ChantierEquipe] { journee?.chantiers ?? [] }
    public var enCours: Pointage? { feuille.enCours }

    public func charger() async {
        if journee == nil { etat = .chargement }
        do {
            journee = try await api.journeeEquipe()
            etat = .pret
        } catch {
            etat = journee == nil ? .erreur(error) : .pret
        }
    }

    public func commencer(_ chantier: ChantierEquipe, le date: Date = Date()) {
        feuille.commencer(chantier, le: date)
        sauver()
    }

    public func arreter(le date: Date = Date()) {
        feuille.arreter(le: date)
        sauver()
    }

    public var remarques: String {
        get { feuille.remarques }
        set { feuille.remarques = newValue; sauver() }
    }

    /// Corrige la durée d'un chantier (oubli de pointage) : un pointage unique de la durée voulue.
    public func corriger(chantierId: String, heures: Double) {
        guard let nom = feuille.pointages.first(where: { $0.chantierId == chantierId })?.chantier else { return }
        let debut = feuille.pointages.filter { $0.chantierId == chantierId }.map(\.debut).min() ?? Date()
        feuille.pointages.removeAll { $0.chantierId == chantierId }
        feuille.pointages.append(Pointage(chantierId: chantierId, chantier: nom, debut: debut,
                                          fin: debut.addingTimeInterval(max(0, heures) * 3600)))
        feuille.pointages.sort { $0.debut < $1.debut }
        sauver()
    }

    public func marquerEnvoyee() {
        envoyee = true
        sauver()
    }

    private func sauver() {
        guard let fichier, let data = try? JSONEncoder().encode(FeuilleEnregistree(feuille: feuille, envoyee: envoyee)) else { return }
        try? FileManager.default.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fichier, options: [.atomic])
    }
}
