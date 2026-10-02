import EndryKit
import SwiftUI

// MARK: - Surfaces

/// Carte Maison Endry : la surface par défaut est la tuile de la maquette (dégradé teinté, filet, reflet,
/// ombre longue) ; une couleur de remplissage explicite garde un aplat (états, alertes).
struct SurfaceCarte: ViewModifier {
    var rayon: CGFloat = Espace.rayon
    var remplissage: Color = .surface

    func body(content: Content) -> some View {
        if remplissage == .surface {
            content.tuileMaison(rayon: rayon)
        } else {
            let forme = RoundedRectangle(cornerRadius: rayon, style: .continuous)
            content
                .background {
                    forme.fill(remplissage.shadow(.drop(color: Color.ombre, radius: 22, y: 12)))
                }
                .overlay { forme.strokeBorder(Color.filet, lineWidth: Espace.filet) }
        }
    }
}

extension View {
    func surfaceCarte(rayon: CGFloat = Espace.rayon, remplissage: Color = .surface) -> some View {
        modifier(SurfaceCarte(rayon: rayon, remplissage: remplissage))
    }

    /// Apparition en cascade : fondu + translation, désactivée si « Réduire les animations ».
    func apparitionEnCascade(index: Int, visible: Bool) -> some View {
        modifier(ApparitionCascade(index: index, visible: visible))
    }

    /// Effet de défilement : les cartes qui sortent de l'écran se tassent et pâlissent légèrement.
    func transitionDefilement() -> some View {
        scrollTransition(.interactive, axis: .vertical) { contenu, phase in
            contenu
                .scaleEffect(phase.isIdentity ? 1 : 0.965, anchor: phase.value < 0 ? .bottom : .top)
                .opacity(phase.isIdentity ? 1 : 0.72)
        }
    }
}

private struct ApparitionCascade: ViewModifier {
    var index: Int
    var visible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduireAnimations ? 0 : 18)
            .animation(
                reduireAnimations ? .fonduDoux : Animation.endry.delay(Double(min(index, 8)) * 0.05),
                value: visible
            )
    }
}

// MARK: - En-têtes

/// En-tête de section Maison Endry : étiquette Cinzel, détail en mono, action discrète à droite.
struct EnTeteSection: View {
    var titre: String
    var detail: String? = nil
    var action: (() -> Void)? = nil
    var libelleAction = "Tout voir"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Espace.xs) {
            Text(titre).etiquetteMaison()
            if let detail {
                Text(detail)
                    .font(Police.mono(11.5))
                    .foregroundStyle(Color.encreDouce)
                    .lineLimit(1)
            }
            Spacer()
            if let action {
                Button(libelleAction, action: action)
                    .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                    .foregroundStyle(Color.bronze)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Badges

struct BadgeControle: View {
    var controle: Controle
    @State private var deplie = false

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            Button {
                guard !controle.pointsAVerifier.isEmpty else { return }
                withAnimation(.endry) { deplie.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: controle.ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.hierarchical)
                    Text(controle.resume)
                        .styleTexte(13, relativeTo: .footnote, graisse: .medium)
                        .multilineTextAlignment(.leading)
                    if !controle.pointsAVerifier.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(deplie ? 180 : 0))
                    }
                }
                .foregroundStyle(couleur)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(couleur.opacity(0.11), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Contrôle qualité : \(controle.resume)"))

            if deplie || !controle.ok {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(controle.pointsAVerifier, id: \.self) { point in
                        HStack(alignment: .top, spacing: Espace.xs) {
                            Circle().fill(couleur).frame(width: 5, height: 5).padding(.top, 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(point.controle).styleTexte(14, relativeTo: .subheadline, graisse: .semibold)
                                if !point.detail.isEmpty {
                                    Text(point.detail).styleTexte(14, relativeTo: .subheadline)
                                        .foregroundStyle(Color.encreDouce)
                                }
                                if let document = point.document {
                                    Label(document, systemImage: "doc.text")
                                        .styleTexte(12, relativeTo: .caption)
                                        .foregroundStyle(Color.encrePale)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var couleur: Color { controle.ok ? .vertControle : .ambre }
}

struct Pastille: View {
    var texte: String
    var couleur: Color = .bronze
    var icone: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icone { Image(systemName: icone).font(.caption2.weight(.bold)) }
            Text(texte).styleTexte(11, relativeTo: .caption2, graisse: .semibold)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(couleur)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(couleur.opacity(0.12), in: Capsule())
    }
}

/// Genre de la carte (E-mail, Facture, Offre, Question, Paiement…) avec son icône.
struct GenreView: View {
    var genre: String

    var body: some View {
        Label {
            Text(genre).styleSurtitre()
        } icon: {
            Image(systemName: Self.icone(pour: genre))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.bronze)
        }
        .labelStyle(.titleAndIcon)
    }

    static func icone(pour genre: String) -> String {
        switch genre.lowercased() {
        case let g where g.contains("mail"): "envelope.fill"
        case let g where g.contains("facture"): "doc.text.fill"
        case let g where g.contains("offre"): "doc.richtext.fill"
        case let g where g.contains("question"): "questionmark.bubble.fill"
        case let g where g.contains("paiement"): "creditcard.fill"
        case let g where g.contains("planning"), let g where g.contains("rendez"): "calendar"
        case let g where g.contains("bexio"): "square.stack.3d.up.fill"
        default: "checkmark.circle.fill"
        }
    }
}

// MARK: - Rail d'avancement (7 étapes)

struct RailAvancement: View {
    var index: Int
    var compact = true
    @State private var rempli = false
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    private let etapes = EtapeChantier.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let largeur = geo.size.width
                let pas = largeur / CGFloat(etapes.count - 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surfaceCreuse).frame(height: 4)
                    Capsule().fill(.degradeOr)
                        .frame(width: rempli ? pas * CGFloat(index) : 0, height: 4)
                    ForEach(etapes.indices, id: \.self) { i in
                        Circle()
                            .fill(i <= index && rempli ? AnyShapeStyle(.degradeOr) : AnyShapeStyle(Color.surfaceCreuse))
                            .overlay(Circle().strokeBorder(i == index ? Color.bronze : .clear, lineWidth: 1.5))
                            .frame(width: i == index ? 12 : 8, height: i == index ? 12 : 8)
                            .position(x: pas * CGFloat(i), y: 2)
                    }
                }
                .frame(height: 12)
            }
            .frame(height: 12)
            .padding(.horizontal, 6)

            if !compact {
                HStack {
                    ForEach(etapes) { etape in
                        Text(etape.libelle)
                            .styleTexte(10, relativeTo: .caption2, graisse: etape.index == index ? .semibold : .regular)
                            .foregroundStyle(etape.index <= index ? Color.encre : Color.encrePale)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .onAppear {
            if reduireAnimations {
                rempli = true
            } else {
                withAnimation(.endry.delay(0.15)) { rempli = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Avancement : \(EtapeChantier.depuisIndex(index)?.libelle ?? ""), étape \(index + 1) sur 7"))
    }
}

// MARK: - Barre d'ancienneté

struct BarreAnciennete: View {
    struct Segment: Identifiable {
        var id: String { libelle }
        var libelle: String
        var montant: Double
        var couleur: Color
    }

    var segments: [Segment]
    var hauteur: CGFloat = 8
    var surFondSombre = false
    @State private var visible = false

    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.montant }, 0.01)
        VStack(alignment: .leading, spacing: Espace.xs) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(segments) { s in
                        if s.montant > 0 {
                            Capsule()
                                .fill(s.couleur)
                                .frame(width: max(hauteur, (geo.size.width - 9) * s.montant / total * (visible ? 1 : 0.02)))
                        }
                    }
                }
            }
            .frame(height: hauteur)

            HStack(spacing: Espace.s) {
                ForEach(segments) { s in
                    HStack(spacing: 5) {
                        Circle().fill(s.couleur).frame(width: 6, height: 6)
                        Text(s.libelle)
                            .styleTexte(11, relativeTo: .caption2, graisse: .medium)
                            .foregroundStyle(surFondSombre ? Color.orClair.opacity(0.7) : Color.encreDouce)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(s.libelle) : \(FormatSuisse.chf(s.montant))"))
                }
            }
        }
        .onAppear { withAnimation(.endry.delay(0.2)) { visible = true } }
    }
}

// MARK: - États

struct EtatVide: View {
    var titre: String
    var message: String
    var icone = "checkmark.seal"

    var body: some View {
        VStack(spacing: Espace.m) {
            ZStack {
                Circle().fill(Color.or.opacity(0.16)).frame(width: 92, height: 92)
                Circle().strokeBorder(Color.or.opacity(0.5), lineWidth: 0.8).frame(width: 118, height: 118)
                Image(systemName: icone)
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color.bronze)
                    .symbolEffect(.bounce, value: titre)
            }
            Text(titre).styleTitre(26, relativeTo: .title2).foregroundStyle(Color.encre)
            Text(message).styleTexte(15, relativeTo: .subheadline)
                .foregroundStyle(Color.encreDouce)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Espace.xxl)
        .padding(.horizontal, Espace.l)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Squelette de chargement avec un reflet qui glisse. Horloge locale (TimelineView) : aucune animation
/// répétée ne se propage au reste de l'écran.
struct Squelette: View {
    var hauteur: CGFloat = 16
    var largeur: CGFloat? = nil
    var rayon: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations
    @Environment(\.animationsEnPause) private var enPause

    var body: some View {
        RoundedRectangle(cornerRadius: rayon, style: .continuous)
            .fill(Color.surfaceCreuse)
            .frame(width: largeur, height: hauteur)
            .overlay {
                if !reduireAnimations, !enPause, !Configuration.testsUI {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { contexte in
                        let t = contexte.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        GeometryReader { geo in
                            LinearGradient(colors: [.clear, Color.or.opacity(0.14), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: geo.size.width * 0.6)
                                .offset(x: (-1 + 2.4 * t) * geo.size.width)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
                }
            }
            .accessibilityHidden(true)
    }
}

struct SqueletteCarte: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            Squelette(hauteur: 10, largeur: 80)
            Squelette(hauteur: 22)
            Squelette(hauteur: 22, largeur: 220)
            Squelette(hauteur: 14)
            Squelette(hauteur: 14, largeur: 160)
            HStack(spacing: Espace.xs) {
                Squelette(hauteur: 48, rayon: 24)
                Squelette(hauteur: 48, rayon: 24)
            }
            .padding(.top, Espace.xs)
        }
        .padding(Espace.l)
        .surfaceCarte()
        .accessibilityLabel(Text("Chargement"))
    }
}

/// Bandeau « Hors ligne · mis à jour il y a … ».
struct BandeauHorsLigne: View {
    var majLe: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { contexte in
            HStack(spacing: Espace.xs) {
                Image(systemName: "wifi.slash")
                Text("Hors ligne · lecture seule" + (majLe.map { " · mis à jour \(DateEndry.ilYa($0, maintenant: contexte.date))" } ?? ""))
                    .lineLimit(2)
            }
            .styleTexte(13, relativeTo: .footnote, graisse: .medium)
            .foregroundStyle(Color.ambre)
            .padding(.horizontal, Espace.m)
            .padding(.vertical, Espace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ambre.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }
}

struct VueErreur: View {
    var erreur: ErreurAPI
    var reessayer: () -> Void

    var body: some View {
        VStack(spacing: Espace.m) {
            Image(systemName: erreur.demandeNouveauLien ? "link.badge.plus" : "exclamationmark.icloud")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.bronze)
            Text(erreur.message)
                .styleTexte(16, relativeTo: .body, graisse: .medium)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.encre)
            Button("Réessayer", action: reessayer)
                .buttonStyle(BoutonSecondaire())
        }
        .padding(Espace.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Boutons

struct BoutonPrincipal: ButtonStyle {
    /// `nil` : or brossé (bouton principal par défaut).
    var couleur: Color? = nil

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        EtiquetteBouton(label: configuration.label, presse: configuration.isPressed, couleur: couleur, principal: true)
    }
}

struct BoutonSecondaire: ButtonStyle {
    var couleur: Color = .encre

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        EtiquetteBouton(label: configuration.label, presse: configuration.isPressed, couleur: couleur, principal: false)
    }
}

/// Rendu commun des boutons ; lit `isEnabled` dans une vue (et non dans le ButtonStyle).
private struct EtiquetteBouton<Etiquette: View>: View {
    var label: Etiquette
    var presse: Bool
    var couleur: Color?
    var principal: Bool
    @Environment(\.isEnabled) private var actif

    var body: some View {
        if principal {
            label
                .styleTexte(17, relativeTo: .body, graisse: .medium)
                .foregroundStyle(couleur == nil ? Color.boutonTexte : Color.espressoProfond)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, Espace.m)
                .background {
                    Capsule()
                        .fill(couleur ?? Color.bouton)
                        .overlay(Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.18), .clear],
                                                               startPoint: .top, endPoint: .center)))
                        .opacity(actif ? 1 : 0.35)
                }
                .shadow(color: Color.ombre.opacity(actif ? 1 : 0), radius: presse ? 6 : 16, y: presse ? 3 : 10)
                .scaleEffect(presse ? 0.97 : 1)
                .animation(.endryVif, value: presse)
        } else {
            label
                .styleTexte(17, relativeTo: .body, graisse: .medium)
                .foregroundStyle((couleur ?? Color.encre).opacity(actif ? 1 : 0.4))
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, Espace.m)
                .verreMaison(Capsule())
                .scaleEffect(presse ? 0.97 : 1)
                .animation(.endryVif, value: presse)
        }
    }
}

/// Puce de filtre (étapes des chantiers).
struct PuceFiltre: View {
    var libelle: String
    var nombre: Int?
    var selectionne: Bool
    var espace: Namespace.ID
    var action: () -> Void

    /// Maison Endry : la puce active porte la loupe (teinte et filet) ; les autres restent en verre discret.
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(libelle).styleTexte(13.5, relativeTo: .subheadline, graisse: selectionne ? .medium : .regular)
                if let nombre {
                    Text("\(nombre)")
                        .font(Police.mono(11.5))
                        .foregroundStyle(Color.encreDouce)
                        .contentTransition(.numericText(value: Double(nombre)))
                }
            }
            .foregroundStyle(selectionne ? Color.encre : Color.encreDouce)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background {
                if selectionne {
                    Capsule().fill(Color.lentille)
                        .overlay(Capsule().strokeBorder(Color.filetFort, lineWidth: Espace.filet))
                        .matchedGeometryEffect(id: "puce", in: espace)
                } else {
                    Capsule().strokeBorder(Color.filet, lineWidth: Espace.filet)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectionne ? .isSelected : [])
    }
}
