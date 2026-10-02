import EndryKit
import SwiftUI

/// Accueil Maison Endry : la frise. Les chantiers de la semaine en pastilles posées au-dessus d'un axe gradué
/// (lundi → dimanche), le repère « maintenant » en signal crème. Le PC ne donne pas d'heures : la frise compte
/// en jours, sans rien inventer. Toucher : Planning.
struct FriseSemaineView: View {
    var semaine: [Semaine]
    var ouvrir: () -> Void

    private var jours: [Date] { DateEndry.semaine() }

    var body: some View {
        let jours = self.jours
        let bandes = FriseSemaine.bandes(semaine, jours: jours, maximum: 4)
        Button(action: ouvrir) {
            VStack(alignment: .leading, spacing: 10) {
                if bandes.isEmpty {
                    Text("Aucun chantier planifié cette semaine")
                        .font(Police.mono(11.5))
                        .foregroundStyle(Color.encreDouce)
                        .frame(height: 30)
                } else {
                    DispositionFrise(colonnes: bandes.map(\.debut)) {
                        ForEach(bandes) { bande in
                            puce(bande, jours: jours)
                        }
                    }
                }
                AxeSemaine(jours: jours)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("La semaine : " + (bandes.isEmpty ? "aucun chantier" : bandes.map(\.titre).joined(separator: ", "))))
        .accessibilityHint(Text("Ouvre le planning"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("frise-semaine")
    }

    private func puce(_ bande: FriseSemaine.Bande, jours: [Date]) -> some View {
        HStack(spacing: 6) {
            Text(Self.plage(bande, jours: jours))
                .font(Police.mono(11.5))
                .foregroundStyle(Color.encreDouce)
            Text(Self.titreCourt(bande.titre))
                .styleTexte(13, relativeTo: .caption)
                .foregroundStyle(Color.encre)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .verreMaison(Capsule())
    }

    /// « Lu », ou « Lu–Ve » pour un chantier de plusieurs jours (« …–Di » s'il continue la semaine suivante).
    static func plage(_ bande: FriseSemaine.Bande, jours: [Date]) -> String {
        func jour(_ i: Int) -> String {
            jours.indices.contains(i) ? DateEndry.jourAbrege(jours[i]).prefix(2).capitalized : ""
        }
        return bande.fin > bande.debut ? "\(jour(bande.debut))–\(jour(bande.fin))" : jour(bande.debut)
    }

    /// « Villa Morel — PAC air-eau 10 kW » → « Villa Morel ».
    static func titreCourt(_ titre: String) -> String {
        let morceaux = titre.components(separatedBy: " — ")
        return (morceaux.first ?? titre).trimmingCharacters(in: .whitespaces)
    }
}

/// Place les pastilles à la colonne de leur jour de début, sans chevauchement (une rangée de plus au besoin)
/// et sans dépasser le bord droit.
struct DispositionFrise: Layout {
    var colonnes: [Int]
    var hauteur: CGFloat = 30
    var ecart: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? 320
        let rangs = (placer(largeur, subviews).map(\.rang).max() ?? 0) + 1
        return CGSize(width: largeur, height: CGFloat(rangs) * hauteur + CGFloat(rangs - 1) * ecart)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, place) in placer(bounds.width, subviews).enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + place.x, y: bounds.minY + CGFloat(place.rang) * (hauteur + ecart)),
                                  proposal: ProposedViewSize(width: place.largeur, height: hauteur))
        }
    }

    private func placer(_ largeur: CGFloat, _ subviews: Subviews) -> [(x: CGFloat, largeur: CGFloat, rang: Int)] {
        let colonne = largeur / 7
        var fins: [CGFloat] = []
        var resultat: [(x: CGFloat, largeur: CGFloat, rang: Int)] = []
        for (index, vue) in subviews.enumerated() {
            let l = min(vue.sizeThatFits(.unspecified).width, largeur * 0.62)
            let debut = colonnes.indices.contains(index) ? colonnes[index] : 0
            let voulu = max(0, min(CGFloat(debut) * colonne, largeur - l))
            // Sur la première rangée qui a la place, juste après la pastille précédente si elle déborde sur ce jour.
            var place: (x: CGFloat, rang: Int)?
            for (rang, fin) in fins.enumerated() {
                let x = max(voulu, fin + 8)
                if x + l <= largeur { place = (x, rang); break }
            }
            let (x, rang) = place ?? (voulu, fins.count)
            if rang == fins.count { fins.append(0) }
            fins[rang] = x + l
            resultat.append((x, l, rang))
        }
        return resultat
    }
}

/// Axe de la frise : filet, graduations (jours et demi-journées), repère « maintenant », jours en mono.
struct AxeSemaine: View {
    var jours: [Date]
    var maintenant = Date()

    private var positionMaintenant: CGFloat? {
        guard let index = jours.firstIndex(where: { DateEndry.memeJour($0, maintenant) }) else { return nil }
        let debut = Calendar(identifier: .gregorian).startOfDay(for: maintenant)
        let fraction = min(max(maintenant.timeIntervalSince(debut) / 86_400, 0), 1)
        return (CGFloat(index) + CGFloat(fraction)) / 7
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                Canvas { ctx, taille in
                    let y: CGFloat = 11
                    var ligne = Path()
                    ligne.move(to: CGPoint(x: 0, y: y))
                    ligne.addLine(to: CGPoint(x: taille.width, y: y))
                    ctx.stroke(ligne, with: .color(.filetFort), lineWidth: 0.5)
                    for i in 0...14 {
                        let x = min(max(CGFloat(i) * taille.width / 14, 0.25), taille.width - 0.25)
                        let majeur = i.isMultiple(of: 2)
                        var trait = Path()
                        trait.move(to: CGPoint(x: x, y: y - (majeur ? 5 : 3)))
                        trait.addLine(to: CGPoint(x: x, y: y + (majeur ? 4 : 2)))
                        ctx.stroke(trait, with: .color(.filetFort), lineWidth: 0.5)
                    }
                }
                .frame(height: 22)
                if let p = positionMaintenant {
                    GeometryReader { geo in
                        let x = geo.size.width * p
                        Rectangle().fill(Color.signal)
                            .frame(width: 1, height: 22)
                            .offset(x: x - 0.5)
                        Circle().fill(Color.signal)
                            .frame(width: 7, height: 7)
                            .background(Circle().fill(Color.signalHalo).frame(width: 15, height: 15))
                            .offset(x: x - 3.5, y: 7.5)
                    }
                    .frame(height: 22)
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(jours.enumerated()), id: \.offset) { _, jour in
                    let aujourdhui = DateEndry.memeJour(jour, maintenant)
                    Text("\(DateEndry.jourAbrege(jour).prefix(2).capitalized) \(DateEndry.numeroJour(jour))")
                        .font(Police.mono(11))
                        .foregroundStyle(aujourdhui ? Color.signal : Color.encreDouce)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
