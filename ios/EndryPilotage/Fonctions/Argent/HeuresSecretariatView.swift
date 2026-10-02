import EndryKit
import SwiftUI

/// Détail des heures du secrétariat, pensé pour aller vite : en-tête compact, documents du bureau en haut,
/// bascule « Par jour / Par travail », jours à en-tête collant, lignes repliées (toucher pour déplier),
/// filtre par travail et recherche. Les relevés PDF et Excel sont produits par le bureau (Claude), pas par l'iPhone.
struct HeuresSecretariatView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @State private var heures: HeuresSecretariat
    @State private var chargement = false
    @State private var detailIndisponible = false
    @State private var releveDemande = false
    @State private var vue: Vue = .jours
    @State private var travail: String?
    @State private var recherche = ""
    @State private var depliees: Set<String> = []

    enum Vue: String, CaseIterable, Identifiable {
        case jours = "Par jour"
        case travaux = "Par travail"
        var id: String { rawValue }
    }

    init(heures: HeuresSecretariat) {
        _heures = State(initialValue: heures)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Espace.m, pinnedViews: [.sectionHeaders]) {
                    entete
                    if heures.moisDisponibles.count > 1 { choixMois }
                    documents
                    if heures.lignes.isEmpty {
                        sansDetail
                    } else {
                        Picker("Affichage", selection: $vue) {
                            ForEach(Vue.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("vue-heures")
                        switch vue {
                        case .jours: jours
                        case .travaux: travaux
                        }
                    }
                }
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, Espace.xl)
                .largeurLisible(Adaptatif.ecran)
                .verrouillerLargeur()
            }
            .background(FondAmbiant())
            .searchable(text: $recherche, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Tâche, client, travail")
            .onChange(of: recherche) { _, texte in if !texte.isEmpty { vue = .jours } }
            .refreshable { await charger(heures.periode) }
            .navigationTitle("Heures de secrétariat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
        }
        .task { await charger(nil) }
    }

    // MARK: En-tête

    private var entete: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(heures.mois.capitalizedPremiere).styleSurtitre()
                Text(FormatSuisse.heures(heures.heures)).styleTitre(34, relativeTo: .largeTitle).foregroundStyle(Color.encre)
                    .accessibilityIdentifier("total-heures-secretariat")
            }
            Spacer(minLength: Espace.s)
            VStack(alignment: .trailing, spacing: 2) {
                if let m = heures.montant { Text(FormatSuisse.chf(m)).styleTexte(15, graisse: .semibold).foregroundStyle(Color.encreDouce) }
                if let t = heures.tarif { Text("\(FormatSuisse.chf(t)) / h HT").styleTexte(12).foregroundStyle(Color.encrePale) }
                if chargement { ProgressView().controlSize(.small) }
            }
        }
        .padding(.top, Espace.s)
    }

    private var choixMois: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Espace.xs) {
                ForEach(heures.moisDisponibles, id: \.self) { mois in
                    let actif = mois == heures.periode
                    Button { Task { await charger(mois) } } label: {
                        Text(Self.nomMois(mois))
                            .styleTexte(14, graisse: .semibold)
                            .foregroundStyle(actif ? Color.espressoProfond : Color.encre)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(actif ? AnyShapeStyle(.degradeOr) : AnyShapeStyle(Color.surfaceCreuse), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Documents du bureau

    /// Les relevés viennent du bureau (Claude les met en page) ; l'iPhone les ouvre et peut en demander un à jour.
    private var documents: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            if !heures.documents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Espace.xs) {
                        ForEach(heures.documents) { doc in
                            Button {
                                Task { await app.documents.ouvrir(doc.chemin, nom: doc.nom, api: app.session.api) }
                            } label: {
                                Label(Self.libelle(doc), systemImage: Self.icone(doc))
                                    .styleTexte(14, graisse: .semibold)
                                    .foregroundStyle(Color.encre)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(Color.surfaceCreuse, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(doc.nom))
                        }
                    }
                }
                .accessibilityIdentifier("documents-heures")
            }
            Button {
                Task {
                    let r = await app.transmettreDemande(heures.demandeReleve)
                    releveDemande = r == .transmise || r == .gardee
                    app.toast = Toast(releveDemande ? "Demandé au Secrétariat : le relevé arrivera ici et dans la conversation."
                                                    : "La demande n’est pas partie.", style: releveDemande ? .succes : .erreur)
                }
            } label: {
                Label(releveDemande ? "Relevé demandé au bureau"
                                    : (heures.documents.isEmpty ? "Demander le relevé PDF et Excel au bureau" : "Demander un relevé à jour"),
                      systemImage: releveDemande ? "checkmark.circle" : "doc.badge.plus")
                    .styleTexte(14, graisse: .semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.bronze)
            .disabled(releveDemande)
            .accessibilityIdentifier("demander-releve")
        }
    }

    // MARK: Par jour

    private var jours: some View {
        let groupes = heures.parJour(categorie: travail, recherche: recherche)
        return Group {
            if let travail {
                HStack {
                    Label(travail, systemImage: "line.3.horizontal.decrease.circle.fill")
                        .styleTexte(14, graisse: .semibold)
                    Spacer()
                    Button { withAnimation(.endry) { self.travail = nil } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.encrePale)
                    }
                    .accessibilityLabel(Text("Retirer le filtre"))
                }
                .foregroundStyle(Color.bronze)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.surfaceCreuse, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if groupes.isEmpty {
                Text("Aucune tâche ne correspond.").styleTexte(14).foregroundStyle(Color.encrePale)
                    .padding(.vertical, Espace.m)
            }
            ForEach(groupes) { jour in
                Section {
                    VStack(spacing: 0) {
                        ForEach(jour.lignes) { l in
                            ligne(l)
                            if l.id != jour.lignes.last?.id { Divider().overlay(Color.bordureOr.opacity(0.4)) }
                        }
                    }
                    .padding(.horizontal, Espace.m)
                    .background(Color.surfaceCreuse.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } header: {
                    HStack {
                        Text(Self.jourLong(jour.date)).styleTexte(13, graisse: .semibold).foregroundStyle(Color.encreDouce)
                        Spacer()
                        Text(FormatSuisse.heures(jour.heures)).styleTexte(13, graisse: .semibold).monospacedDigit()
                            .foregroundStyle(Color.encre)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .background(.bar)
                }
            }
        }
    }

    /// Une tâche : deux lignes, toucher pour lire le détail complet.
    private func ligne(_ l: LigneHeuresSecretariat) -> some View {
        let ouverte = depliees.contains(l.id)
        return Button {
            withAnimation(.endry) {
                if ouverte { depliees.remove(l.id) } else { depliees.insert(l.id) }
            }
        } label: {
            HStack(alignment: .top, spacing: Espace.s) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(l.libelle).styleTexte(14).foregroundStyle(Color.encre)
                        .lineLimit(ouverte ? nil : 2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if let c = l.categorie { Text(c).styleTexte(11, relativeTo: .caption, graisse: .semibold).foregroundStyle(Color.bronze) }
                        if let client = l.client, !client.isEmpty {
                            Text(client).styleTexte(11, relativeTo: .caption).foregroundStyle(Color.encrePale).lineLimit(ouverte ? nil : 1)
                        }
                    }
                }
                Spacer(minLength: Espace.xs)
                Text(FormatSuisse.heures(l.heures)).styleTexte(14, graisse: .semibold).monospacedDigit()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(ouverte ? "Replier" : "Lire le détail complet"))
    }

    // MARK: Par travail

    /// Toucher un travail : ses tâches, jour par jour.
    private var travaux: some View {
        let totaux = heures.parCategorie
        let maximum = max(totaux.first?.heures ?? 1, 0.1)
        return VStack(spacing: 0) {
            ForEach(totaux.indices, id: \.self) { i in
                Button {
                    withAnimation(.endry) {
                        travail = totaux[i].categorie
                        vue = .jours
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(totaux[i].categorie).styleTexte(14, graisse: .medium).foregroundStyle(Color.encre)
                            Spacer()
                            Text(FormatSuisse.heures(totaux[i].heures)).styleTexte(14, graisse: .semibold).monospacedDigit()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.encrePale)
                        }
                        BarreProportion(fraction: totaux[i].heures / maximum)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Espace.m)
        .background(Color.surfaceCreuse.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sansDetail: some View {
        Label(detailIndisponible
              ? "Le PC ne donne pas encore le détail des heures (contrat v1.6)."
              : "Pas de détail pour ce mois.", systemImage: "info.circle")
            .styleTexte(14).foregroundStyle(Color.encreDouce)
    }

    // MARK: Données

    private func charger(_ mois: String?) async {
        guard let api = app.session.api else { return }
        chargement = true
        defer { chargement = false }
        do throws(ErreurAPI) {
            heures = try await api.heuresSecretariat(mois: mois)
            detailIndisponible = false
            travail = nil
            depliees = []
        } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
            detailIndisponible = true
        } catch {
            app.toast = Toast(error.message, style: .erreur)
        }
    }

    static func nomMois(_ periode: String) -> String {
        guard let d = DateEndry.lire(periode + "-01") else { return periode }
        return DateEndry.nomMois(d).capitalizedPremiere
    }

    static func jourLong(_ date: String) -> String {
        guard let d = DateEndry.lire(date) else { return DateEndry.courte(date) }
        return DateEndry.longue(d).capitalizedPremiere
    }

    static func libelle(_ doc: DocumentHeures) -> String {
        switch doc.format.lowercased() {
        case "pdf": "PDF du bureau"
        case "xlsx", "xls", "csv": "Excel du bureau"
        default: doc.nom
        }
    }

    static func icone(_ doc: DocumentHeures) -> String {
        doc.format.lowercased() == "pdf" ? "doc.richtext" : "tablecells"
    }
}

extension HeuresSecretariat: @retroactive Identifiable {
    public var id: String { periode ?? mois }
}
