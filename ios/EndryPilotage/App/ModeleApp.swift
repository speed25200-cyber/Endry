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
    /// Assistant vocal plein écran (toucher long du micro central).
    var assistantPresente = false
    var toast: Toast?

    private(set) var decisions: ModeleDecisions?
    private(set) var chantiers: ModeleChantiers?
    private(set) var argent: ModeleArgent?
    private(set) var saisie: ModeleSaisie?
    /// Pause / reprise de l'assistant du PC (v1.1).
    private(set) var pilotage: ModelePilotage?
    /// Claude et ses agents sur le PC (Secrétariat, Comptabilité…), v1.2.
    private(set) var agents: ModeleAgents?

    @ObservationIgnored private var jetonAPNsEnAttente: String?
    /// File persistante des saisies faites sans réseau.
    @ObservationIgnored let fileSaisies = FileSaisies.parDefaut()
    @ObservationIgnored let reseau = SurveillanceReseau()
    /// Mises à jour poussées par le PC (SSE), avec repli sur une interrogation toutes les 60 s.
    @ObservationIgnored let flux = FluxEvenements()
    @ObservationIgnored private var dernierJetonEnvoye: String?

    // MARK: - Assistant vocal

    /// Nouvelle conversation : moteur temps réel si le PC fournit une session éphémère, sinon moteur local.
    func nouvelAssistant() -> AssistantVocal {
        AssistantVocal(
            fabrique: { await self.moteurPrefere() },
            repli: { self.moteurLocal() },
            bureau: session.api.map { BureauClaude(api: $0) }
        )
    }

    private func moteurPrefere() async -> any MoteurVoix {
        if !session.estDemo, let api = session.api, let voix = try? await api.sessionVoix(), voix.disponible {
            return MoteurTempsReel(session: voix, executeur: ExecuteurOutils(api: api))
        }
        return moteurLocal()
    }

    private func moteurLocal() -> any MoteurVoix {
        let transmettre: @MainActor @Sendable (String) async -> ModeleSaisie.ResultatDemande = { [weak self] demande in
            guard let saisie = self?.saisie else { return .refusee("Connectez d’abord l’app au bureau.") }
            return await saisie.transmettre(demande: demande)
        }
        return MoteurLocal(
            donnees: {
                RepondeurLocal.Donnees(accueil: self.decisions?.accueil, argent: self.argent?.argent, chantiers: self.chantiers?.tous ?? [])
            },
            transmettre: transmettre,
            // Apple Intelligence sur l'iPhone : comprend les questions libres et lit les données par les outils.
            cerveau: FabriqueCerveau.creer(executeur: session.api.map { ExecuteurOutils(api: $0) }, transmettre: transmettre),
            executeur: session.api.map { ExecuteurOutils(api: $0) }
        )
    }

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
        flux.surSujets = { [weak self] sujets in
            await self?.recharger(sujets)
        }
    }

    /// Recrée les modèles d'écran quand le client API change (connexion, démo, déconnexion).
    func reconstruire() {
        flux.arreter()
        guard let api = session.api else {
            decisions = nil
            chantiers = nil
            argent = nil
            saisie = nil
            pilotage = nil
            agents = nil
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
        let p = ModelePilotage(api: api)
        p.surChangement = { [weak self] pause in self?.decisions?.appliquerPause(pause) }
        pilotage = p
        agents = ModeleAgents(api: api) { [weak self] demande in
            guard let saisie = self?.saisie else { return .refusee("Connectez d’abord l’app au bureau.") }
            return await saisie.transmettre(demande: demande)
        }
        dernierJetonEnvoye = nil
        reprendreFlux()
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
        let d = decisions, c = chantiers, a = argent, s = saisie, g = agents
        await withDiscardingTaskGroup { groupe in
            groupe.addTask { await d?.charger() }
            groupe.addTask { await c?.charger() }
            groupe.addTask { await a?.charger() }
            groupe.addTask { await s?.viderFile() }
            groupe.addTask { await g?.charger() }
        }
    }

    /// Recharge seulement ce que le PC signale comme modifié.
    func recharger(_ sujets: Set<SujetMaj>) async {
        guard session.estConnecte else { return }
        let d = decisions, c = chantiers, a = argent, s = saisie, g = agents
        await withDiscardingTaskGroup { groupe in
            if sujets.contains(.decisions) { groupe.addTask { await d?.charger() } }
            if sujets.contains(.chantiers) { groupe.addTask { await c?.charger() } }
            if sujets.contains(.argent) { groupe.addTask { await a?.charger() } }
            if sujets.contains(.saisies) { groupe.addTask { await s?.chargerHistorique() } }
            if sujets.contains(.agents) || sujets.contains(.saisies) { groupe.addTask { await g?.charger() } }
        }
    }

    /// Flux d'événements : seulement avec un vrai serveur, au premier plan.
    func reprendreFlux() {
        guard session.estConnecte, !session.estDemo, let client = session.api as? ClientAPI else { return }
        flux.demarrer(client: client)
    }

    func suspendreFlux() {
        flux.arreter()
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

    /// Action « Oui » d'une notification DECISION (appareil déverrouillé).
    /// Défense en profondeur : la décision est relue ; un envoi à un tiers ou une question n'est jamais validé
    /// hors de l'app, la carte est alors simplement ouverte.
    func accepterDepuisNotification(_ reference: String) async {
        guard let api = session.api, session.estConnecte else { return }
        guard let liste = try? await api.decisions(),
              let carte = liste.decisions.first(where: { $0.reference == reference }),
              !carte.exigeGlisser, !carte.estQuestion, !(decisions?.enPause ?? false) else {
            ouvrir(reference: reference)
            return
        }
        do {
            _ = try await api.agir(.oui, sur: reference)
            await decisions?.charger()
        } catch {
            ouvrir(reference: reference)
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
