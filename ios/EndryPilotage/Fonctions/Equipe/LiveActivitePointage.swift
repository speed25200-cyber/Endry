import ActivityKit
import EndryKit
import Foundation

/// Démarre, met à jour ou termine la Live Activity du pointage. Sans l'extension widgets (ou si l'ouvrier
/// les a désactivées), rien ne se passe : le pointage reste dans l'app.
@MainActor
enum LiveActivitePointage {
    static func synchroniser(_ modele: ModeleEquipe) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let enCours = modele.enCours else {
            Task {
                for a in Activity<ActivitePointage>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }
        let etat = ActivitePointage.ContentState(chantier: enCours.chantier, debut: enCours.debut, totalJour: modele.feuille.total())
        let contenu = ActivityContent(state: etat, staleDate: nil)
        if !Activity<ActivitePointage>.activities.isEmpty {
            Task {
                for a in Activity<ActivitePointage>.activities { await a.update(contenu) }
            }
        } else {
            _ = try? Activity.request(attributes: ActivitePointage(ouvrier: modele.feuille.ouvrier), content: contenu, pushType: nil)
        }
    }
}
