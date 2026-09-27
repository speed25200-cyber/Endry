import EndryKit
import Foundation
import Observation
import UIKit

/// État global : session, écrans, navigation, notifications. Toutes les données viennent de l'API.
@MainActor
@Observable
final class ModeleApp {
    let session: ModeleSession
    let verrou = Verrou()
    let documents = Documents()

    var onglet: Onglet = .aujourdhui
    /// Vue de l'espace Chantiers (Pipeline ou Planning), pilotable depuis l'accueil.
    var vueChantiers: VueChantiers = .pipeline
    /// Carte à mettre en avant (toucher d'une notification).
    var referenceCiblee: String?
    /// Présente l'écran de connexion par-dessus l'app (nouveau lien).
    var connexionPresentee = false
    /// Lien d'accès reçu par lien profond, en attente de confirmation de l'hôte.
    var lienEnAttente: LienAcces?
    var reglagesPresentes = false
    var toast: Toast?

    private(set) var decisions: ModeleDecisions?
    private(set) var chantiers: ModeleChantiers?
    private(set) var argent: ModeleArgent?
    private(set) var saisie: ModeleSaisie?

    @ObservationIgnored private var jetonAPNsEnAttente: String?
    /// File persistante des saisies faites sans réseau.
    @ObservationIgnored let fileSaisies = FileSaisies.parDefaut()
    @ObservationIgnored let reseau = SurveillanceReseau()
    @ObservationIgnored private var dernierJetonEnvoye: String?

    init(session: ModeleSession? = nil) {
        if let session {
            self.session = session
        } else {
            #if canImport(Security)
            let coffre = CoffreTrousseau()
            #else
            let coffre = CoffreMemoire()
            #endif
            self.session = ModeleSession(coffre: coffre, cache: .parDefaut())
        }
        self.session.appareil = (UIDevice.current.name, Self.modeleMachine())
        Documents.purger()
        if Configuration.lancementDemo {
            self.session.activerDemo(latence: Configuration.testsUI ? .milliseconds(80) : .milliseconds(450))
            verrou.marquerDeverrouille()
        }
        reconstruire()
        // Retour du réseau : les saisies gardées sur l'iPhone partent seules.
        reseau.surRetour = { [weak self] in
            Task { await self?.saisie?.viderFile() }
        }
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
        saisie = ModeleSaisie(api: api, file: session.estDemo ? FileSaisies(dossier: nil) : fileSaisies, rapport: rapport)
        dernierJetonEnvoye = nil
        if let jeton = jetonAPNsEnAttente { enregistrerAppareil(jeton) }
    }

    func connecter(texte: String) async throws(ErreurConnexion) {
        try await session.connecter(texte: texte)
        verrou.marquerDeverrouille()
        reconstruire()
        connexionPresentee = false
        onglet = .aujourdhui
        await proposerNotifications()
    }

    func activerDemo() {
        session.activerDemo()
        verrou.marquerDeverrouille()
        reconstruire()
        onglet = .aujourdhui
    }

    /// Connexion confirmée par le patron depuis un lien profond.
    func connecterLienConfirme(_ lien: LienAcces) async {
        lienEnAttente = nil
        do {
            try await connecter(texte: lien.base.absoluteString + LienAcces.marqueur + lien.secret)
        } catch {
            connexionPresentee = true
            toast = Toast(error.message, style: .erreur)
        }
    }

    /// Révoque le jeton de cet iPhone côté PC (v1.1), puis efface tout.
    func deconnecterCetAppareil() async {
        await session.deconnecterCetAppareil()
        await apresDeconnexion()
    }

    func deconnecter() async {
        await session.deconnecter()
        await apresDeconnexion()
    }

    private func apresDeconnexion() async {
        await fileSaisies.effacer()
        Documents.purger()
        reconstruire()
        DelegueApp.mettreAJourBadge(0)
    }

    /// Dictée depuis un chantier : ouvre la Saisie pré-remplie.
    func dicter(pour dossier: Dossier) {
        saisie?.preparer(prefixe: dossier.prefixeSaisie)
        onglet = .saisie
    }

    func ouvrir(reference: String) {
        referenceCiblee = reference
        onglet = .aujourdhui
    }

    /// Identifiant matériel (« iPhone17,1 »), pour la liste des appareils côté PC.
    static func modeleMachine() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { octets in
            String(decoding: octets.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    // MARK: - Rafraîchissement

    /// Recharge les écrans : retour au premier plan, notification reçue, événement serveur.
    func rafraichirTout() async {
        guard session.estConnecte else { return }
        let d = decisions, c = chantiers, a = argent, s = saisie
        await withDiscardingTaskGroup { groupe in
            groupe.addTask { await d?.charger() }
            groupe.addTask { await c?.charger() }
            groupe.addTask { await a?.charger() }
            groupe.addTask { await s?.viderFile() }
        }
    }

    // MARK: - Badge

    private func publier(_ accueil: Accueil) {
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

enum VueChantiers: Hashable {
    case pipeline, planning
}
