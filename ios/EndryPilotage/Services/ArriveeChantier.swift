@preconcurrency import CoreLocation
import EndryKit
import Foundation
import UserNotifications

/// Rappel à l'arrivée sur un chantier : iOS surveille jusqu'à 20 zones (150 m autour des chantiers de la période).
/// En entrant dans une zone, une notification dit ce qui attend (décision, note, achats) et propose le bon de régie
/// ou le bon de livraison. La position ne quitte jamais l'iPhone ; aucun montant dans la notification.
@MainActor
final class ArriveeChantier {
    static let partage = ArriveeChantier()
    static let cleActif = "rappel-arrivee-actif"
    private static let cleCoordonnees = "zones-chantiers-coordonnees"
    private static let cleRappels = "zones-chantiers-rappels"
    nonisolated private static let cleDerniers = "zones-chantiers-derniers"
    private static let nomMoniteur = "endry-chantiers"

    private var moniteur: CLMonitor?
    private var ecoute: Task<Void, Never>?
    private var sessionService: CLServiceSession?
    private let gestionnaire = CLLocationManager()

    var actif: Bool { UserDefaults.standard.bool(forKey: Self.cleActif) }

    /// Chantier où le patron est arrivé ces dernières heures (pour pré-remplir un bon de régie ou de livraison).
    nonisolated static func chantierRecent(depuis heures: Double = 6) -> String? {
        let derniers = UserDefaults.standard.dictionary(forKey: cleDerniers) as? [String: Double] ?? [:]
        let limite = Date().timeIntervalSince1970 - heures * 3600
        return derniers.filter { $0.value >= limite }.max { $0.value < $1.value }?.key
    }

    var autorisationRefusee: Bool {
        [.denied, .restricted].contains(gestionnaire.authorizationStatus)
    }

    /// Active la surveillance : autorisation « Toujours » (iOS la demande en deux temps) et notifications.
    func activer() async {
        UserDefaults.standard.set(true, forKey: Self.cleActif)
        _ = await DelegueApp.demanderAutorisation()
        sessionService = CLServiceSession(authorization: .always)
        gestionnaire.requestAlwaysAuthorization()
        await demarrer()
    }

    func desactiver() async {
        UserDefaults.standard.set(false, forKey: Self.cleActif)
        ecoute?.cancel()
        ecoute = nil
        if let moniteur {
            for id in await moniteur.identifiers { await moniteur.remove(id) }
        }
        sessionService = nil
    }

    /// Au lancement (y compris en arrière-plan pour un événement de zone) : reprendre l'écoute.
    func reprendre() {
        guard actif else { return }
        Task { await demarrer() }
    }

    private func demarrer() async {
        guard ecoute == nil else { return }
        if sessionService == nil { sessionService = CLServiceSession(authorization: .always) }
        let m = await CLMonitor(Self.nomMoniteur)
        moniteur = m
        ecoute = Task { [weak self] in
            do {
                for try await evenement in await m.events where evenement.state == .satisfied {
                    await self?.entree(dans: evenement.identifier)
                }
            } catch {
                // Surveillance interrompue : reprise au prochain lancement.
            }
        }
    }

    /// Zones à jour : chantiers de la période, géocodés une fois (cache), rappels recalculés sans montants.
    func mettreAJour(app: ModeleApp) async {
        guard actif, let chantiers = app.chantiers?.tous, !chantiers.isEmpty else { return }
        await demarrer()
        guard let moniteur else { return }
        let zones = RappelsChantier.zones(chantiers: chantiers, semaine: app.chantiers?.semaine ?? [])
        var coordonnees = UserDefaults.standard.dictionary(forKey: Self.cleCoordonnees) as? [String: [Double]] ?? [:]
        var rappels: [String: [String]] = [:]
        let decisions = app.decisions?.cartes ?? []
        let achats = app.argent?.argent?.aRefacturer.achats ?? []
        for d in zones {
            let adresse = RappelsChantier.adresse(d)
            if coordonnees[adresse] == nil, let c = await Self.geocoder(adresse) {
                coordonnees[adresse] = [c.latitude, c.longitude]
            }
            let r = RappelsChantier.rappel(pour: d, decisions: decisions, achats: achats)
            rappels[d.id] = [r.titre, r.corps]
        }
        UserDefaults.standard.set(coordonnees, forKey: Self.cleCoordonnees)
        UserDefaults.standard.set(rappels, forKey: Self.cleRappels)

        let voulus = Set(zones.map(\.id))
        for id in await moniteur.identifiers where !voulus.contains(id) { await moniteur.remove(id) }
        let existants = Set(await moniteur.identifiers)
        for d in zones where !existants.contains(d.id) {
            guard let c = coordonnees[RappelsChantier.adresse(d)], c.count == 2 else { continue }
            let centre = CLLocationCoordinate2D(latitude: c[0], longitude: c[1])
            let condition = CLMonitor.CircularGeographicCondition(center: centre, radius: RappelsChantier.rayon)
            await moniteur.add(condition, identifier: d.id, assuming: .unsatisfied)
        }
    }

    private func entree(dans chantierId: String) async {
        // Une seule fois par chantier et par demi-journée.
        var derniers = UserDefaults.standard.dictionary(forKey: Self.cleDerniers) as? [String: Double] ?? [:]
        if let dernier = derniers[chantierId], Date().timeIntervalSince1970 - dernier < 6 * 3600 { return }
        derniers[chantierId] = Date().timeIntervalSince1970
        UserDefaults.standard.set(derniers, forKey: Self.cleDerniers)
        let rappel = (UserDefaults.standard.dictionary(forKey: Self.cleRappels) as? [String: [String]])?[chantierId]
        await NotificationLocale.programmer(.arrivee(chantierId: chantierId), identifiant: "arrivee-\(chantierId)",
                                            titre: rappel?.first ?? "Arrivée sur le chantier",
                                            corps: rappel?.last ?? "Touchez pour le dossier, un bon de régie ou une photo.",
                                            categorie: NotificationLocale.categorieArrivee, declencheur: nil, fil: "chantier-\(chantierId)")
    }

    private static func geocoder(_ adresse: String) async -> CLLocationCoordinate2D? {
        let geocodeur = CLGeocoder()
        let marques = try? await geocodeur.geocodeAddressString(adresse)
        return marques?.first?.location?.coordinate
    }
}
