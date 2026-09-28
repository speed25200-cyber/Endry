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
    /// Outil de terrain ouvert (bon de régie, bon de livraison, relevé 3D).
    var outilTerrain: DemandeOutil?
    /// Briefing du jour affiché (carte d'Aujourd'hui, notification du matin, Siri).
    var briefingPresente = false
    /// Chantier à ouvrir dans l'espace Chantiers (notification d'arrivée, Siri, Spotlight).
    var dossierCible: String?
    /// Lecture à voix haute du briefing.
    let lecteur = LecteurVocal()
    var toast: Toast?

    private(set) var decisions: ModeleDecisions?
    private(set) var chantiers: ModeleChantiers?
    private(set) var argent: ModeleArgent?
    private(set) var saisie: ModeleSaisie?
    /// Pause / reprise de l'assistant du PC (v1.1).
    private(set) var pilotage: ModelePilotage?
    /// Claude et ses agents sur le PC (Secrétariat, Comptabilité…), v1.2.
    private(set) var agents: ModeleAgents?
    /// Entretiens récurrents repérés par le bureau (v1.3).
    private(set) var entretiens: ModeleEntretiens?
    /// Mode équipe (lien d'ouvrier) : chantiers du jour et pointage.
    private(set) var equipe: ModeleEquipe?
    /// Suivi de chaque geste du patron jusqu'au résultat (« Fait récemment »).
    private(set) var suiviActions: ModeleSuiviActions?
    /// Fiche de suivi ouverte (toucher d'une ligne, notification, Siri).
    var suiviOuvert: String?
    /// Offres signées reçues par le bureau (v1.5).
    private(set) var offresSignees: ModeleOffresSignees?
    /// Nouvelle offre / nouvelle facture en cours de rédaction.
    var creation: DemandeCreation?
    /// Un chantier est ouvert dans l'espace Chantiers (le sélecteur Pipeline / Planning s'efface).
    var dossierOuvert = false
    /// Fil de conversation avec l'assistant du bureau (écrit, dicté, ou venu de l'assistant vocal).
    private(set) var conversation: ModeleConversation?
    /// Écran « Conversation » ouvert.
    var conversationPresentee = false

    @ObservationIgnored private var jetonAPNsEnAttente: String?
    /// File persistante des saisies faites sans réseau.
    @ObservationIgnored let fileSaisies = FileSaisies.parDefaut()
    @ObservationIgnored let reseau = SurveillanceReseau()
    /// Mises à jour poussées par le PC (SSE), avec repli sur une interrogation toutes les 60 s.
    @ObservationIgnored let flux = FluxEvenements()
    @ObservationIgnored private var dernierJetonEnvoye: String?
    @ObservationIgnored private var tacheSuivi: Task<Void, Never>?
    /// Assistant vocal ouvert : ses questions en attente sont revérifiées à chaque `maj saisies`.
    @ObservationIgnored weak var assistantActif: AssistantVocal?

    // MARK: - Assistant vocal

    /// Nouvelle conversation : moteur temps réel si le PC fournit une session éphémère, sinon moteur local.
    func nouvelAssistant() -> AssistantVocal {
        // La reconnaissance vocale apprend les noms du moment : chantiers de la semaine, clients, fournisseurs.
        VocabulaireVocal.partage.mettreAJour(noms: VocabulaireMetier.noms(
            semaine: chantiers?.semaine ?? [], chantiers: chantiers?.tous ?? [], argent: argent?.argent))
        let assistant = AssistantVocal(
            fabrique: { await self.moteurPrefere() },
            repli: { self.moteurLocal() },
            bureau: session.api.map { BureauClaude(api: $0) },
            transmettre: { [weak self] demande in
                guard let saisie = self?.saisie else { return .refusee("Connectez d’abord l’app au bureau.") }
                return await saisie.transmettre(demande: demande)
            },
            conversation: conversation
        )
        assistantActif = assistant
        return assistant
    }

    private func moteurPrefere() async -> any MoteurVoix {
        if !session.estDemo, let api = session.api, let voix = try? await api.sessionVoix(), voix.disponible {
            return MoteurTempsReel(session: voix, executeur: ExecuteurOutils(api: api))
        }
        return moteurLocal()
    }

    private func moteurLocal() -> any MoteurVoix {
        MoteurLocal(
            donnees: {
                RepondeurLocal.Donnees(accueil: self.decisions?.accueil, argent: self.argent?.argent, chantiers: self.chantiers?.tous ?? [])
            },
            // Apple Intelligence sur l'iPhone : comprend les questions libres et lit les données par les outils.
            cerveau: FabriqueCerveau.creer(executeur: session.api.map { ExecuteurOutils(api: $0) }),
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
            self.session.activerDemo(latence: Configuration.testsUI ? .milliseconds(80) : .milliseconds(450), ouvrier: Configuration.demoOuvrier)
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
            entretiens = nil
            equipe = nil
            suiviActions = nil
            offresSignees = nil
            conversation = nil
            return
        }
        let cache = session.estDemo ? nil : session.cache
        let rapport: RapportErreur = { [weak self] erreur in self?.session.signaler(erreur) }
        let d = ModeleDecisions(api: api, cache: cache, rapport: rapport)
        d.surAccueil = { [weak self] accueil in self?.publier(accueil) }
        decisions = d
        offresSignees = session.estOuvrier ? nil : ModeleOffresSignees(api: api)
        if session.estOuvrier {
            suiviActions = nil
        } else {
            let dossierSuivi = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let s = ModeleSuiviActions(api: api, fichier: session.estDemo ? nil : dossierSuivi?.appendingPathComponent("suivi-actions.json"))
            suiviActions = s
            d.surGeste = { [weak self] geste, carte, reponse, consignes in
                s.enregistrer(geste, carte: carte, reponse: reponse, consignes: consignes)
                self?.suivreApresGeste()
            }
        }
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
        entretiens = ModeleEntretiens(api: api)
        if session.estOuvrier {
            conversation = nil
        } else {
            let dossier = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            conversation = ModeleConversation(
                bureau: BureauClaude(api: api),
                transmettre: { [weak self] demande in
                    guard let saisie = self?.saisie else { return .refusee("Connectez d’abord l’app au bureau.") }
                    return await saisie.transmettre(demande: demande)
                },
                fichier: session.estDemo ? nil : dossier?.appendingPathComponent("conversation.json"))
        }
        if session.estOuvrier {
            let dossier = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            equipe = ModeleEquipe(api: api, ouvrier: session.nomOuvrier ?? "Équipe",
                                  fichier: session.estDemo ? nil : dossier?.appendingPathComponent("journee-ouvrier.json"))
        } else {
            equipe = nil
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
        session.activerDemo(ouvrier: Configuration.demoOuvrier)
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

    /// Révoque le jeton de cet iPhone côté PC (`DELETE /appareils/{id}`), puis efface tout.
    func deconnecterCetAppareil() async {
        let resultat = await session.deconnecterCetAppareil()
        await apresDeconnexion()
        switch resultat {
        case .revoque:
            toast = Toast("iPhone déconnecté : son jeton est révoqué sur le PC.")
        case .nonRevocable:
            toast = Toast("iPhone déconnecté. Le PC ne permet pas encore de révoquer ce jeton à distance : demandez un nouveau lien au bureau pour couper l’ancien.", style: .info)
        case .pcInjoignable:
            toast = Toast("iPhone déconnecté. Le PC était injoignable : retirez cet iPhone dans Réglages › Appareils depuis un autre appareil.", style: .info)
        }
    }

    /// Ancien jeton commun → jeton propre à cet iPhone, une seule fois, sans nouveau lien.
    func migrerJetonSiNecessaire() async {
        guard !session.estDemo, await session.migrerSiNecessaire() else { return }
        reconstruire()
        await rafraichirTout()
    }

    func deconnecter() async {
        await session.deconnecter()
        await apresDeconnexion()
    }

    private func apresDeconnexion() async {
        await fileSaisies.effacer()
        Documents.purger()
        // Plus rien de l'entreprise sur l'iPhone : Spotlight, briefing, zones de chantier, brouillon.
        await RepertoireChantiers.effacer()
        UserDefaults.standard.set(false, forKey: BriefingMatin.cleActif)
        await BriefingMatin.programmer(nil)
        await ArriveeChantier.partage.desactiver()
        BrouillonRegie.effacer()
        if let dossier = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: dossier.appendingPathComponent("suivi-actions.json"))
            try? FileManager.default.removeItem(at: dossier.appendingPathComponent("conversation.json"))
        }
        reconstruire()
        DelegueApp.mettreAJourBadge(0)
    }

    /// Dictée depuis un chantier : ouvre la Saisie pré-remplie.
    func dicter(pour dossier: Dossier) {
        saisie?.preparer(prefixe: dossier.prefixeSaisie)
        onglet = .saisie
    }

    /// Ouvre la fiche d'un chantier.
    func ouvrirChantier(_ id: String) {
        vueChantiers = .pipeline
        onglet = .chantiers
        dossierCible = id
    }

    /// Notification locale touchée (briefing, arrivée sur un chantier).
    func traiter(_ locale: NotificationLocale, action: String) {
        switch locale {
        case .briefing:
            briefingPresente = true
            if action == NotificationLocale.actionEcouter {
                Task {
                    await rafraichirTout()
                    lecteur.lire(BriefingMatin.composer(app: self).texteParle)
                }
            }
        case .arrivee(let id):
            switch action {
            case NotificationLocale.actionRegie: ouvrirOutil(.regie, chantier: id)
            case NotificationLocale.actionBon: ouvrirOutil(.bonLivraison, chantier: id)
            default: ouvrirChantier(id)
            }
        }
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
        // Jeton d'ouvrier : ni argent, ni décisions, ni agents (le PC répondrait 403).
        if session.estOuvrier {
            await equipe?.charger()
            await saisie?.viderFile()
            return
        }
        let d = decisions, c = chantiers, a = argent, s = saisie, g = agents
        await withDiscardingTaskGroup { groupe in
            groupe.addTask { await d?.charger() }
            groupe.addTask { await c?.charger() }
            groupe.addTask { await a?.charger() }
            groupe.addTask { await s?.viderFile() }
            groupe.addTask { await g?.charger() }
        }
        await suiviActions?.rafraichir(saisies: s?.historique ?? [])
        await offresSignees?.charger(chantiers: c?.tous ?? [])
        await conversation?.verifierEnAttente()
        await apresChargement()
    }

    /// Données fraîches : briefing du prochain matin et zones de chantier à jour.
    func apresChargement() async {
        guard !session.estDemo, !session.estOuvrier else { return }
        if let tous = chantiers?.tous, !tous.isEmpty { await RepertoireChantiers.mettreAJour(tous) }
        if BriefingMatin.actif {
            await BriefingMatin.programmer(BriefingMatin.composer(app: self, masquerMontants: true))
        }
        await ArriveeChantier.partage.mettreAJour(app: self)
    }

    /// Recharge seulement ce que le PC signale comme modifié.
    func recharger(_ sujets: Set<SujetMaj>) async {
        guard session.estConnecte else { return }
        if session.estOuvrier {
            if sujets.contains(.chantiers) { await equipe?.charger() }
            return
        }
        let d = decisions, c = chantiers, a = argent, s = saisie, g = agents
        await withDiscardingTaskGroup { groupe in
            if sujets.contains(.decisions) { groupe.addTask { await d?.charger() } }
            if sujets.contains(.chantiers) { groupe.addTask { await c?.charger() } }
            if sujets.contains(.argent) { groupe.addTask { await a?.charger() } }
            if sujets.contains(.saisies) { groupe.addTask { await s?.chargerHistorique() } }
            if sujets.contains(.agents) || sujets.contains(.saisies) { groupe.addTask { await g?.charger() } }
            if sujets.contains(.saisies) || sujets.contains(.agents) {
                // Réponses aux questions posées à l'assistant : `maj saisies`, ou `event: reponse` (v1.6, mode direct).
                let assistant = assistantActif
                groupe.addTask { await assistant?.verifierEnAttente() }
                groupe.addTask { await g?.verifierEnAttente() }
                let fil = conversation
                groupe.addTask { await fil?.verifierEnAttente() }
            }
        }
        if !sujets.isDisjoint(with: [.decisions, .saisies, .agents, .suivi]) {
            await suiviActions?.rafraichir(saisies: saisie?.historique ?? [])
        }
        if !sujets.isDisjoint(with: [.chantiers, .argent]) {
            await offresSignees?.charger(chantiers: chantiers?.tous ?? [])
        }
        if sujets.contains(.chantiers) || sujets.contains(.decisions) { await apresChargement() }
    }

    /// Après un geste : le compte rendu du bureau est relu à 3 s, 15 s, 45 s puis 2 min (en plus des événements du PC).
    func suivreApresGeste() {
        tacheSuivi?.cancel()
        tacheSuivi = Task { [weak self] in
            for delai in [3, 12, 30, 75] {
                try? await Task.sleep(for: .seconds(delai))
                guard !Task.isCancelled, let self, let suivi = self.suiviActions else { return }
                await suivi.rafraichir(saisies: self.saisie?.historique ?? [])
                if suivi.enAttente.isEmpty { return }
            }
        }
    }

    /// Nouvelle offre ou facture : le patron décrit, le bureau prépare dans Bexio, le Oui reste au patron.
    func nouveauDocument(_ type: TypeDemandeDocument, chantier: String? = nil, offre: OffreSignee? = nil) {
        guard !session.estOuvrier else { return }
        reglagesPresentes = false
        creation = DemandeCreation(type: type, chantierId: chantier ?? offre?.chantierId, offre: offre)
    }

    func ouvrirSuivi(_ id: String) {
        reglagesPresentes = false
        suiviOuvert = id
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
              !carte.exigeGlisser, !carte.estQuestion else {
            ouvrir(reference: reference)
            return
        }
        do {
            let reponse = try await api.agir(.oui, sur: reference)
            suiviActions?.enregistrer(.oui, carte: carte, reponse: reponse.message)
            await decisions?.charger()
            suivreApresGeste()
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
