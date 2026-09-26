import EndryKit
import SwiftUI
import UIKit

/// Planning : la semaine sur les chantiers et l'abonnement au calendrier (`webcal://`).
struct PlanningView: View {
    var modele: ModeleChantiers
    @Environment(\.openURL) private var ouvrirURL
    @State private var jourChoisi = Date()
    @State private var visible = false
    @State private var abonnementCopie = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.l) {
                    VStack(alignment: .leading, spacing: Espace.xxs) {
                        Text("Semaine du \(DateEndry.jourMois(iso(DateEndry.semaine(contenant: jourChoisi).first ?? jourChoisi)))").styleSurtitre()
                        Text("Planning").styleTitre(34, relativeTo: .largeTitle).foregroundStyle(Color.encre)
                    }
                    .padding(.top, Espace.m)

                    bandeJours
                        .apparitionEnCascade(index: 0, visible: visible)

                    VStack(alignment: .leading, spacing: Espace.s) {
                        let jour = chantiers(du: jourChoisi)
                        EnTeteSection(titre: DateEndry.longue(jourChoisi).capitalizedPremiere)
                        if jour.isEmpty {
                            Text("Aucun chantier ne commence ce jour-là.")
                                .styleTexte(14, relativeTo: .subheadline)
                                .foregroundStyle(Color.encrePale)
                                .padding(.vertical, Espace.s)
                        } else {
                            ForEach(jour) { item in ligne(item) }
                        }
                    }
                    .animation(.snappy, value: jourChoisi)
                    .apparitionEnCascade(index: 1, visible: visible)

                    if !modele.semaine.isEmpty {
                        SemaineChantiers(semaine: modele.semaine)
                            .apparitionEnCascade(index: 2, visible: visible)
                    }

                    abonnement
                        .apparitionEnCascade(index: 3, visible: visible)
                }
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .tirerPourActualiser { await modele.charger() }
            .background(Color.fond)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            if modele.etat == .initial { await modele.charger() }
            visible = true
        }
    }

    private var bandeJours: some View {
        HStack(spacing: Espace.xs) {
            ForEach(DateEndry.semaine(contenant: jourChoisi), id: \.self) { jour in
                let choisi = DateEndry.memeJour(jour, jourChoisi)
                let aujourdhui = DateEndry.estAujourdhui(jour)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { jourChoisi = jour }
                } label: {
                    VStack(spacing: 6) {
                        Text(DateEndry.jourAbrege(jour))
                            .styleTexte(11, relativeTo: .caption2, graisse: .semibold)
                            .textCase(.uppercase)
                            .foregroundStyle(choisi ? Color.orClair : Color.encrePale)
                        Text("\(DateEndry.numeroJour(jour))")
                            .styleTitre(20, relativeTo: .title3)
                            .foregroundStyle(choisi ? Color.orClair : Color.encre)
                        Circle()
                            .fill(chantiers(du: jour).isEmpty ? Color.clear : (choisi ? Color.or : Color.bronze))
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(choisi ? AnyShapeStyle(Color.espresso) : AnyShapeStyle(Color.surface))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(aujourdhui && !choisi ? Color.bronze : Color.filet, lineWidth: aujourdhui && !choisi ? 1 : 0.5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(DateEndry.longue(jour)))
                .accessibilityAddTraits(choisi ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: jourChoisi)
    }

    private func ligne(_ item: Semaine) -> some View {
        HStack(spacing: Espace.m) {
            Rectangle().fill(.degradeOr).frame(width: 3).clipShape(Capsule())
            VStack(alignment: .leading, spacing: 4) {
                Text(item.titre).styleTexte(16, graisse: .semibold).foregroundStyle(Color.encre)
                Text([item.lieu, item.dates].compactMap { $0 }.joined(separator: " · "))
                    .styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
            }
            Spacer()
        }
        .padding(Espace.m)
        .surfaceCarte(rayon: 20)
        .accessibilityElement(children: .combine)
    }

    private var abonnement: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            HStack(spacing: Espace.s) {
                Image(systemName: "calendar.badge.plus").font(.system(size: 26, weight: .light)).foregroundStyle(Color.or)
                VStack(alignment: .leading, spacing: 2) {
                    Text("S’abonner au planning").styleTitre(18, relativeTo: .headline).foregroundStyle(Color.orClair)
                    Text("Les chantiers apparaissent dans Calendrier et se mettent à jour seuls.")
                        .styleTexte(13, relativeTo: .footnote)
                        .foregroundStyle(Color.orClair.opacity(0.65))
                }
            }
            if let url = modele.urlAbonnement {
                Button {
                    ouvrirURL(url)
                } label: {
                    Label("Ajouter à Calendrier", systemImage: "plus")
                }
                .buttonStyle(BoutonPrincipal(couleur: .or))
                Button {
                    UIPasteboard.general.string = url.absoluteString
                    abonnementCopie = true
                } label: {
                    Text(abonnementCopie ? "Adresse copiée" : "Copier l’adresse")
                        .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                        .foregroundStyle(Color.orClair.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
                .sensoryFeedback(.success, trigger: abonnementCopie)
            } else {
                Text("Adresse du calendrier indisponible pour le moment.")
                    .styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.orClair.opacity(0.6))
            }
        }
        .padding(Espace.l)
        .background(MatiereEspresso())
    }

    private func chantiers(du jour: Date) -> [Semaine] {
        modele.semaine.filter { item in
            guard let debut = item.dateDebut else { return false }
            return DateEndry.memeJour(debut, jour)
        }
    }

    private func iso(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = DateEndry.fuseau
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

extension String {
    /// « lundi 28 septembre » → « Lundi 28 septembre ».
    var capitalizedPremiere: String { prefix(1).uppercased() + dropFirst() }
}

#Preview("Planning — démo") {
    let app = ModeleApp()
    app.activerDemo()
    return PlanningView(modele: app.chantiers!)
        .environment(app)
}
