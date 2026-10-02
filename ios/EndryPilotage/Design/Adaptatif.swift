import SwiftUI

/// iPad : l'espace sert (deux colonnes, grilles), sans lignes de texte interminables.
/// Sur iPhone, et sur iPad en Split View étroit (largeur compacte), rien ne change.
enum Adaptatif {
    /// Largeur maximale d'une colonne de lecture (fiches, formulaires, conversation).
    static let lecture: CGFloat = 760
    /// Largeur maximale d'un écran à colonnes (Aujourd'hui, Finances, Entreprise).
    static let ecran: CGFloat = 1180
    /// Largeur maximale de l'assistant vocal plein écran.
    static let assistant: CGFloat = 640
    /// Largeur minimale d'une carte de chantier dans la grille.
    static let carteChantier: CGFloat = 330
}

extension View {
    /// Contenu centré et limité en largeur (iPad) ; sans effet quand l'écran est plus étroit.
    /// Contenu d'un défilement vertical : exactement la largeur de l'écran. Un élément trop large ne peut plus
    /// élargir la page, qui ne glisse donc jamais de côté « comme une page web ».
    func verrouillerLargeur() -> some View {
        containerRelativeFrame(.horizontal)
    }

    func largeurLisible(_ maximum: CGFloat = Adaptatif.lecture) -> some View {
        frame(maxWidth: maximum, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

/// Deux colonnes côte à côte en largeur régulière (iPad), l'une sous l'autre sinon (iPhone, Split View étroit).
struct Colonnes<Gauche: View, Droite: View>: View {
    /// Espace vertical entre les blocs d'une colonne.
    var espacement: CGFloat = Espace.l
    /// Espace entre les deux colonnes (les blocs portant déjà leur marge peuvent passer 0).
    var ecart: CGFloat = Espace.l
    @ViewBuilder var gauche: Gauche
    @ViewBuilder var droite: Droite
    @Environment(\.horizontalSizeClass) private var classe

    var body: some View {
        if classe == .regular {
            HStack(alignment: .top, spacing: ecart) {
                VStack(alignment: .leading, spacing: espacement) { gauche }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: espacement) { droite }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: espacement) {
                gauche
                droite
            }
        }
    }
}
