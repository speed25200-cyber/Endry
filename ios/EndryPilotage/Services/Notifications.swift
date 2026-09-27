import EndryKit
import UIKit
import UserNotifications

/// Notifications push : autorisation, enregistrement du jeton APNs auprès du PC, ouverture de la bonne carte.
///
/// Charge utile attendue côté PC (v1.1) :
/// `{"aps": {"alert": {...}, "badge": n, "thread-id": "<chantier>", "category": "DECISION"}, "reference": "V-XXXX"}`.
/// Catégories : DECISION (Voir, Oui), DECISION_ENVOI (Voir : l'envoi à un tiers exige le geste dans l'app),
/// SAISIE_TRAITEE (Voir), INFO.
final class DelegueApp: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Appelés sur le MainActor par l'app (branchés dans `EndryPilotageApp`).
    var surJetonAPNs: (@MainActor (String) -> Void)?
    var surReference: (@MainActor (String) -> Void)?
    /// Une notification arrive app ouverte : les écrans se rechargent.
    var surNotificationRecue: (@MainActor () -> Void)?
    /// Action « Oui » d'une notification DECISION.
    var surOui: (@MainActor (String) -> Void)?
    /// Saisie traitée sans décision liée : ouvrir l'historique des saisies.
    var surSaisieTraitee: (@MainActor () -> Void)?
    /// Notification locale touchée (briefing du matin, arrivée sur un chantier), avec l'action choisie.
    var surLocale: (@MainActor (NotificationLocale, String) -> Void)?
    private var localeEnAttente: (NotificationLocale, String)?
    private var referenceEnAttente: String?

    static let actionVoir = "VOIR"
    static let actionOui = "OUI"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Self.enregistrerCategories()
        // Tâche de fond du briefing (avant la fin du lancement) ; surveillance des chantiers relancée.
        BriefingMatin.enregistrerTache()
        ArriveeChantier.partage.reprendre()
        return true
    }

    /// Catégories et actions affichées sur la notification (appui long ou balayage).
    static func enregistrerCategories() {
        let voir = UNNotificationAction(identifier: actionVoir, title: "Voir", options: [.foreground])
        // « Oui » exige un iPhone déverrouillé ; jamais proposé pour un envoi à un tiers.
        let oui = UNNotificationAction(identifier: actionOui, title: "Oui", options: [.authenticationRequired])
        let categories = Set<UNNotificationCategory>([
            UNNotificationCategory(identifier: CategorieNotification.decision.rawValue, actions: [voir, oui], intentIdentifiers: []),
            UNNotificationCategory(identifier: CategorieNotification.decisionEnvoi.rawValue, actions: [voir], intentIdentifiers: []),
            UNNotificationCategory(identifier: CategorieNotification.saisieTraitee.rawValue, actions: [voir], intentIdentifiers: []),
            UNNotificationCategory(identifier: CategorieNotification.info.rawValue, actions: [], intentIdentifiers: []),
        ]).union(NotificationLocale.categories)
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        surJetonAPNs?(hex)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulateur ou capacité Push absente du profil : rien à faire, l'app fonctionne sans.
    }

    /// Notification reçue app ouverte : bannière discrète.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { surNotificationRecue?() }
        return [.banner, .list, .badge]
    }

    /// Toucher la notification (ou « Voir ») : ouvrir la carte. « Oui » : accepter sans ouvrir l'app,
    /// seulement pour une décision DECISION (rien ne part chez un tiers).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let infos = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        if let locale = NotificationLocale(userInfo: infos) {
            await MainActor.run {
                if let surLocale { surLocale(locale, action) } else { localeEnAttente = (locale, action) }
            }
            return
        }
        let charge = ChargeNotification(userInfo: infos)
        await MainActor.run {
            if action == Self.actionOui, charge.ouiAutorise, let reference = charge.reference, let surOui {
                surOui(reference)
                return
            }
            guard let reference = charge.reference else {
                if charge.categorie == .saisieTraitee { surSaisieTraitee?() }
                return
            }
            if let surReference { surReference(reference) } else { referenceEnAttente = reference }
        }
    }

    func consommerLocaleEnAttente() -> (NotificationLocale, String)? {
        defer { localeEnAttente = nil }
        return localeEnAttente
    }

    func consommerReferenceEnAttente() -> String? {
        defer { referenceEnAttente = nil }
        return referenceEnAttente
    }

    /// Demande l'autorisation puis l'enregistrement APNs.
    static func demanderAutorisation() async -> Bool {
        let accorde = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if accorde { UIApplication.shared.registerForRemoteNotifications() }
        return accorde
    }

    static func autorisationDejaAccordee() async -> Bool {
        let reglages = await UNUserNotificationCenter.current().notificationSettings()
        return reglages.authorizationStatus == .authorized || reglages.authorizationStatus == .provisional
    }

    static func mettreAJourBadge(_ nombre: Int) {
        UNUserNotificationCenter.current().setBadgeCount(nombre)
    }
}
