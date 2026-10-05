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

    enum VueFinances: Hashable {
        case encaisser, payer, offres
    }

    /// Vue choisie, gardée dans l'app : les instruments de l'accueil ouvrent directement la bonne.
    private var vue: VueFinances { app.vueFinances }
    private var selectionVue: Binding<VueFinances> {
        Binding(get: { app.vueFinances }, set: { app.vueFinances = $0 })
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
                    ], selection: selectionVue)
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

                            if let compta = argent.comptabilite, !devantClient {
                                comptabilite(compta)
                                    .padding(.top, Espace.xl)
                                    .apparitionEnCascade(index: 1, visible: visible)
                            }

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
                .verrouillerLargeur()
                .animation(.endry, value: vue)
            }
            .scrollIndicators(.hidden)
            .tirerPourActualiser { await modele.charger() }
            .background(FondMaison(discret: true))
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
                    .font(Police.mono(12))
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
            let echu = e.anciennete.jours0a30 + e.anciennete.jours31a60 + e.anciennete.plus60
            BandeChiffres(elements: [
                .init(valeur: FormatSuisse.francs(e.anciennete.aEchoir), libelle: "Non échu"),
                .init(valeur: FormatSuisse.francs(echu), libelle: "Échu", ton: echu > 0 ? .alerte : nil),
                .init(valeur: FormatSuisse.francs(e.anciennete.plus60), libelle: "Plus de 60 j", ton: e.anciennete.plus60 > 0 ? .alerte : nil),
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

            if let compta = argent.comptabilite, !compta.travaux.isEmpty {
                Text("Travaux acceptés, à facturer").etiquetteMaison().padding(.top, Espace.xl)
                VStack(spacing: 10) {
                    ForEach(compta.travaux) { travail in
                        LigneMaison(titre: travail.titre,
                                    detail: Self.detailTravail(travail),
                                    montant: FormatSuisse.francs(travail.reste),
                                    etat: "À facturer", etatAccent: true)
                    }
                }
                .padding(.top, Espace.s)
                BandeChiffres(elements: [
                    .init(valeur: FormatSuisse.francs(e.total), libelle: "Factures ouvertes"),
                    .init(valeur: FormatSuisse.francs(compta.aFacturer), libelle: "À facturer"),
                    .init(valeur: FormatSuisse.francs(e.total + compta.aFacturer), libelle: "On nous doit"),
                ])
                .padding(.top, Espace.m)
                .accessibilityIdentifier("travaux-a-facturer")
            }

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
                .font(Police.mono(11.5))
                .foregroundStyle(Color.encreDouce)
                .padding(.top, Espace.s)
        }
    }

    private func echeanceClient(_ f: FactureClient) -> String {
        if f.retardJours > 0 { return "+\(f.retardJours) j" }
        if let echeance = f.echeance { return "éch. \(DateEndry.jourMois(echeance))" }
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
                let echues = Self.somme(p.factures) { $0 < 0 }
                BandeChiffres(elements: [
                    .init(valeur: FormatSuisse.francs(echues), libelle: "Échues", ton: echues > 0 ? .alerte : nil),
                    .init(valeur: FormatSuisse.francs(Self.somme(p.factures) { (0...7).contains($0) }), libelle: "Sous 7 jours"),
                    .init(valeur: FormatSuisse.francs(Self.somme(p.factures) { $0 > 7 }), libelle: "Plus tard"),
                ])
                .padding(.top, Espace.m)
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
                    .font(Police.mono(11.5))
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

    /// Somme des factures dont l'échéance (jours restants, 999 si inconnue) passe le filtre.
    static func somme(_ factures: [FactureFournisseur], _ filtre: (Int) -> Bool) -> Double {
        factures.filter { filtre($0.joursRestants ?? 999) }.reduce(0) { $0 + $1.montant }
    }

    /// Échéances à payer regroupées : échues, sous 7, 14 et 30 jours, plus tard.
    static func barresPayer(_ factures: [FactureFournisseur]) -> [Histogramme.Barre] {
        func somme(_ filtre: (Int) -> Bool) -> Double { Self.somme(factures, filtre) }
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

    // MARK: - Comptabilité

    /// « Devis 35’000 · facturé 17’500 », précédé du chantier quand le client est connu.
    static func detailTravail(_ t: TravailAFacturer) -> String {
        let montants = "devis \(FormatSuisse.francs(t.devis)) · facturé \(FormatSuisse.francs(t.facture))"
        return t.client.isEmpty || t.chantier.isEmpty ? montants : t.chantier + " · " + montants
    }

    static func detailCompte(_ c: CompteUtilise) -> String {
        "Compte \(c.numero) · \(c.factures) facture\(c.factures > 1 ? "s" : "")"
    }

    /// Plan comptable tenu par le bureau : solde, comptes utilisés, documents (PDF, Excel).
    private func comptabilite(_ c: Comptabilite) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Comptabilité").etiquetteMaison()
                .accessibilityAddTraits(.isHeader)
            BandeChiffres(elements: [
                .init(valeur: FormatSuisse.francs(c.nousDoit), libelle: "On nous doit"),
                .init(valeur: FormatSuisse.francs(c.aPayer), libelle: "Nous devons", ton: c.aPayerEnRetard > 0 ? .alerte : nil),
                .init(valeur: FormatSuisse.francs(c.solde), libelle: "Solde", ton: c.solde < 0 ? .alerte : nil),
            ])
            .padding(.top, Espace.s)
            if !c.comptes.isEmpty {
                VStack(spacing: 10) {
                    ForEach(c.comptes) { compte in
                        LigneMaison(titre: compte.libelle.isEmpty ? "Compte \(compte.numero)" : compte.libelle,
                                    detail: Self.detailCompte(compte),
                                    montant: FormatSuisse.francs(compte.total),
                                    etat: compte.ouvert > 0 ? "reste \(FormatSuisse.francs(compte.ouvert))" : "payé",
                                    etatAlerte: compte.ouvert > 0)
                    }
                }
                .padding(.top, Espace.m)
            }
            if !c.documents.isEmpty {
                HStack(spacing: Espace.xs) {
                    ForEach(c.documents) { doc in
                        Button {
                            Task { await app.documents.ouvrir(doc.chemin, nom: doc.nom, api: app.session.api) }
                        } label: {
                            Text(doc.format == "pdf" ? "Plan comptable PDF" : "Classeur Excel")
                                .font(Police.mono(11.5))
                                .foregroundStyle(Color.encre)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .overlay(Capsule().strokeBorder(Color.filetFort, lineWidth: Espace.filet))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ActionPressee())
                        .accessibilityHint(Text("Ouvre le document du bureau"))
                    }
                }
                .padding(.top, Espace.m)
            }
        }
        .accessibilityIdentifier("comptabilite")
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
                        .font(Police.mono(11.5))
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
        .sheet(item: $heuresOuvertes) { HeuresSecretariatView(heures: $0).apercuDocuments() }
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
