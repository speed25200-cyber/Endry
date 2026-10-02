import EndryKit
import SwiftUI
import UIKit

// MARK: - Maison Endry : briques de la maquette E (voir ios/Maquettes/MaisonEndry/STYLE.md)

extension Police {
    /// Cormorant Garamond à la taille de la maquette (hors échelle : grands chiffres, titres de tuile),
    /// mis à l'échelle avec Dynamic Type.
    static func serif(_ taille: CGFloat, relativeTo style: Font.TextStyle = .title, italique: Bool = false) -> Font {
        .custom(italique ? GraisseTitre.italique.nom : GraisseTitre.medium.nom, size: taille, relativeTo: style)
    }

    /// Chiffres et repères discrets (heures, « 4/7 », « Glisser pour valider ») : SF Mono.
    static func mono(_ taille: CGFloat = 10.5, relativeTo style: Font.TextStyle = .caption2) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: taille), weight: .regular, design: .monospaced)
    }
}

extension View {
    /// Étiquette de section Cinzel en capitales espacées (« À DÉCIDER », « FINANCES »).
    func etiquetteMaison(_ taille: CGFloat = 10.5, couleur: Color = .etiquette) -> some View {
        font(Police.etiquette(taille))
            .textCase(.uppercase)
            .tracking(taille * 0.2)
            .foregroundStyle(couleur)
    }

    /// Tuile Maison Endry : surface à peine teintée, filet fin, reflet sur le bord haut, ombre longue et douce.
    /// Volontairement sans flou d'arrière-plan : rien ne se recalcule pendant le défilement.
    func tuileMaison(rayon: CGFloat = 24) -> some View {
        let forme = RoundedRectangle(cornerRadius: rayon, style: .continuous)
        return background {
            forme.fill(Color.tuileTeinte)
                .shadow(color: Color.ombre.opacity(0.55), radius: 20, y: 14)
        }
        .overlay { forme.strokeBorder(Color.filet, lineWidth: Espace.filet) }
        .overlay {
            forme.strokeBorder(LinearGradient(colors: [Color.refletBord, .clear], startPoint: .top, endPoint: .center),
                               lineWidth: 1)
                .opacity(0.7)
        }
    }

    /// Verre Maison Endry pour les pastilles et boutons ronds posés sur le fond (statut, recherche, actions).
    /// Teinte crème et filet : même rendu sur toutes les versions d'iOS, sans effet de verre animé.
    func verreMaison<S: InsettableShape>(_ forme: S) -> some View {
        background {
            forme.fill(Color.verreTeinte)
                .shadow(color: Color.ombre.opacity(0.5), radius: 16, y: 10)
        }
        .overlay { forme.strokeBorder(Color.filet, lineWidth: Espace.filet) }
        .overlay {
            forme.strokeBorder(LinearGradient(colors: [Color.refletBord, .clear], startPoint: .topLeading, endPoint: .center),
                               lineWidth: 1)
                .opacity(0.6)
        }
    }
}

/// Point « en veille » qui respire (statut du bureau). Horloge locale au point : aucune animation
/// répétée ne s'échappe vers le reste de l'écran (cause du scintillement de la capsule en 1.0 (34)).
struct PointVeille: View {
    var couleur: Color = .sauge
    var actif = true
    var diametre: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        if actif, !reduireAnimations, !Configuration.testsUI {
            TimelineView(.animation(minimumInterval: 1 / 20)) { contexte in
                let t = contexte.date.timeIntervalSinceReferenceDate
                Circle().fill(couleur)
                    .opacity(0.675 + 0.325 * cos(t * 2 * .pi / 2.8))
                    .frame(width: diametre, height: diametre)
            }
            .frame(width: diametre, height: diametre)
            .accessibilityHidden(true)
        } else {
            Circle().fill(actif ? couleur : Color.encrePale)
                .frame(width: diametre, height: diametre)
                .accessibilityHidden(true)
        }
    }
}

/// Bouton rond de verre (40 pt) de l'en-tête.
struct BoutonRondVerre<Contenu: View>: View {
    var libelle: String
    var identifiant: String
    var action: () -> Void
    @ViewBuilder var contenu: Contenu

    var body: some View {
        Button(action: action) {
            contenu
                .foregroundStyle(Color.encre)
                .frame(width: 40, height: 40)
                .verreMaison(Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(ActionPressee())
        .accessibilityLabel(Text(libelle))
        .accessibilityIdentifier(identifiant)
    }
}

/// Pression : l'élément se tasse puis revient avec un léger ressort.
struct ActionPressee: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// Barre d'avancement fine (2 pt) des tuiles : filet en fond, couleur pleine jusqu'à la part.
struct BarreFine: View {
    var part: Double
    var couleur: Color = .signal

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.filet)
                Capsule().fill(couleur)
                    .frame(width: geo.size.width * min(max(part, 0), 1))
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

/// Fond Maison Endry : brun profond (ou papier) et, en haut à gauche, la photo d'ambiance fondue en halo.
struct FondMaison: View {
    var photo: String? = PhotosMarque.accueil
    @Environment(\.colorScheme) private var schema

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.fond
            if let photo {
                Image(photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 520, height: 520)
                    .blur(radius: 70)
                    .saturation(1.3)
                    .opacity(schema == .dark ? 0.34 : 0.2)
                    .offset(x: -90, y: -170)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Histogramme Maison Endry : barres arrondies, la barre mise en avant en signal, libellés en mono.
struct Histogramme: View {
    struct Barre: Identifiable {
        var libelle: String
        var valeur: Double
        var accent = false
        var id: String { libelle }
    }

    var barres: [Barre]
    var hauteur: CGFloat = 66

    var body: some View {
        let maximum = max(barres.map(\.valeur).max() ?? 1, 1)
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(barres) { barre in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(barre.accent ? Color.signal : Color.signal.opacity(0.28))
                        .frame(height: max(4, hauteur * barre.valeur / maximum))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: hauteur, alignment: .bottom)
            HStack(spacing: 6) {
                ForEach(barres) { barre in
                    Text(barre.libelle)
                        .font(Police.mono(9.5))
                        .foregroundStyle(Color.encreDouce)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(barres.map { "\($0.libelle) : \(FormatSuisse.chfArrondi($0.valeur))" }.joined(separator: ", ")))
    }
}

/// Ligne de liste Maison Endry (Finances, chantiers) : nom à gauche et repère mono, montant serif et état à droite.
struct LigneMaison: View {
    var titre: String
    var detail: String
    var montant: String
    var etat: String?
    var etatAccent = false
    var etatAlerte = false

    var body: some View {
        HStack(alignment: .center, spacing: Espace.s) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titre)
                    .styleTexte(15, relativeTo: .subheadline)
                    .foregroundStyle(Color.encre)
                    .lineLimit(1)
                Text(detail)
                    .font(Police.mono(10.5))
                    .foregroundStyle(Color.encreDouce)
                    .lineLimit(1)
            }
            Spacer(minLength: Espace.xs)
            VStack(alignment: .trailing, spacing: 3) {
                Text(montant)
                    .font(Police.serif(20, relativeTo: .headline))
                    .monospacedDigit()
                    .foregroundStyle(Color.encre)
                    .lineLimit(1)
                if let etat {
                    Text(etat)
                        .font(Police.mono(10.5))
                        .foregroundStyle(etatAlerte ? Color.rouille : etatAccent ? Color.signal : Color.encreDouce)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .tuileMaison(rayon: 22)
        .accessibilityElement(children: .combine)
    }
}
