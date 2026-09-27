import AVFoundation
import BackgroundTasks
import EndryKit
import Foundation
import Observation
import UserNotifications

/// Briefing du matin : composé sur l'iPhone à partir des données du PC, lu à voix haute sur demande,
/// et posé en notification chaque jour ouvrable à l'heure choisie (rafraîchi en arrière-plan juste avant).
/// Sur l'écran verrouillé, jamais de montant.
enum BriefingMatin {
    static let cleActif = "briefing-actif"
    /// Minutes depuis minuit (7 h 00 par défaut).
    static let cleHeure = "briefing-heure"
    /// Montants dits par Siri (iPhone verrouillé, voiture) : désactivé par défaut.
    static let cleMontantsSiri = "briefing-montants-siri"
    static let tache = "com.endrysa.endry.briefing"
    static let identifiantNotification = "briefing-matin"

    static var actif: Bool { UserDefaults.standard.bool(forKey: cleActif) }
    static var minutes: Int { UserDefaults.standard.object(forKey: cleHeure) as? Int ?? 7 * 60 }

    @MainActor
    static func composer(app: ModeleApp, masquerMontants: Bool? = nil, le date: Date = Date()) -> Briefing {
        let masquer = masquerMontants ?? UserDefaults.standard.bool(forKey: ModeDevantClient.cle)
        return Briefing.composer(
            accueil: app.decisions?.accueil, semaine: app.chantiers?.semaine ?? [], argent: app.argent?.argent,
            entretiens: app.entretiens?.entretiens ?? [], offresASuivre: app.offresASuivre, pause: app.decisions?.enPause,
            prenom: UserDefaults.standard.string(forKey: Salutation.clePrenom), masquerMontants: masquer, le: date)
    }

    /// Prochain jour ouvrable à l'heure choisie (aujourd'hui si l'heure n'est pas passée).
    static func prochaineEcheance(apres date: Date = Date(), minutes: Int = minutes) -> Date {
        for decalage in 0..<8 {
            let jour = Calendar.current.date(byAdding: .day, value: decalage, to: date) ?? date
            guard DateEndry.jourSemaine(jour) <= 5 else { continue }
            let moment = DateEndry.a(minutes / 60, minutes % 60, le: jour)
            if moment > date { return moment }
        }
        return date.addingTimeInterval(86_400)
    }

    /// (Re)programme la notification du prochain matin avec le briefing le plus récent.
    static func programmer(_ briefing: Briefing?) async {
        let centre = UNUserNotificationCenter.current()
        centre.removePendingNotificationRequests(withIdentifiers: [identifiantNotification])
        guard actif else { return }
        let echeance = prochaineEcheance()
        let composants = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: echeance)
        let corps = briefing?.resumeNotification.nonVide ?? "Chantiers du jour, décisions et suivis : touchez pour écouter."
        await NotificationLocale.programmer(.briefing, identifiant: identifiantNotification, titre: "Briefing du matin",
                                            corps: corps, categorie: NotificationLocale.categorieBriefing,
                                            declencheur: UNCalendarNotificationTrigger(dateMatching: composants, repeats: false),
                                            fil: "briefing")
        planifierRafraichissement(avant: echeance)
    }

    // MARK: - Arrière-plan

    /// À appeler au lancement (avant la fin de `didFinishLaunching`).
    static func enregistrerTache() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: tache, using: nil) { tache in
            nonisolated(unsafe) let t = tache
            let travail = Task {
                let briefing = await DonneesArrierePlan.briefing(masquerMontants: true)
                await programmer(briefing)
                t.setTaskCompleted(success: briefing != nil)
            }
            t.expirationHandler = { travail.cancel() }
        }
    }

    static func planifierRafraichissement(avant echeance: Date) {
        let requete = BGAppRefreshTaskRequest(identifier: tache)
        requete.earliestBeginDate = max(Date().addingTimeInterval(15 * 60), echeance.addingTimeInterval(-50 * 60))
        try? BGTaskScheduler.shared.submit(requete)
    }
}

/// Données lues hors de l'interface (tâche de fond, Siri) : jeton du trousseau, lectures en parallèle.
enum DonneesArrierePlan {
    static func api() -> (any EndryAPI)? {
        #if canImport(Security)
        guard let i = CoffreTrousseau().lire(), !i.estExpire else { return nil }
        return ClientAPI(identifiants: i)
        #else
        return nil
        #endif
    }

    struct Lot: Sendable {
        var accueil: Accueil?
        var chantiers: ReponseChantiers?
        var argent: Argent?
        var entretiens: [Entretien]
    }

    static func charger() async -> Lot? {
        guard let api = api() else { return nil }
        async let a = try? api.accueil()
        async let c = try? api.chantiers()
        async let g = try? api.argent()
        async let e = try? api.entretiens()
        let lot = await Lot(accueil: a, chantiers: c, argent: g, entretiens: e ?? [])
        return lot.accueil == nil && lot.chantiers == nil ? nil : lot
    }

    static func briefing(masquerMontants: Bool) async -> Briefing? {
        guard let lot = await charger() else { return nil }
        let defauts = UserDefaults.standard
        let seuil = defauts.object(forKey: ReglagesSuivi.cleSeuil) as? Int ?? SuiviOffres.seuilParDefaut
        let offres = SuiviOffres.aSuivre(lot.argent?.offres.offres ?? lot.accueil?.offres.offres ?? [], seuil: seuil,
                                         ecartees: ReglagesSuivi.ecartees(defauts.string(forKey: ReglagesSuivi.cleEcartees) ?? ""))
        return Briefing.composer(accueil: lot.accueil, semaine: lot.chantiers?.semaine ?? [], argent: lot.argent, entretiens: lot.entretiens,
                                 offresASuivre: offres, prenom: defauts.string(forKey: Salutation.clePrenom), masquerMontants: masquerMontants)
    }
}

extension String {
    var nonVide: String? { isEmpty ? nil : self }
}

// MARK: - Lecture à voix haute

/// Lit un texte avec la voix d'Endry (Réglages › Voix d'Endry), par-dessus la musique baissée.
@MainActor
@Observable
final class LecteurVocal {
    private(set) var enLecture = false
    @ObservationIgnored private let synthese = AVSpeechSynthesizer()
    @ObservationIgnored private let delegue = DelegueLecture()

    init() {
        synthese.delegate = delegue
        delegue.surFin = { [weak self] in self?.enLecture = false }
    }

    func basculer(_ texte: String) {
        enLecture ? arreter() : lire(texte)
    }

    func lire(_ texte: String) {
        guard !Configuration.testsUI else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let phrase = AVSpeechUtterance(string: texte)
        phrase.voice = MoteurLocal.meilleureVoix()
        phrase.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        phrase.prefersAssistiveTechnologySettings = false
        synthese.stopSpeaking(at: .immediate)
        synthese.speak(phrase)
        enLecture = true
    }

    func arreter() {
        synthese.stopSpeaking(at: .immediate)
        enLecture = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private final class DelegueLecture: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var surFin: (@MainActor @Sendable () -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let fin = surFin
        Task { @MainActor in fin?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let fin = surFin
        Task { @MainActor in fin?() }
    }
}
