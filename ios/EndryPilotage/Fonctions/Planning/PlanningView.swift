import EndryKit
import SwiftUI
import UIKit

/// Planning multi-semaines : durée réelle de chaque chantier (début → fin), frise de 4 semaines,
/// détail du jour choisi et abonnement au calendrier (`webcal://`).
struct PlanningView: View {
    var modele: ModeleChantiers
    @Environment(\.openURL) private var ouvrirURL
    @State private var decalage = 0
    @State private var jourChoisi = Date()
    @State private var visible = false
    @State private var abonnementCopie = false

    private let semainesFrise = 4

    private var lundi: Date { Planning.lundi(de: Date(), decalage: decalage) }
    private var joursSemaine: [Date] { Planning.jours(depuis: lundi, nombre: 7) }
    private var dossiersDates: [Dossier] { modele.tous.filter { $0.debut != nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.l) {
                    VStack(alignment: .leading, spacing: Espace.xxs) {
                        Text(libelleSemaine).styleSurtitre()
                            .contentTransition(.numericText())
                        Text("Planning").styleTitre(34, relativeTo: .largeTitle).foregroundStyle(Color.encre)
                    }
                    .padding(.top, 56)

                    navigateur
                        .apparitionEnCascade(index: 0, visible: visible)

                    bandeJours
                        .apparitionEnCascade(index: 1, visible: visible)

                    detailJour
                        .apparitionEnCascade(index: 2, visible: visible)

                    frise
                        .apparitionEnCascade(index: 3, visible: visible)

                    abonnement
                        .apparitionEnCascade(index: 4, visible: visible)
                }
                .largeurLisible(Adaptatif.ecran)
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, 120)
                .animation(.endry, value: decalage)
            }
            .scrollIndicators(.hidden)
            .tirerPourActualiser { await modele.charger() }
            .background(FondAmbiant())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            if modele.etat == .initial { await modele.charger() }
            visible = true
        }
    }

    private var libelleSemaine: String {
        guard let premier = joursSemaine.first, let dernier = joursSemaine.last else { return "" }
        return "Semaine du \(DateEndry.jourMois(iso(premier))) au \(DateEndry.jourMois(iso(dernier)))"
    }

    // MARK: - Navigation

    private var navigateur: some View {
        HStack(spacing: Espace.xs) {
            boutonFleche("chevron.left", libelle: "Semaine précédente") { decaler(-1) }
            Spacer()
            if decalage != 0 {
                Button {
                    decaler(-decalage)
                } label: {
                    Text("Aujourd’hui")
                        .styleTexte(13, relativeTo: .footnote, graisse: .semibold)
                        .foregroundStyle(Color.espressoProfond)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .background(Capsule().fill(.degradeOr))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            boutonFleche("chevron.right", libelle: "Semaine suivante") { decaler(1) }
        }
        .sensoryFeedback(.selection, trigger: decalage)
    }

    private func boutonFleche(_ icone: String, libelle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icone)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.encre)
                .frame(width: 44, height: 44)
                .background(Color.surfaceCreuse, in: Circle())
                .overlay(Circle().strokeBorder(Color.or.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(libelle))
    }

    private func decaler(_ n: Int) {
        withAnimation(.endry) {
            decalage += n
            let dans = Planning.jours(depuis: Planning.lundi(de: Date(), decalage: decalage), nombre: 7)
            jourChoisi = dans.first { DateEndry.estAujourdhui($0) } ?? dans.first ?? jourChoisi
        }
    }

    // MARK: - Jours

    private var bandeJours: some View {
        HStack(spacing: Espace.xs) {
            ForEach(joursSemaine, id: \.self) { jour in
                let choisi = DateEndry.memeJour(jour, jourChoisi)
                let aujourdhui = DateEndry.estAujourdhui(jour)
                let nombre = Planning.actifs(le: jour, dans: dossiersDates).count
                Button {
                    withAnimation(.endry) { jourChoisi = jour }
                } label: {
                    VStack(spacing: 6) {
                        Text(DateEndry.jourAbrege(jour))
                            .styleTexte(11, relativeTo: .caption2, graisse: .semibold)
                            .textCase(.uppercase)
                            .foregroundStyle(choisi ? Color.espressoProfond.opacity(0.7) : Color.encrePale)
                        Text("\(DateEndry.numeroJour(jour))")
                            .font(Police.chiffres(20, relativeTo: .title3))
                            .foregroundStyle(choisi ? Color.espressoProfond : Color.encre)
                        HStack(spacing: 2) {
                            ForEach(0..<min(nombre, 3), id: \.self) { _ in
                                Circle().fill(choisi ? Color.espressoProfond : Color.or).frame(width: 4, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(choisi ? AnyShapeStyle(.degradeOr) : AnyShapeStyle(Color.surface))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(aujourdhui && !choisi ? Color.or : Color.or.opacity(0.18), lineWidth: aujourdhui && !choisi ? 1 : 0.5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(DateEndry.longue(jour)), \(nombre) chantier\(nombre > 1 ? "s" : "")"))
                .accessibilityAddTraits(choisi ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: jourChoisi)
    }

    private var detailJour: some View {
        let actifs = Planning.actifs(le: jourChoisi, dans: dossiersDates)
        return VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: DateEndry.longue(jourChoisi).capitalizedPremiere,
                          detail: actifs.isEmpty ? nil : "\(actifs.count) chantier\(actifs.count > 1 ? "s" : "")")
            if actifs.isEmpty {
                HStack(spacing: Espace.s) {
                    Image(systemName: "sun.max").foregroundStyle(Color.or)
                    Text("Aucun chantier ce jour-là.")
                        .styleTexte(15, relativeTo: .subheadline)
                        .foregroundStyle(Color.encreDouce)
                }
                .padding(Espace.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCarte(rayon: 20)
            } else {
                ForEach(actifs) { dossier in ligne(dossier) }
            }
        }
        .animation(.endry, value: jourChoisi)
    }

    private func ligne(_ d: Dossier) -> some View {
        HStack(spacing: Espace.m) {
            Capsule().fill(.degradeOr).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(d.client.isEmpty ? d.titre : d.client)
                    .styleTexte(16, graisse: .semibold).foregroundStyle(Color.encre)
                Text(d.titre)
                    .styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce).lineLimit(1)
                HStack(spacing: Espace.s) {
                    if let dates = Planning.libelleDates(d) {
                        Label(dates, systemImage: "calendar").labelStyle(.titleAndIcon)
                    }
                    if let n = Planning.joursOuvrables(d), n > 1 {
                        Text("\(n) jours")
                    }
                    if let lieu = d.lieu {
                        Label(lieu, systemImage: "mappin.and.ellipse").labelStyle(.titleAndIcon).lineLimit(1)
                    }
                }
                .styleTexte(12, relativeTo: .caption, graisse: .medium)
                .foregroundStyle(Color.encrePale)
            }
            Spacer(minLength: 0)
        }
        .padding(Espace.m)
        .fixedSize(horizontal: false, vertical: true)
        .surfaceCarte(rayon: 20)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Frise 4 semaines

    private var frise: some View {
        let jours = Planning.jours(depuis: lundi, nombre: 7 * semainesFrise)
        let barres = Planning.barres(dossiersDates, depuis: lundi, nombreJours: jours.count)
        return VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: "4 semaines", detail: barres.isEmpty ? nil : "\(barres.count) chantiers")
            VStack(alignment: .leading, spacing: Espace.s) {
                GeometryReader { geo in
                    let pas = geo.size.width / CGFloat(jours.count)
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<semainesFrise, id: \.self) { s in
                            Text("\(DateEndry.jourMois(iso(jours[s * 7])))")
                                .font(Police.chiffres(10, relativeTo: .caption2))
                                .foregroundStyle(Color.encrePale)
                                .offset(x: pas * CGFloat(s * 7))
                        }
                    }
                }
                .frame(height: 14)

                if barres.isEmpty {
                    Text("Aucun chantier daté sur ces 4 semaines.")
                        .styleTexte(13, relativeTo: .footnote)
                        .foregroundStyle(Color.encrePale)
                } else {
                    ForEach(barres) { barre in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(barre.dossier.client.isEmpty ? barre.dossier.titre : barre.dossier.client)
                                .styleTexte(12, relativeTo: .caption, graisse: .semibold)
                                .foregroundStyle(Color.encreDouce)
                                .lineLimit(1)
                            GeometryReader { geo in
                                let pas = geo.size.width / CGFloat(jours.count)
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.surfaceCreuse).frame(height: 8)
                                    UnevenRoundedRectangle(
                                        topLeadingRadius: barre.coupeAvant ? 1 : 4, bottomLeadingRadius: barre.coupeAvant ? 1 : 4,
                                        bottomTrailingRadius: barre.coupeApres ? 1 : 4, topTrailingRadius: barre.coupeApres ? 1 : 4,
                                        style: .continuous)
                                        .fill(.degradeOr)
                                        .frame(width: max(pas * CGFloat(barre.duree), 6), height: 8)
                                        .offset(x: pas * CGFloat(barre.debut))
                                }
                            }
                            .frame(height: 8)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(barre.dossier.client) : \(Planning.libelleDates(barre.dossier) ?? "")"))
                    }
                }
            }
            .padding(Espace.m)
            .overlay(alignment: .topLeading) { ligneAujourdhui(jours: jours) }
            .surfaceCarte(rayon: 22)
        }
    }

    /// Fin trait doré sur la date du jour.
    private func ligneAujourdhui(jours: [Date]) -> some View {
        GeometryReader { geo in
            if let index = jours.firstIndex(where: { DateEndry.estAujourdhui($0) }) {
                let largeur = geo.size.width - Espace.m * 2
                Rectangle()
                    .fill(Color.or.opacity(0.7))
                    .frame(width: 1)
                    .offset(x: Espace.m + largeur / CGFloat(jours.count) * (CGFloat(index) + 0.5))
                    .padding(.vertical, Espace.s)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Abonnement

    private var abonnement: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            HStack(spacing: Espace.s) {
                Image(systemName: "calendar.badge.plus").font(.system(size: 26, weight: .light)).foregroundStyle(Color.or)
                VStack(alignment: .leading, spacing: 2) {
                    Text("S’abonner au planning").styleTitre(17, relativeTo: .headline).foregroundStyle(Color.orClair)
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
                .buttonStyle(BoutonPrincipal())
                Button {
                    UIPasteboard.general.string = url.absoluteString
                    abonnementCopie = true
                } label: {
                    Text(abonnementCopie ? "Adresse copiée" : "Copier l’adresse")
                        .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                        .foregroundStyle(Color.orClair.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 44)
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
        .preferredColorScheme(.dark)
}
