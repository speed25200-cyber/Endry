import EndryKit
import SwiftUI

/// Accueil Maison Endry : la semaine en un coup d'œil. Sept colonnes (lundi → dimanche), le jour présent marqué d'un
/// repère, les chantiers en bandes de verre du jour de début au jour de fin. Toucher : Planning.
struct FriseSemaineView: View {
    var semaine: [Semaine]
    var ouvrir: () -> Void

    private var jours: [Date] { DateEndry.semaine() }

    var body: some View {
        let bandes = FriseSemaine.bandes(semaine, jours: jours)
        Button(action: ouvrir) {
            VStack(alignment: .leading, spacing: Espace.s) {
                HStack {
                    Text("La semaine")
                        .font(Police.etiquette(Echelle.micro))
                        .textCase(.uppercase)
                        .tracking(2.2)
                        .foregroundStyle(Color.bronze)
                    Spacer()
                    Text("Planning")
                        .styleTexte(12, relativeTo: .caption, graisse: .semibold)
                        .foregroundStyle(Color.bronze)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.bronze)
                }
                GeometryReader { geo in
                    let colonne = geo.size.width / 7
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            ForEach(Array(jours.enumerated()), id: \.offset) { _, jour in
                                let aujourdhui = DateEndry.estAujourdhui(jour)
                                VStack(spacing: 3) {
                                    Text(DateEndry.jourAbrege(jour).prefix(2))
                                        .font(.system(size: 10, weight: .medium))
                                        .textCase(.uppercase)
                                        .foregroundStyle(aujourdhui ? Color.bronze : Color.encrePale)
                                    Text("\(DateEndry.numeroJour(jour))")
                                        .font(.system(size: 14, weight: aujourdhui ? .semibold : .regular).monospacedDigit())
                                        .foregroundStyle(aujourdhui ? Color.encre : Color.encreDouce)
                                    Circle()
                                        .fill(aujourdhui ? Color.bronze : .clear)
                                        .frame(width: 4, height: 4)
                                }
                                .frame(width: colonne)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(Color.filet).frame(width: Espace.filet).padding(.top, 44)
                                }
                            }
                        }
                        ForEach(Array(bandes.enumerated()), id: \.element.id) { rang, bande in
                            let largeur = CGFloat(bande.fin - bande.debut + 1) * colonne - 4
                            Text(bande.titre)
                                .styleTexte(11.5, relativeTo: .caption, graisse: .medium)
                                .foregroundStyle(Color.encre)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .frame(width: max(largeur, 24), height: 22, alignment: .leading)
                                .background(Color.bronze.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.bordureOr, lineWidth: Espace.filet))
                                .offset(x: CGFloat(bande.debut) * colonne + 2, y: 52 + CGFloat(rang) * 26)
                        }
                    }
                }
                .frame(height: 52 + CGFloat(max(bandes.count, 1)) * 26)
                if bandes.isEmpty {
                    Text("Aucun chantier planifié cette semaine.")
                        .styleTexte(12, relativeTo: .caption)
                        .foregroundStyle(Color.encrePale)
                        .padding(.top, -20)
                }
            }
            .padding(Espace.m)
            .surfaceCarte(rayon: Espace.rayon)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("La semaine : " + (bandes.isEmpty ? "aucun chantier" : bandes.map(\.titre).joined(separator: ", "))))
        .accessibilityHint(Text("Ouvre le planning"))
        .accessibilityIdentifier("frise-semaine")
    }
}
