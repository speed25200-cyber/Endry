import EndryKit
import SwiftUI
import UIKit

// MARK: - Maison Endry : briques de la maquette E (voir ios/Maquettes/MaisonEndry/STYLE.md)

extension Police {
    /// Cormorant Garamond à la taille voulue (grands chiffres, titres courts), mis à l'échelle avec Dynamic Type.
    /// Grands titres et grands chiffres : SF Pro Display, fin pour les très grandes tailles (montants, compteurs),
    /// régulier pour les titres, chiffres alignés et tabulaires. L'italique n'est plus utilisé (gardé pour l'API).
    static func serif(_ taille: CGFloat, relativeTo style: Font.TextStyle = .title, italique: Bool = false) -> Font {
        let poids: Font.Weight = taille >= 34 ? .light : taille >= 22 ? .regular : .medium
        return .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: taille), weight: poids)
            .monospacedDigit()
    }

    /// Cormorant avec chiffres alignés (« 01 », « 49’673 », « 0:03 ») : par défaut, la fonte dessine des chiffres
    /// elzéviriens (« OI », chiffres qui descendent), illisibles dans les montants et les compteurs.
    static func cormorant(_ nom: String, taille: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        guard let base = UIFont(name: nom, size: taille) else { return .custom(nom, size: taille, relativeTo: style) }
        // kNumberCaseType (21) / kUpperCaseNumbersSelector (1) : chiffres alignés sur les capitales.
        let reglages: [[UIFontDescriptor.FeatureKey: Int]] = [[.type: 21, .selector: 1]]
        let descripteur = base.fontDescriptor.addingAttributes([.featureSettings: reglages])
        let police = UIFont(descriptor: descripteur, size: taille)
        return Font(UIFontMetrics(forTextStyle: style.uiKit).scaledFont(for: police))
    }

    /// Repères discrets (heures, « 4/7 », « Glisser pour valider ») : SF Pro, chiffres tabulaires.
    /// (Plus de police à chasse fixe pour les libellés : elle faisait « terminal ».)
    static func mono(_ taille: CGFloat = 11.5, relativeTo style: Font.TextStyle = .caption) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: taille + 1), weight: .medium)
            .monospacedDigit()
    }
}

extension View {
    /// Étiquette de section : petites capitales SF Pro, nettes et espacées (« À DÉCIDER », « FINANCES »).
    func etiquetteMaison(_ taille: CGFloat = 11.5, couleur: Color = .etiquette) -> some View {
        font(.system(size: UIFontMetrics(forTextStyle: .caption1).scaledValue(for: taille), weight: .semibold))
            .textCase(.uppercase)
            .tracking(taille * 0.1)
            .foregroundStyle(couleur)
    }

    /// Tuile Maison Endry : surface teintée en dégradé (plus claire en haut à gauche), filet fin, reflet sur le
    /// bord haut, ombre longue et douce. Sans flou d'arrière-plan : rien ne se recalcule pendant le défilement.
    func tuileMaison(rayon: CGFloat = 24) -> some View {
        let forme = RoundedRectangle(cornerRadius: rayon, style: .continuous)
        return background {
            forme.fill(LinearGradient(colors: [Color.tuileHaut, Color.tuileTeinte], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Color.ombre.opacity(0.55), radius: 22, y: 14)
        }
        .overlay { forme.strokeBorder(Color.filet, lineWidth: Espace.filet) }
        .overlay {
            forme.strokeBorder(LinearGradient(colors: [Color.refletBord, .clear], startPoint: .top, endPoint: .center),
                               lineWidth: 1)
                .opacity(0.35)
        }
    }

    /// Verre Maison Endry pour ce qui flotte (pastilles, boutons ronds, barres) : Liquid Glass teinté crème
    /// sur iOS 26 (réagit au toucher si `interactif`), verre teinté et filet avant.
    @ViewBuilder
    func verreMaison<S: InsettableShape>(_ forme: S, interactif: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(interactif ? Glass.regular.tint(Color.verreTeinte).interactive() : Glass.regular.tint(Color.verreTeinte), in: forme)
                .overlay { forme.strokeBorder(Color.filet, lineWidth: Espace.filet) }
        } else {
            verrePlat(forme)
        }
        #else
        verrePlat(forme)
        #endif
    }

    private func verrePlat<S: InsettableShape>(_ forme: S) -> some View {
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

/// Titre adaptatif : le Cormorant d'apparat pour les titres courts ; plus le texte est long, plus il se fait
/// discret, jusqu'au texte courant (SF Pro) au-delà de 110 signes — jamais de mur de grandes lettres.
/// Ce qui suit un tiret long passe en italique (« Réponse à Mme Rey — *variante WC* »).
struct TitreAdaptatif: View {
    var texte: String
    /// Taille du serif pour un titre court.
    var grand: CGFloat = 36
    var lignes: Int? = nil
    var couleur: Color = .encre

    private var longueur: Int { texte.count }

    private var taille: CGFloat {
        switch longueur {
        case ...32: grand * 0.86
        case ...64: (grand * 0.7).rounded()
        default: max((grand * 0.6).rounded(), 21)
        }
    }

    var body: some View {
        if longueur > 110 {
            Text(texte)
                .styleTexte(19, relativeTo: .title3, graisse: .medium)
                .lineSpacing(4)
                .foregroundStyle(couleur)
                .lineLimit(lignes)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let morceaux = texte.components(separatedBy: " — ")
            let debut = morceaux.first ?? texte
            let fin = morceaux.dropFirst().joined(separator: " — ")
            Text("\(Text(debut))\(Text(fin.isEmpty ? "" : " — "))\(Text(fin).foregroundStyle(Color.encreDouce))")
                .font(Police.serif(taille, relativeTo: .title))
                .tracking(-0.02 * taille)
                .foregroundStyle(couleur)
                .lineLimit(lignes)
                .fixedSize(horizontal: false, vertical: true)
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
                .frame(width: 42, height: 42)
                .verreMaison(Circle(), interactif: true)
                .frame(width: 46, height: 46)
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
        // La photo est posée en calque : elle ne doit jamais élargir l'écran (520 pt > largeur d'un iPhone).
        Color.fond
            .overlay(alignment: .topLeading) {
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
            .clipped()
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
                        .font(Police.mono(11))
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
                    .styleTexte(16, relativeTo: .subheadline)
                    .foregroundStyle(Color.encre)
                    .lineLimit(1)
                Text(detail)
                    .font(Police.mono(11.5))
                    .foregroundStyle(Color.encreDouce)
                    .lineLimit(1)
            }
            Spacer(minLength: Espace.xs)
            VStack(alignment: .trailing, spacing: 3) {
                Text(montant)
                    .font(Police.serif(23, relativeTo: .headline))
                    .monospacedDigit()
                    .foregroundStyle(Color.encre)
                    .lineLimit(1)
                if let etat {
                    Text(etat)
                        .font(Police.mono(11.5))
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
