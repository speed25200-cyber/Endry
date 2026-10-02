import EndryKit
import SwiftUI

/// Finances « Maison Endry » (maquette E) : vues À encaisser / À payer / Offres, grand montant, histogramme,
/// lignes avec leur état (« Suivi seulement » : jamais de relance), heures du secrétariat (documents du bureau),
/// nouvelle offre / nouvelle facture. Suivi seulement : aucune relance, aucun paiement depuis l'app.
struct ArgentView: View {
    @AppStorage(ModeDevantClient.cle) private var devantClient = false
    @Environment(ModeleApp.self) private var app
    var modele: ModeleArgent
    @State private var visible = false
    @State private var heuresOuvertes: HeuresSecretariat?
    @State private var vue: VueFinances = .encaisser

    enum VueFinances: Hashable {
        case encaisser, payer, offres
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Finances · \(DateEndry.nomMois(Date()))")
                        .etiquetteMaison()
                        .padding(.top, Espace.l)
                        .accessibilityAddTraits(.isHeader)

                    SelecteurSegments(options: [
                        OptionSegment(valeur: VueFinances.encaisser, titre: "À encaisser"),
                        OptionSegment(valeur: .payer, titre: "À payer"),
                        OptionSegment(valeur: .offres, titre: "Offres"),
                    ], selection: $vue)
                    .padding(.top, 14)

                    if modele.horsLigne {
                        BandeauHorsLigne(majLe: modele.majLe)
                            .padding(.top, Espace.s)
                    }

                    switch modele.etat {
                    case .chargement where modele.argent == nil, .initial:
                        Squelette(hauteur: 120, rayon: 22).padding(.top, Espace.l)
                        Squelette(hauteur: 220, rayon: 22).padding(.top, Espace.s)
                    case .erreur(let erreur) where modele.argent == nil:
                        VueErreur(erreur: erreur) { Task { await modele.charger() } }
                            .padding(.top, Espace.l)
                    default:
                        if let argent = modele.argent {
                            Group {
                                switch vue {
                                case .encaisser: encaisser(argent)
                                case .payer: payer(argent)
                                case .offres: offres(argent)
                                }
                            }
                            .id(vue)
                            .transition(.opacity)
                            .apparitionEnCascade(index: 0, visible: visible)

                            if let heures = argent.heuresSecretariat {
                                secretariat(heures)
                                    .padding(.top, Espace.xl)
                                    .apparitionEnCascade(index: 1, visible: visible)
                            }
                        }
                    }

                    // Le patron décrit ; l'assistant prépare dans Bexio ; rien ne part sans son Oui.
                    RangeeNouveauDocument()
                        .padding(.top, Espace.l)
                }
                .largeurLisible(Adaptatif.ecran)
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, 120)
                .animation(.endry, value: vue)
            }
            .scrollIndicators(.hidden)
            .tirerPourActualiser { await modele.charger() }
            .background(FondMaison(photo: nil))
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            if modele.etat == .initial { await modele.charger() }
            visible = true
            if let signees = app.offresSignees, signees.etat == .initial {
                await signees.charger(chantiers: app.chantiers?.tous ?? [])
            }
        }
    }

    // MARK: - Grand montant

    private func grandMontant(_ titre: String, _ montant: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre)
                .styleTexte(13, relativeTo: .footnote)
                .foregroundStyle(Color.encreDouce)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("CHF")
                    .font(Police.mono(11))
                    .foregroundStyle(Color.encreDouce)
                Text(FormatSuisse.francs(montant))
                    .font(Police.serif(64, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(Color.encre)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: montant))
            }
        }
        .padding(.top, Espace.l)
        .accessibilityElement(children: .combine)
    }

    // MARK: - À encaisser

    @ViewBuilder
    private func encaisser(_ argent: Argent) -> some View {
        let e = argent.encaisser
        VStack(alignment: .leading, spacing: 0) {
            grandMontant("À encaisser · \(e.factures.count) facture\(e.factures.count > 1 ? "s" : "") ouverte\(e.factures.count > 1 ? "s" : "")", e.total)
            Histogramme(barres: [
                .init(libelle: "À échoir", valeur: e.anciennete.aEchoir, accent: true),
                .init(libelle: "0–30 j", valeur: e.anciennete.jours0a30),
                .init(libelle: "31–60 j", valeur: e.anciennete.jours31a60),
                .init(libelle: "> 60 j", valeur: e.anciennete.plus60),
            ])
            .padding(.top, Espace.m)

            VStack(spacing: 10) {
                ForEach(e.factures.sorted { $0.retardJours > $1.retardJours }) { facture in
                    Button {
                        Task { await app.documents.ouvrir(facture.cheminPDF, nom: "\(facture.numero).pdf", api: app.session.api) }
                    } label: {
                        LigneMaison(titre: facture.client,
                                    detail: facture.numero + " · " + echeanceClient(facture),
                                    montant: FormatSuisse.francs(facture.montant),
                                    etat: facture.retardJours > 0 ? "Suivi seulement" : "Envoyée")
                    }
                    .buttonStyle(ActionPressee())
                    .accessibilityHint(Text("Ouvre la facture"))
                }
            }
            .padding(.top, Espace.l)

            if !argent.versementsNonIdentifies.isEmpty {
                Text("Versements non identifiés").etiquetteMaison().padding(.top, Espace.xl)
                VStack(spacing: 10) {
                    ForEach(argent.versementsNonIdentifies) { v in
                        LigneMaison(titre: v.titre,
                                    detail: [v.date.map { DateEndry.courte($0) }, v.reference].compactMap { $0 }.joined(separator: " · "),
                                    montant: FormatSuisse.francs(v.montant),
                                    etat: "À rapprocher", etatAccent: true)
                    }
                }
                .padding(.top, Espace.s)
            }
            Text("Suivi seulement : aucune relance ne part sans votre demande.")
                .font(Police.mono(10))
                .foregroundStyle(Color.encreDouce)
                .padding(.top, Espace.s)
        }
    }

    private func echeanceClient(_ f: FactureClient) -> String {
        if f.retardJours > 0 { return "échue depuis \(f.retardJours) j" }
        if let echeance = f.echeance { return "échéance \(DateEndry.jourMois(echeance))" }
        return "ouverte"
    }

    // MARK: - À payer

    @ViewBuilder
    private func payer(_ argent: Argent) -> some View {
        let p = argent.payer
        if devantClient {
            BlocMasqueClient(titre: "À payer").padding(.top, Espace.l)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                grandMontant("À payer · \(p.factures.count) facture\(p.factures.count > 1 ? "s" : "")", p.total)
                Histogramme(barres: Self.barresPayer(p.factures)).padding(.top, Espace.m)
                VStack(spacing: 10) {
                    ForEach(p.factures.sorted { ($0.joursRestants ?? 999) < ($1.joursRestants ?? 999) }) { f in
                        LigneMaison(titre: f.fournisseur,
                                    detail: f.numero + (f.echeance.map { " · éch. \(DateEndry.courte($0))" } ?? ""),
                                    montant: FormatSuisse.francs(f.montant),
                                    etat: f.joursRestants.map { $0 < 0 ? "échue" : $0 == 0 ? "aujourd’hui" : "dans \($0) j" },
                                    etatAlerte: (f.joursRestants ?? 99) <= 3)
                    }
                }
                .padding(.top, Espace.l)
                Text("Les paiements se signent dans l’e-banking ; l’app n’émet aucun paiement.")
                    .font(Police.mono(10))
                    .foregroundStyle(Color.encreDouce)
                    .padding(.top, Espace.s)

                if !argent.aRefacturer.achats.isEmpty {
                    Text("Matériel à refacturer").etiquetteMaison().padding(.top, Espace.xl)
                    VStack(spacing: 10) {
                        ForEach(argent.aRefacturer.achats) { achat in
                            LigneMaison(titre: achat.libelle,
                                        detail: [achat.chantier, achat.fournisseur].compactMap { $0 }.joined(separator: " · "),
                                        montant: FormatSuisse.francs(achat.montant),
                                        etat: "À refacturer", etatAccent: true)
                        }
                    }
                    .padding(.top, Espace.s)
                }
            }
        }
    }

    /// Échéances à payer regroupées : échues, sous 7, 14 et 30 jours, plus tard.
    static func barresPayer(_ factures: [FactureFournisseur]) -> [Histogramme.Barre] {
        func somme(_ filtre: (Int) -> Bool) -> Double {
            factures.filter { filtre($0.joursRestants ?? 999) }.reduce(0) { $0 + $1.montant }
        }
        return [
            .init(libelle: "Échues", valeur: somme { $0 < 0 }),
            .init(libelle: "7 j", valeur: somme { (0...7).contains($0) }, accent: true),
            .init(libelle: "14 j", valeur: somme { (8...14).contains($0) }),
            .init(libelle: "30 j", valeur: somme { (15...30).contains($0) }),
            .init(libelle: "Plus tard", valeur: somme { $0 > 30 }),
        ]
    }

    // MARK: - Offres

    @ViewBuilder
    private func offres(_ argent: Argent) -> some View {
        let o = argent.offres
        VStack(alignment: .leading, spacing: 0) {
            grandMontant("Offres en attente · \(o.offres.count)", o.total)
            if !o.offres.isEmpty {
                let plusGrande = o.offres.map(\.montant).max()
                Histogramme(barres: o.offres.prefix(8).map {
                    .init(libelle: String($0.numero.suffix(3)), valeur: $0.montant, accent: $0.montant == plusGrande)
                })
                .padding(.top, Espace.m)
            }
            if let signees = app.offresSignees {
                SectionOffresSignees(modele: signees).padding(.top, Espace.l)
            }
            VStack(spacing: 10) {
                ForEach(o.offres) { offre in
                    Button {
                        Task { await app.documents.ouvrir(offre.cheminPDF, nom: "\(offre.numero).pdf", api: app.session.api) }
                    } label: {
                        LigneMaison(titre: offre.client,
                                    detail: offre.numero + " · " + offre.titre,
                                    montant: FormatSuisse.francs(offre.montant),
                                    etat: offre.valableJusquAu.map { "jusqu’au \(DateEndry.jourMois($0))" })
                    }
                    .buttonStyle(ActionPressee())
                    .accessibilityHint(Text("Ouvre l’offre"))
                }
            }
            .padding(.top, Espace.l)
            CarteOffresASuivre(offres: o.offres).padding(.top, Espace.l)
        }
    }

    // MARK: - Secrétariat

    private func secretariat(_ h: HeuresSecretariat) -> some View {
        Button { heuresOuvertes = h } label: {
            HStack(alignment: .center, spacing: Espace.s) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Secrétariat").etiquetteMaison()
                    Text(FormatSuisse.heures(h.heures) + (h.montant.map { " · " + FormatSuisse.chf($0) } ?? ""))
                        .styleTexte(15, relativeTo: .subheadline)
                        .foregroundStyle(Color.encre)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: Espace.xs)
                ForEach(["PDF", "Excel"], id: \.self) { format in
                    Text(format)
                        .font(Police.mono(10.5))
                        .foregroundStyle(Color.encre)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .overlay(Capsule().strokeBorder(Color.filetFort, lineWidth: Espace.filet))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .tuileMaison(rayon: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActionPressee())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Détail des heures, relevés PDF et Excel du bureau"))
        .accessibilityIdentifier("heures-secretariat")
        .sheet(item: $heuresOuvertes) { HeuresSecretariatView(heures: $0) }
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
