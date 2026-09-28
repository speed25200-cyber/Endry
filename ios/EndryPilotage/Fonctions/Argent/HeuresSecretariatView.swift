import EndryKit
import SwiftUI
import UIKit

/// Détail des heures du secrétariat : par catégorie et jour par jour, relevé PDF et tableau Excel.
struct HeuresSecretariatView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @State private var heures: HeuresSecretariat
    @State private var chargement = false
    @State private var detailIndisponible = false
    @State private var fichiers: FichiersExport?
    @State private var questionEnvoyee = false

    init(heures: HeuresSecretariat) {
        _heures = State(initialValue: heures)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.l) {
                    entete
                    if heures.moisDisponibles.count > 1 { choixMois }
                    documents
                    if heures.lignes.isEmpty {
                        sansDetail
                    } else {
                        categories
                        journal
                    }
                }
                .padding(Espace.bord)
            }
            .background(FondAmbiant())
            .refreshable { await charger(heures.periode) }
            .navigationTitle("Heures de secrétariat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
        }
        .task { await charger(nil) }
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: Espace.xxs) {
            Text(heures.mois.capitalizedPremiere).styleSurtitre()
            Text(FormatSuisse.heures(heures.heures)).styleTitre(40, relativeTo: .largeTitle).foregroundStyle(Color.encre)
                .accessibilityIdentifier("total-heures-secretariat")
            HStack(spacing: Espace.s) {
                if let m = heures.montant { Text(FormatSuisse.chf(m)).styleTexte(15, graisse: .semibold).foregroundStyle(Color.encreDouce) }
                if let t = heures.tarif { Text("· \(FormatSuisse.chf(t)) / h HT").styleTexte(13).foregroundStyle(Color.encrePale) }
            }
            if chargement { ProgressView().padding(.top, Espace.xs) }
        }
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
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(actif ? AnyShapeStyle(.degradeOr) : AnyShapeStyle(Color.surfaceCreuse), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var documents: some View {
        SectionTerrain(titre: "Documents", icone: "doc.on.doc") {
            ForEach(heures.documents) { doc in
                Button {
                    Task { await app.documents.ouvrir(doc.chemin, nom: doc.nom, api: app.session.api) }
                } label: {
                    Label(doc.nom, systemImage: doc.format == "pdf" ? "doc.richtext" : "tablecells")
                        .styleTexte(15, graisse: .semibold).foregroundStyle(Color.encre)
                }
                .buttonStyle(.plain)
            }
            if let fichiers {
                ShareLink(item: fichiers.csv) {
                    Label("Tableau pour Excel (.csv)", systemImage: "tablecells").styleTexte(15, graisse: .semibold)
                }
                .accessibilityIdentifier("export-excel")
                ShareLink(item: fichiers.pdf) {
                    Label("Relevé PDF (généré sur l’iPhone)", systemImage: "doc.richtext").styleTexte(15, graisse: .semibold)
                }
                .accessibilityIdentifier("export-pdf")
            }
            if heures.documents.isEmpty && heures.lignes.isEmpty {
                Text("Aucun document fourni par le bureau pour ce mois.").styleTexte(13).foregroundStyle(Color.encrePale)
            }
        }
        .tint(Color.bronze)
    }

    private var categories: some View {
        SectionTerrain(titre: "Par travail", icone: "chart.bar") {
            let maximum = max(heures.parCategorie.first?.heures ?? 1, 0.1)
            let totaux = heures.parCategorie
            ForEach(totaux.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(totaux[i].categorie).styleTexte(14, graisse: .medium).foregroundStyle(Color.encre)
                        Spacer()
                        Text(FormatSuisse.heures(totaux[i].heures)).styleTexte(14, graisse: .semibold).monospacedDigit()
                    }
                    BarreProportion(fraction: totaux[i].heures / maximum)
                }
            }
        }
    }

    private var journal: some View {
        SectionTerrain(titre: "Jour par jour", icone: "calendar") {
            ForEach(heures.lignes) { l in
                HStack(alignment: .top, spacing: Espace.s) {
                    Text(DateEndry.courte(l.date).prefix(5))
                        .font(Police.reference(12)).foregroundStyle(Color.encrePale).frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.libelle).styleTexte(14).foregroundStyle(Color.encre)
                        if let client = l.client {
                            Text(client).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
                        }
                    }
                    Spacer(minLength: Espace.xs)
                    Text(FormatSuisse.heures(l.heures)).styleTexte(14, graisse: .semibold).monospacedDigit()
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var sansDetail: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            Label(detailIndisponible
                  ? "Le PC ne donne pas encore le détail des heures (contrat v1.6)."
                  : "Pas de détail pour ce mois.", systemImage: "info.circle")
                .styleTexte(14).foregroundStyle(Color.encreDouce)
            Button {
                Task {
                    let r = await app.saisie?.transmettre(demande: "Question du patron : peux-tu me donner le détail des heures de secrétariat de \(heures.mois) (date, tâche, durée) et le relevé en PDF et en Excel ?")
                    questionEnvoyee = r == .transmise || r == .gardee
                }
            } label: {
                Label(questionEnvoyee ? "Demande transmise" : "Demander le détail au bureau", systemImage: "questionmark.bubble")
            }
            .buttonStyle(BoutonSecondaire())
            .disabled(questionEnvoyee)
        }
    }

    // MARK: Données

    private func charger(_ mois: String?) async {
        guard let api = app.session.api else { return }
        chargement = true
        defer { chargement = false }
        do throws(ErreurAPI) {
            heures = try await api.heuresSecretariat(mois: mois)
            detailIndisponible = false
        } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
            detailIndisponible = true
        } catch {
            app.toast = Toast(error.message, style: .erreur)
        }
        fichiers = FichiersExport.creer(heures)
    }

    static func nomMois(_ periode: String) -> String {
        guard let d = DateEndry.lire(periode + "-01") else { return periode }
        return DateEndry.nomMois(d).capitalizedPremiere
    }
}

/// Fichiers partageables (Excel, PDF) produits sur l'iPhone à partir du détail.
struct FichiersExport: Equatable {
    let csv: URL
    let pdf: URL

    static func creer(_ h: HeuresSecretariat) -> FichiersExport? {
        guard !h.lignes.isEmpty else { return nil }
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let base = "Heures secrétariat \(h.mois)"
        let csv = dossier.appendingPathComponent(base + ".csv")
        let pdf = dossier.appendingPathComponent(base + ".pdf")
        do {
            try h.csv().write(to: csv, options: .atomic)
            try RelevePDF.donnees(h).write(to: pdf, options: .atomic)
        } catch {
            return nil
        }
        return FichiersExport(csv: csv, pdf: pdf)
    }
}

/// Relevé A4 : en-tête, tableau jour par jour, total.
enum RelevePDF {
    static func donnees(_ h: HeuresSecretariat) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let marge: CGFloat = 48
        let rendu = UIGraphicsPDFRenderer(bounds: page)
        let encre = UIColor(red: 0.14, green: 0.12, blue: 0.09, alpha: 1)
        let pale = UIColor(red: 0.45, green: 0.41, blue: 0.36, alpha: 1)
        let titre: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 20, weight: .bold), .foregroundColor: encre]
        let texte: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: encre]
        let gras: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: encre]
        let discret: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: pale]
        return rendu.pdfData { ctx in
            var y: CGFloat = 0
            func nouvellePage() {
                ctx.beginPage()
                y = marge
            }
            func ligne(_ date: String, _ tache: String, _ client: String, _ duree: String, style: [NSAttributedString.Key: Any]) {
                if y > page.height - marge - 30 { nouvellePage() }
                (date as NSString).draw(at: CGPoint(x: marge, y: y), withAttributes: style)
                (tache as NSString).draw(in: CGRect(x: marge + 70, y: y, width: 290, height: 28), withAttributes: style)
                (client as NSString).draw(in: CGRect(x: marge + 365, y: y, width: 90, height: 28), withAttributes: style)
                let d = duree as NSString
                d.draw(at: CGPoint(x: page.width - marge - d.size(withAttributes: style).width, y: y), withAttributes: style)
                y += 18
            }
            nouvellePage()
            ("Endry SA — Heures de secrétariat" as NSString).draw(at: CGPoint(x: marge, y: y), withAttributes: titre)
            y += 28
            (h.mois.capitalizedPremiere as NSString).draw(at: CGPoint(x: marge, y: y), withAttributes: discret)
            y += 28
            ligne("Date", "Tâche", "Client", "Heures", style: gras)
            for l in h.lignes {
                ligne(DateEndry.courte(l.date), l.libelle, l.client ?? "", FormatSuisse.heures(l.heures), style: texte)
            }
            y += 8
            ligne("", "Total", "", FormatSuisse.heures(h.heures), style: gras)
            if let m = h.montant { ligne("", "Montant", "", FormatSuisse.chf(m), style: gras) }
        }
    }
}

extension HeuresSecretariat: @retroactive Identifiable {
    public var id: String { periode ?? mois }
}
