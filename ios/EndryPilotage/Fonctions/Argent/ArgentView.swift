import EndryKit
import SwiftUI

/// Argent : suivi seulement. Aucune relance, aucun paiement depuis l'app.
struct ArgentView: View {
    @AppStorage(ModeDevantClient.cle) private var devantClient = false
    @Environment(ModeleApp.self) private var app
    var modele: ModeleArgent
    @State private var visible = false
    @State private var clientsDeplies: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.xl) {
                    VStack(alignment: .leading, spacing: Espace.xxs) {
                        Text("Finances").styleTitre(34, relativeTo: .largeTitle).foregroundStyle(Color.encre)
                        Label("Suivi seulement : aucune relance sans votre demande.", systemImage: "hand.raised")
                            .styleTexte(13, relativeTo: .footnote, graisse: .medium)
                            .foregroundStyle(Color.encreDouce)
                    }
                    .padding(.top, Espace.m)

                    if modele.horsLigne {
                        BandeauHorsLigne(majLe: modele.majLe)
                    }

                    switch modele.etat {
                    case .chargement where modele.argent == nil, .initial:
                        Squelette(hauteur: 220, rayon: Espace.rayon)
                        Squelette(hauteur: 160, rayon: Espace.rayon)
                    case .erreur(let erreur) where modele.argent == nil:
                        VueErreur(erreur: erreur) { Task { await modele.charger() } }
                    default:
                        if let argent = modele.argent {
                            encaisser(argent.encaisser).apparitionEnCascade(index: 0, visible: visible)
                            if devantClient {
                                BlocMasqueClient(titre: "À payer").apparitionEnCascade(index: 1, visible: visible)
                            } else {
                                payer(argent.payer).apparitionEnCascade(index: 1, visible: visible)
                            }
                            offres(argent.offres).apparitionEnCascade(index: 2, visible: visible)
                            CarteOffresASuivre(offres: argent.offres.offres).apparitionEnCascade(index: 2, visible: visible)
                            if !devantClient {
                                refacturer(argent.aRefacturer).apparitionEnCascade(index: 3, visible: visible)
                            }
                            versements(argent.versementsNonIdentifies).apparitionEnCascade(index: 4, visible: visible)
                            if let heures = argent.heuresSecretariat {
                                secretariat(heures).apparitionEnCascade(index: 5, visible: visible)
                            }
                        }
                    }
                }
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, 120)
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

    // MARK: - À encaisser

    private func encaisser(_ e: Encaisser) -> some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            VStack(alignment: .leading, spacing: Espace.xs) {
                Text("À encaisser").styleSurtitre()
                MontantAnime(montant: e.total, taille: 44, dore: true).refletDore()
            }
            BarreAnciennete(segments: [
                .init(libelle: "À échoir", montant: e.anciennete.aEchoir, couleur: .or),
                .init(libelle: "0–30 j", montant: e.anciennete.jours0a30, couleur: .bronzeMoyen),
                .init(libelle: "31–60 j", montant: e.anciennete.jours31a60, couleur: Color(hex: 0xC4583C)),
                .init(libelle: "> 60 j", montant: e.anciennete.plus60, couleur: .rouille),
            ])

            VStack(spacing: 0) {
                ForEach(Array(e.parClient.enumerated()), id: \.element.id) { index, groupe in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.endry) {
                                if clientsDeplies.contains(groupe.client) { clientsDeplies.remove(groupe.client) } else { clientsDeplies.insert(groupe.client) }
                            }
                        } label: {
                            HStack(spacing: Espace.s) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(groupe.client).styleTexte(15, relativeTo: .subheadline, graisse: .semibold).foregroundStyle(Color.encre)
                                    Text(libelleRetard(groupe.retardMax) + " · \(groupe.factures.count) facture\(groupe.factures.count > 1 ? "s" : "")")
                                        .styleTexte(12, relativeTo: .caption, graisse: .medium)
                                        .foregroundStyle(couleurRetard(groupe.retardMax))
                                }
                                Spacer()
                                MontantView(montant: groupe.montant, taille: 16, style: .subheadline)
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.encrePale)
                                    .rotationEffect(.degrees(clientsDeplies.contains(groupe.client) ? 180 : 0))
                            }
                            .padding(.vertical, Espace.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if clientsDeplies.contains(groupe.client) {
                            ForEach(groupe.factures) { facture in
                                Button {
                                    Task { await app.documents.ouvrir(facture.cheminPDF, nom: "\(facture.numero).pdf", api: app.session.api) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(facture.titre).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encre).lineLimit(1)
                                            HStack(spacing: 6) {
                                                Text(facture.numero).font(Police.reference(11)).foregroundStyle(Color.encrePale)
                                                if let echeance = facture.echeance {
                                                    Text("· éch. \(DateEndry.courte(echeance))").styleTexte(11, relativeTo: .caption2).foregroundStyle(Color.encrePale)
                                                }
                                            }
                                        }
                                        Spacer()
                                        MontantView(montant: facture.montant, taille: 13, style: .footnote)
                                        Image(systemName: "doc.richtext").font(.caption).foregroundStyle(Color.bronze)
                                    }
                                    .padding(.leading, Espace.s)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            .padding(.bottom, Espace.xs)
                        }
                    }
                    if index < e.parClient.count - 1 {
                        Rectangle().fill(Color.filet).frame(height: 0.5)
                    }
                }
            }
        }
        .padding(Espace.l)
        .surfaceCarte()
    }

    private func libelleRetard(_ jours: Int) -> String {
        jours <= 0 ? "À échoir" : "\(jours) j de retard"
    }

    private func couleurRetard(_ jours: Int) -> Color {
        switch jours {
        case ...0: .vertControle
        case 1...30: .ambre
        default: .rouille
        }
    }

    // MARK: - À payer

    private func payer(_ p: Payer) -> some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: "À payer", detail: FormatSuisse.chfArrondi(p.total))
            VStack(spacing: 0) {
                ForEach(p.factures.sorted { ($0.joursRestants ?? 999) < ($1.joursRestants ?? 999) }) { f in
                    LigneFournisseur(facture: f)
                    if f.id != p.factures.last?.id { Rectangle().fill(Color.filet).frame(height: 0.5) }
                }
            }
            .padding(.horizontal, Espace.m)
            .surfaceCarte(rayon: 22)
            Text("Les paiements se signent dans l’e-banking ; l’app n’émet aucun paiement.")
                .styleTexte(12, relativeTo: .caption)
                .foregroundStyle(Color.encrePale)
        }
    }

    // MARK: - Offres

    private func offres(_ o: Offres) -> some View {
        let maximum = max(o.offres.map(\.montant).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: "Offres en attente", detail: FormatSuisse.chfArrondi(o.total))
            VStack(alignment: .leading, spacing: Espace.m) {
                ForEach(o.offres) { offre in
                    Button {
                        Task { await app.documents.ouvrir(offre.cheminPDF, nom: "\(offre.numero).pdf", api: app.session.api) }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(offre.client).styleTexte(15, relativeTo: .subheadline, graisse: .semibold).foregroundStyle(Color.encre)
                                Spacer()
                                MontantView(montant: offre.montant, taille: 15, afficherCentimes: false, style: .subheadline)
                            }
                            BarreProportion(fraction: offre.montant / maximum)
                            HStack(spacing: 6) {
                                Text(offre.numero).font(Police.reference(11)).foregroundStyle(Color.encrePale)
                                Text("· \(offre.titre)").styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encreDouce).lineLimit(1)
                                Spacer()
                                if let fin = offre.valableJusquAu {
                                    Text("jusqu’au \(DateEndry.jourMois(fin))").styleTexte(11, relativeTo: .caption2).foregroundStyle(Color.encrePale)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Espace.l)
            .surfaceCarte(rayon: 22)
        }
    }

    // MARK: - À refacturer

    private func refacturer(_ r: ARefacturer) -> some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: "Matériel à refacturer", detail: FormatSuisse.chfArrondi(r.total))
            if r.achats.isEmpty {
                Text("Rien à refacturer.").styleTexte(14, relativeTo: .subheadline).foregroundStyle(Color.encrePale)
            } else {
                VStack(spacing: 0) {
                    ForEach(r.achats) { achat in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(achat.libelle).styleTexte(14, relativeTo: .subheadline, graisse: .semibold).foregroundStyle(Color.encre)
                                Text([achat.chantier, achat.fournisseur].compactMap { $0 }.joined(separator: " · "))
                                    .styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encreDouce)
                            }
                            Spacer()
                            MontantView(montant: achat.montant, taille: 14, style: .subheadline)
                        }
                        .padding(.vertical, Espace.s)
                        .accessibilityElement(children: .combine)
                        if achat.id != r.achats.last?.id { Rectangle().fill(Color.filet).frame(height: 0.5) }
                    }
                }
                .padding(.horizontal, Espace.m)
                .surfaceCarte(rayon: 22)
            }
        }
    }

    // MARK: - Versements

    private func versements(_ v: [VersementNonIdentifie]) -> some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: "Versements non identifiés", detail: v.isEmpty ? nil : "\(v.count)")
            if v.isEmpty {
                Text("Tous les versements sont rapprochés.").styleTexte(14, relativeTo: .subheadline).foregroundStyle(Color.encrePale)
            } else {
                VStack(spacing: 0) {
                    ForEach(v) { versement in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(versement.titre).styleTexte(14, relativeTo: .subheadline, graisse: .semibold).foregroundStyle(Color.encre).lineLimit(1)
                                if let texte = versement.texte, versement.contrepartie != nil {
                                    Text(texte).font(Police.reference(11)).foregroundStyle(Color.encreDouce).lineLimit(2)
                                }
                                if let reference = versement.reference {
                                    Text(reference).font(Police.reference(10)).foregroundStyle(Color.encrePale).lineLimit(1)
                                }
                                if let date = versement.date {
                                    Text(DateEndry.courte(date)).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
                                }
                            }
                            Spacer()
                            MontantView(montant: versement.montant, taille: 14, couleur: .vertControle, style: .subheadline)
                        }
                        .padding(.vertical, Espace.s)
                        .accessibilityElement(children: .combine)
                        if versement.id != v.last?.id { Rectangle().fill(Color.filet).frame(height: 0.5) }
                    }
                }
                .padding(.horizontal, Espace.m)
                .surfaceCarte(rayon: 22)
            }
        }
    }

    // MARK: - Secrétariat

    private func secretariat(_ h: HeuresSecretariat) -> some View {
        HStack(alignment: .center, spacing: Espace.m) {
            ZStack {
                Circle().fill(Color.or.opacity(0.16))
                Image(systemName: "clock").font(.system(size: 20, weight: .medium)).foregroundStyle(Color.bronze)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Heures de secrétariat").styleTexte(15, relativeTo: .subheadline, graisse: .semibold).foregroundStyle(Color.encre)
                Text(h.mois).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(FormatSuisse.heures(h.heures)).styleTitre(22, relativeTo: .title3).foregroundStyle(Color.encre)
                if let montant = h.montant {
                    Text(FormatSuisse.chf(montant)).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encreDouce).monospacedDigit()
                }
            }
        }
        .padding(Espace.l)
        .surfaceCarte()
        .accessibilityElement(children: .combine)
    }
}

/// Barre proportionnelle animée (offres).
struct BarreProportion: View {
    var fraction: Double
    @State private var visible = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surfaceCreuse)
                Capsule().fill(.degradeOr).frame(width: geo.size.width * (visible ? max(0.02, min(fraction, 1)) : 0.02))
            }
        }
        .frame(height: 6)
        .onAppear { withAnimation(.endry.delay(0.15)) { visible = true } }
        .accessibilityHidden(true)
    }
}

#Preview("Argent — démo") {
    let app = ModeleApp()
    app.activerDemo()
    return ArgentView(modele: app.argent!)
        .environment(app)
}
