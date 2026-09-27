import EndryKit
import UIKit
import UserNotifications

/// Notifications push : autorisation, enregistrement du jeton APNs auprès du PC, ouverture de la bonne carte.
///
/// Charge utile attendue côté PC : `{"aps": {"alert": {...}, "badge": n}, "reference": "V-XXXX"}`.
final class DelegueApp: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Appelés sur le MainActor par l'app (branchés dans `EndryPilotageApp`).
    var surJetonAPNs: (@MainActor (String) -> Void)?
    var surReference: (@MainActor (String) -> Void)?
    /// Une notification arrive app ouverte : les écrans se rechargent.
    var surNotificationRecue: (@MainActor () -> Void)?
    private var referenceEnAttente: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
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

    /// Toucher la notification : ouvrir la carte correspondante.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let reference = response.notification.request.content.userInfo["reference"] as? String
        await MainActor.run {
            guard let reference else { return }
            if let surReference { surReference(reference) } else { referenceEnAttente = reference }
        }
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
