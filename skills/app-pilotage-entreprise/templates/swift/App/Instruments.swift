// Modèle issu du skill app-pilotage-entreprise. Dépend de Palette.swift (tokens) et de EtapeDossier ({{PREFIXE}}Kit).
import {{PREFIXE}}Kit
import SwiftUI

// MARK: - Instruments du poste de pilotage
//
// Briques de la supervision : un glyphe dans un carré teinté, un libellé, un grand chiffre tabulaire, une ligne
// de détail, et un accessoire de lecture (barre de proportion, segments d'avancement). Même tuile partout :
// on lit l'entreprise d'un coup d'œil, chaque chiffre mène à son espace.

/// Ton d'un instrument : neutre (crème), alerte (rouille), sain (sauge).
enum TonInstrument {
    case neutre, alerte, sain

    var couleur: Color {
        switch self {
        case .neutre: .signal
        case .alerte: .rouille
        case .sain: .sauge
        }
    }
}

/// Glyphe SF Symbols dans un carré arrondi teinté du ton.
struct GlypheInstrument: View {
    var symbole: String
    var ton: TonInstrument = .neutre
    var cote: CGFloat = 26

    var body: some View {
        Image(systemName: symbole)
            .font(.system(size: cote * 0.46, weight: .semibold))
            .foregroundStyle(ton.couleur)
            .frame(width: cote, height: cote)
            .background(ton.couleur.opacity(0.13), in: RoundedRectangle(cornerRadius: cote * 0.31, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// En-tête d'instrument : glyphe et libellé ; à droite, un accessoire (pastille, chevron).
struct LibelleInstrument<Accessoire: View>: View {
    var symbole: String
    var titre: String
    var ton: TonInstrument = .neutre
    @ViewBuilder var accessoire: Accessoire

    var body: some View {
        HStack(spacing: 8) {
            GlypheInstrument(symbole: symbole, ton: ton)
            Text(titre)
                .font(.system(size: UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 13), weight: .medium))
                .foregroundStyle(Color.encreDouce)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            accessoire
        }
    }
}

extension LibelleInstrument where Accessoire == EmptyView {
    init(symbole: String, titre: String, ton: TonInstrument = .neutre) {
        self.init(symbole: symbole, titre: titre, ton: ton) { EmptyView() }
    }
}

/// Grand chiffre d'instrument, tabulaire, suivi d'une unité discrète (« 3 factures », « CHF 35’589 »).
struct ChiffreInstrument: View {
    var valeur: String
    var unite: String? = nil
    /// Unité avant le chiffre (« CHF »).
    var prefixe: String? = nil
    var taille: CGFloat = 30
    var couleur: Color = .encre

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let prefixe {
                Text(prefixe)
                    .font(.system(size: UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 12), weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Color.encreDouce)
            }
            Text(valeur)
                .font(Police.serif(taille, relativeTo: .largeTitle))
                .tracking(-taille * 0.022)
                .foregroundStyle(couleur)
                .contentTransition(.numericText())
            if let unite {
                Text(unite)
                    .font(.system(size: UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 13), weight: .regular))
                    .foregroundStyle(Color.encreDouce)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Indicateur du poste de pilotage : tuile touchable (libellé, grand chiffre, détail, accessoire de lecture).
struct Indicateur<Pied: View>: View {
    var symbole: String
    var titre: String
    var valeur: String
    var unite: String? = nil
    var detail: String? = nil
    var ton: TonInstrument = .neutre
    var identifiant: String
    var action: () -> Void
    @ViewBuilder var pied: Pied

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                LibelleInstrument(symbole: symbole, titre: titre, ton: ton)
                Spacer(minLength: 14)
                ChiffreInstrument(valeur: valeur, unite: unite, couleur: ton == .alerte ? .rouille : .encre)
                if let detail {
                    Text(detail)
                        .font(.system(size: UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 12.5)))
                        .monospacedDigit()
                        .foregroundStyle(Color.encreDouce)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 2)
                }
                pied
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .tuileMaison(rayon: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(ActionPressee())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([titre, [valeur, unite].compactMap { $0 }.joined(separator: " "), detail].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifiant)
    }
}

extension Indicateur where Pied == EmptyView {
    init(symbole: String, titre: String, valeur: String, unite: String? = nil, detail: String? = nil,
         ton: TonInstrument = .neutre, identifiant: String, action: @escaping () -> Void) {
        self.init(symbole: symbole, titre: titre, valeur: valeur, unite: unite, detail: detail, ton: ton,
                  identifiant: identifiant, action: action) { EmptyView() }
    }
}

/// Barre de proportion : parts côte à côte, séparées d'un fin interstice (encaisser / payer, ancienneté…).
struct BarreParts: View {
    var parts: [(valeur: Double, couleur: Color)]
    var hauteur: CGFloat = 6

    var body: some View {
        let total = parts.reduce(0) { $0 + max($1.valeur, 0) }
        GeometryReader { geo in
            let visibles = parts.filter { $0.valeur > 0 }
            let interstices = CGFloat(max(visibles.count - 1, 0)) * 3
            HStack(spacing: 3) {
                if total <= 0 {
                    Capsule().fill(Color.filetFort)
                } else {
                    ForEach(Array(visibles.enumerated()), id: \.offset) { _, part in
                        Capsule()
                            .fill(part.couleur)
                            .frame(width: max((geo.size.width - interstices) * part.valeur / total, hauteur))
                    }
                }
            }
        }
        .frame(height: hauteur)
        .accessibilityHidden(true)
    }
}

/// Segments d'avancement (« 4 sur 7 ») : allumés en crème, les autres en filet.
struct SegmentsAvancement: View {
    var allumes: Int
    var total: Int
    var couleur: Color = .signal

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule()
                    .fill(i < allumes ? couleur : Color.filetFort)
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

/// En-tête de section du poste de pilotage : étiquette à gauche, lien ou repère à droite.
struct TitreSection: View {
    var titre: String
    var repere: String? = nil
    var lien: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titre)
                .etiquetteMaison()
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let lien, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(lien)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 13), weight: .medium))
                    .foregroundStyle(Color.encreDouce)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if let repere {
                Text(repere)
                    .font(Police.mono(11.5))
                    .foregroundStyle(Color.encreDouce)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Bande de chiffres : quelques valeurs côte à côte dans une même tuile, séparées d'un filet
/// (« 22 traitées · 3 en file · 0 bloqué »). Lecture d'ensemble en une ligne.
struct BandeChiffres: View {
    struct Element: Identifiable {
        var valeur: String
        var libelle: String
        var ton: TonInstrument? = nil
        var id: String { libelle }
    }

    var elements: [Element]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
                if index > 0 {
                    Rectangle().fill(Color.filet).frame(width: Espace.filet, height: 34)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(element.valeur)
                        .font(Police.serif(24, relativeTo: .title2))
                        .foregroundStyle(element.ton == .alerte ? Color.rouille : Color.encre)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(element.libelle)
                        .font(.system(size: UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 12)))
                        .foregroundStyle(Color.encreDouce)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, index > 0 ? 14 : 0)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .tuileMaison(rayon: 22)
    }
}

/// Entonnoir des chantiers : une colonne par étape (demande → payé), hauteur selon le nombre de dossiers ;
/// les étapes en cours (acceptée → réalisé) en crème. Toucher une colonne filtre la liste sur cette étape.
struct EntonnoirChantiers: View {
    var comptes: [Int]
    var selection: String
    var choisir: (String) -> Void

    private static let abreges = EtapeDossier.allCases.map(\.abrege)

    var body: some View {
        let maximum = CGFloat(max(comptes.max() ?? 1, 1))
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(EtapeDossier.allCases) { etape in
                let n = comptes.indices.contains(etape.index) ? comptes[etape.index] : 0
                let choisie = selection == etape.rawValue
                Button {
                    choisir(choisie ? "tous" : etape.rawValue)
                } label: {
                    VStack(spacing: 6) {
                        Text("\(n)")
                            .font(Police.mono(12))
                            .foregroundStyle(n > 0 ? Color.encre : Color.encreDouce)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(choisie ? Color.signal
                                  : (2...4).contains(etape.index) ? Color.signal.opacity(0.5) : Color.filetFort)
                            .frame(height: 6 + 44 * CGFloat(n) / maximum)
                        Text(Self.abreges.indices.contains(etape.index) ? Self.abreges[etape.index] : etape.libelle)
                            .font(.system(size: UIFontMetrics(forTextStyle: .caption2).scaledValue(for: 10.5), weight: .medium))
                            .foregroundStyle(choisie ? Color.encre : Color.encreDouce)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(etape.libelle) : \(n) \(n == 1 ? "dossier" : "dossiers")"))
                .accessibilityAddTraits(choisie ? .isSelected : [])
                .accessibilityIdentifier("entonnoir-\(etape.rawValue)")
            }
        }
        .frame(height: 96, alignment: .bottom)
        .animation(.maison, value: selection)
    }
}
