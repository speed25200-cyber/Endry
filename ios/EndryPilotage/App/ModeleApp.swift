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
    /// Un écran plein ou une feuille couvre les onglets : leurs animations (points en direct, orbe) s'arrêtent.
    var ecranParDessus: Bool {
        conversationPresentee || assistantPresente || recherchePresentee || reglagesPresentes || briefingPresente || outilTerrain != nil
    }
    /// Vue de Finances à montrer (un instrument de l'accueil y mène directement).
    var vueFinances: ArgentView.VueFinances = .encaisser
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
    /// Saisie à mettre en avant dans l'historique (notification « saisie traitée »).
    var saisieCiblee: String?
    /// Recherche globale ouverte (loupe d'Aujourd'hui, ⌘F).
    var recherchePresentee = false

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
    /// Modèle d'Apple de l'assistant vocal (mémoire de la conversation) ; recréé quand le client API change.
    @ObservationIgnored private var cerveauGarde: (any CerveauVocal)?

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
                guard let self else { return .refusee("Connectez d’abord l’app au bureau.") }
                return await self.transmettreDemande(demande)
            },
            conversation: conversation
        )
        assistantActif = assistant
        return assistant
    }

    /// Temps réel si le PC le propose dans les 4 s ; sinon le moteur de l'iPhone, sans faire attendre le patron.
    private func moteurPrefere() async -> any MoteurVoix {
        if !session.estDemo, let api = session.api,
           let voix = await dansLeDelai(.seconds(4), { try? await api.sessionVoix() }), voix.disponible {
            return MoteurTempsReel(session: voix, executeur: ExecuteurOutils(api: api))
        }
        return moteurLocal()
    }

    /// Le modèle d'Apple garde le fil d'une ouverture de l'assistant à l'autre (page blanche après 30 min),
    /// et il est préchargé à chaque ouverture pour répondre sans délai.
    private func cerveauVocal() -> (any CerveauVocal)? {
        if let garde = cerveauGarde {
            garde.prechauffer()
            return garde
        }
        let nouveau = FabriqueCerveau.creer(executeur: session.api.map { ExecuteurOutils(api: $0) })
        cerveauGarde = nouveau
        return nouveau
    }

    private func moteurLocal() -> any MoteurVoix {
        MoteurLocal(
            donnees: {
                RepondeurLocal.Donnees(accueil: self.decisions?.accueil, argent: self.argent?.argent, chantiers: self.chantiers?.tous ?? [])
            },
            // Apple Intelligence sur l'iPhone : comprend les questions libres et lit les données par les outils.
            // En relais direct (par défaut), l'iPhone ne répond pas lui-même : le modèle n'est pas chargé
            // (des centaines de Mo et un temps de chargement épargnés à chaque ouverture).
            cerveau: ReglageVoix.relaisBureau ? nil : cerveauVocal(),
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
            // Questions de la conversation gardées faute de réseau : elles partent aussi.
            Task { await self?.conversation?.renvoyerEnAttente() }
        }
        flux.surSujets = { [weak self] sujets in
            await self?.recharger(sujets)
        }
        // Réponse du bureau prête : affichée et dite à l'instant, partout où elle est attendue.
        flux.surReponse = { [weak self] questionId, reponse in
            guard let self else { return }
            await self.conversation?.recevoirReponse(questionId: questionId, reponse: reponse)
            await self.assistantActif?.recevoirReponse(questionId: questionId, reponse: reponse)
            await self.agents?.recevoirReponse(questionId: questionId, reponse: reponse)
        }
        // Réponse en train de s'écrire sur le PC (v1.8) : elle apparaît mot à mot dans la conversation.
        flux.surPartiel = { [weak self] questionId, texte in
            self?.conversation?.recevoirPartiel(questionId: questionId, texte: texte)
        }
    }

    /// Recrée les modèles d'écran quand le client API change (connexion, démo, déconnexion).
    func reconstruire() {
        flux.arreter()
        cerveauGarde = nil
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
        d.surAccueil = { [weak self] accueil in
            self?.publier(accueil)
            // Les questions du bureau entrent aussi dans la conversation, comme dans une session avec Claude.
            for carte in accueil.decisions where carte.estQuestion { self?.conversation?.recevoir(questionDuBureau: carte) }
        }
        decisions = d
        offresSignees = (session.estOuvrier || session.estDirecteur) ? nil : ModeleOffresSignees(api: api)
        if session.estOuvrier || session.estDirecteur {
            suiviActions = nil
        } else {
            let dossierSuivi = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let s = ModeleSuiviActions(api: api, fichier: session.estDemo ? nil : dossierSuivi?.appendingPathComponent("suivi-actions.json"))
            suiviActions = s
            // Chaque compte rendu du bureau (fait, pas abouti) entre dans la conversation.
            s.surIssue = { [weak self] issue in self?.conversation?.recevoir(issue: issue) }
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
            guard let self else { return .refusee("Connectez d’abord l’app au bureau.") }
            return await self.transmettreDemande(demande)
        }
        entretiens = ModeleEntretiens(api: api)
        if session.estOuvrier {
            conversation = nil
        } else {
            let dossier = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            conversation = ModeleConversation(
                bureau: BureauClaude(api: api),
                transmettre: { [weak self] demande in
                    guard let self else { return .refusee("Connectez d’abord l’app au bureau.") }
                    return await self.transmettreDemande(demande)
                },
                // Fil du directeur dans son propre fichier : jamais mêlé à la conversation du secrétariat.
                fichier: session.estDemo ? nil : dossier?.appendingPathComponent(
                    session.estDirecteur ? "conversation-directeur.json" : "conversation.json"))
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
            try? FileManager.default.removeItem(at: dossier.appendingPathComponent("conversation-directeur.json"))
            try? FileManager.default.removeItem(at: dossier.appendingPathComponent("pieces-conversation", isDirectory: true))
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
        // Accès directeur : les montants et la conversation, rien d'autre (le PC répondrait 403).
        if session.estDirecteur {
            await argent?.charger()
            await chantiers?.charger()
            await conversation?.renvoyerEnAttente()
            await conversation?.verifierEnAttente()
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
        await conversation?.renvoyerEnAttente()
        await conversation?.verifierEnAttente()
        await apresChargement()
    }

    /// Données fraîches : briefing du prochain matin et zones de chantier à jour.
    func apresChargement() async {
        guard !session.estDemo, !session.estOuvrier, !session.estDirecteur else { return }
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
        if session.estDirecteur {
            if sujets.contains(.argent) { await argent?.charger() }
            if sujets.contains(.chantiers) { await chantiers?.charger() }
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
                groupe.addTask { await assistant?.rafraichirBureau() }
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
        guard !session.estOuvrier, !session.estDirecteur else { return }
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

    /// Demande dictée ou écrite (assistant vocal, conversation, fiche d'un agent) : transmise, puis suivie tout de suite
    /// dans « Fait récemment » avec l'identifiant du PC, jusqu'à son compte rendu.
    func transmettreDemande(_ demande: String) async -> ModeleSaisie.ResultatDemande {
        if session.estDirecteur { return .refusee("Cet accès répond aux questions : il ne prépare ni document ni envoi.") }
        guard let saisie else { return .refusee("Connectez d’abord l’app au bureau.") }
        let resultat = await saisie.transmettre(demande: demande)
        if resultat == .transmise {
            suiviActions?.enregistrer(saisie: saisie.derniereSaisieId, texte: demande)
            suivreApresGeste()
        }
        return resultat
    }

    /// Retour au premier plan : les routes du PC marquées absentes sont redemandées (le PC a pu être mis à jour).
    func reessayerRoutesPC() {
        CapacitesServeur.partage.reinitialiser()
        suiviActions?.reessayerRoutes()
    }

    /// Notification « saisie traitée » sans décision : l'onglet Dicter et son historique (la saisie mise en avant).
    func ouvrirHistoriqueSaisies(_ saisieId: String?) {
        reglagesPresentes = false
        saisieCiblee = saisieId
        onglet = .saisie
        Task { await saisie?.chargerHistorique() }
    }

    func recevoirJetonAPNs(_ jeton: String) {
        jetonAPNsEnAttente = jeton
        enregistrerAppareil(jeton)
    }

    private func enregistrerAppareil(_ jeton: String) {
        // Accès directeur : pas de notifications du bureau (décisions, courrier) sur cet iPhone.
        guard let api = session.api, !session.estDemo, !session.estDirecteur, dernierJetonEnvoye != jeton else { return }
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
