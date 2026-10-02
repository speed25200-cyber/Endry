import EndryKit
import Foundation
import UserNotifications

/// Notifications produites par l'iPhone lui-même (aucun serveur) : briefing du matin, arrivée sur un chantier.
enum NotificationLocale: Equatable, Sendable {
    case briefing
    case arrivee(chantierId: String)

    static let cle = "endry_locale"
    static let cleChantier = "chantier_id"
    static let categorieBriefing = "BRIEFING"
    static let categorieArrivee = "ARRIVEE_CHANTIER"
    static let actionEcouter = "ECOUTER"
    static let actionRegie = "REGIE"
    static let actionBon = "BON_LIVRAISON"
    static let actionPhoto = "PHOTO"

    init?(userInfo: [AnyHashable: Any]) {
        switch userInfo[Self.cle] as? String {
        case "briefing": self = .briefing
        case "arrivee":
            guard let id = userInfo[Self.cleChantier] as? String else { return nil }
            self = .arrivee(chantierId: id)
        default: return nil
        }
    }

    var userInfo: [String: String] {
        switch self {
        case .briefing: [Self.cle: "briefing"]
        case .arrivee(let id): [Self.cle: "arrivee", Self.cleChantier: id]
        }
    }

    static var categories: Set<UNNotificationCategory> {
        let ecouter = UNNotificationAction(identifier: actionEcouter, title: "Écouter", options: [.foreground, .authenticationRequired],
                                           icon: UNNotificationActionIcon(systemImageName: "play.fill"))
        let regie = UNNotificationAction(identifier: actionRegie, title: "Bon de régie", options: [.foreground, .authenticationRequired],
                                         icon: UNNotificationActionIcon(systemImageName: "signature"))
        let bon = UNNotificationAction(identifier: actionBon, title: "Bon de livraison", options: [.foreground, .authenticationRequired],
                                       icon: UNNotificationActionIcon(systemImageName: "shippingbox"))
        return [
            UNNotificationCategory(identifier: categorieBriefing, actions: [ecouter], intentIdentifiers: []),
            UNNotificationCategory(identifier: categorieArrivee, actions: [regie, bon], intentIdentifiers: []),
        ]
    }

    /// Programme (ou remplace) une notification locale.
    static func programmer(_ type: NotificationLocale, identifiant: String, titre: String, corps: String, categorie: String,
                           declencheur: UNNotificationTrigger?, fil: String) async {
        let contenu = UNMutableNotificationContent()
        contenu.title = titre
        contenu.body = corps
        contenu.categoryIdentifier = categorie
        contenu.threadIdentifier = fil
        contenu.userInfo = type.userInfo
        contenu.sound = .default
        contenu.interruptionLevel = .active
        let requete = UNNotificationRequest(identifier: identifiant, content: contenu, trigger: declencheur)
        try? await UNUserNotificationCenter.current().add(requete)
    }
}
