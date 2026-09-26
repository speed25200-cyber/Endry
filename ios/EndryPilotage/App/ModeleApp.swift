import EndryKit
import Foundation
import Observation
import UIKit
import WidgetKit

/// État global : session, écrans, navigation, notifications. Toutes les données viennent de l'API.
@MainActor
@Observable
final class ModeleApp {
    let session: ModeleSession
    let verrou = Verrou()
    let documents = Documents()

    var onglet: Onglet = .decisions
    /// Carte à mettre en avant (toucher d'une notification).
    var referenceCiblee: String?
    /// Présente l'écran de connexion par-dessus l'app (nouveau lien).
    var connexionPresentee = false
    var reglagesPresentes = false
    var toast: Toast?

    private(set) var decisions: ModeleDecisions?
    private(set) var chantiers: ModeleChantiers?
    private(set) var argent: ModeleArgent?
    private(set) var saisie: ModeleSaisie?

    @ObservationIgnored private var jetonAPNsEnAttente: String?
    @ObservationIgnored private var dernierJetonEnvoye: String?

    init(session: ModeleSession? = nil) {
        if let session {
            self.session = session
        } else {
            #if canImport(Security)
            let coffre = CoffreTrousseau(groupe: Configuration.groupeTrousseau)
            #else
            let coffre = CoffreMemoire()
            #endif
            self.session = ModeleSession(coffre: coffre, cache: .parDefaut(), groupeWidget: Configuration.groupeApps)
        }
        if Configuration.lancementDemo {
            self.session.activerDemo(latence: Configuration.testsUI ? .milliseconds(80) : .milliseconds(450))
            verrou.actif = false
        }
        reconstruire()
    }

    /// Recrée les modèles d'écran quand le client API change (connexion, démo, déconnexion).
    func reconstruire() {
        guard let api = session.api else {
            decisions = nil
            chantiers = nil
            argent = nil
            saisie = nil
            return
        }
        let cache = session.estDemo ? nil : session.cache
        let rapport: RapportErreur = { [weak self] erreur in self?.session.signaler(erreur) }
        let d = ModeleDecisions(api: api, cache: cache, rapport: rapport)
        d.surAccueil = { [weak self] accueil in self?.publier(accueil) }
        decisions = d
        chantiers = ModeleChantiers(api: api, cache: cache, rapport: rapport)
        argent = ModeleArgent(api: api, cache: cache, rapport: rapport)
        saisie = ModeleSaisie(api: api, rapport: rapport)
        dernierJetonEnvoye = nil
        if let jeton = jetonAPNsEnAttente { enregistrerAppareil(jeton) }
    }

    func connecter(texte: String) async throws(ErreurConnexion) {
        try await session.connecter(texte: texte)
        verrou.marquerDeverrouille()
        reconstruire()
        connexionPresentee = false
        onglet = .decisions
        await proposerNotifications()
    }

    func activerDemo() {
        session.activerDemo()
        verrou.marquerDeverrouille()
        reconstruire()
        onglet = .decisions
    }

    func deconnecter() async {
        await session.deconnecter()
        reconstruire()
        DelegueApp.mettreAJourBadge(0)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Dictée depuis un chantier : ouvre la Saisie pré-remplie.
    func dicter(pour dossier: Dossier) {
        saisie?.preparer(prefixe: dossier.prefixeSaisie)
        onglet = .saisie
    }

    func ouvrir(reference: String) {
        referenceCiblee = reference
        onglet = .decisions
    }

    // MARK: - Widget & badge

    private func publier(_ accueil: Accueil) {
        session.publierResume(accueil)
        WidgetCenter.shared.reloadAllTimelines()
        DelegueApp.mettreAJourBadge(accueil.decisions.count)
    }

    // MARK: - Notifications

    func proposerNotifications() async {
        guard !session.estDemo, !Configuration.testsUI else { return }
        if await DelegueApp.autorisationDejaAccordee() {
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            _ = await DelegueApp.demanderAutorisation()
        }
    }

    func recevoirJetonAPNs(_ jeton: String) {
        jetonAPNsEnAttente = jeton
        enregistrerAppareil(jeton)
    }

    private func enregistrerAppareil(_ jeton: String) {
        guard let api = session.api, !session.estDemo, dernierJetonEnvoye != jeton else { return }
        dernierJetonEnvoye = jeton
        Task {
            do {
                _ = try await api.enregistrerAppareil(jetonAPNs: jeton, nom: UIDevice.current.name, environnement: Configuration.environnementAPNs)
            } catch {
                dernierJetonEnvoye = nil
            }
        }
    }
}
