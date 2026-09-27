import EndryKit
import SwiftUI

/// Détail d'un chantier : avancement, documents, achats fournisseurs, notes, dictée.
struct DossierView: View {
    @Environment(ModeleApp.self) private var app
    @State var modele: ModeleDossier
    @State private var visible = false

    var body: some View {
        let dossier = modele.dossier
        ScrollView {
            VStack(alignment: .leading, spacing: Espace.l) {
                ZStack(alignment: .bottomLeading) {
                    PhotoVivante(nom: PhotosMarque.pour(id: dossier.id))
                        .frame(height: 300)
                        .overlay(VoilePhoto(haut: 0.55, bas: 1))
                    VStack(alignment: .leading, spacing: Espace.xs) {
                        HStack {
                            Text((dossier.lieu ?? dossier.id).uppercased())
                                .font(Police.etiquette(Echelle.micro))
                                .tracking(2.2)
                                .foregroundStyle(Color.or)
                            if dossier.decisionEnAttente {
                                Pastille(texte: "Décision en attente", couleur: .or, icone: "circle.fill")
                            }
                        }
                        Text(dossier.client.isEmpty ? dossier.titre : dossier.client)
                            .styleTitre(34, relativeTo: .largeTitle)
                            .foregroundStyle(Color(hex: 0xF7F2E9))
                        Text(dossier.titre)
                            .styleTitre(22, relativeTo: .title3, graisse: .italique)
                            .foregroundStyle(Color(hex: 0xE9DFCF))
                    }
                    .padding(.horizontal, Espace.bord)
                    .padding(.bottom, Espace.s)
                }
                .padding(.horizontal, -Espace.bord)
                .apparitionEnCascade(index: 0, visible: visible)

                // Avancement
                VStack(alignment: .leading, spacing: Espace.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(dossier.etapeLibelle).styleTitre(20, relativeTo: .title3).foregroundStyle(Color.encre)
                        Spacer()
                        if let montant = dossier.montant {
                            MontantView(montant: montant, taille: 22, style: .title3)
                        }
                    }
                    RailAvancement(index: dossier.etapeIndex, compact: false)
                    if dossier.dateDebut != nil || dossier.dates != nil {
                        HStack(spacing: Espace.l) {
                            if let debut = dossier.dateDebut {
                                infoDate("Début", DateEndry.courte(debut))
                            }
                            if let fin = dossier.dateFin {
                                infoDate("Fin", DateEndry.courte(fin))
                            }
                            if dossier.dateDebut == nil, let dates = dossier.dates {
                                infoDate("Travaux", dates)
                            }
                        }
                    }
                }
                .padding(Espace.l)
                .surfaceCarte()
                .apparitionEnCascade(index: 1, visible: visible)

                Button {
                    app.dicter(pour: dossier)
                } label: {
                    Label("Dicter pour ce chantier", systemImage: "mic.fill")
                }
                .buttonStyle(BoutonPrincipal())
                .accessibilityIdentifier("dicter-chantier")
                .apparitionEnCascade(index: 2, visible: visible)

                if modele.horsLigne {
                    BandeauHorsLigne(majLe: nil)
                }

                if case .chargement = modele.etat, dossier.elements.isEmpty {
                    SqueletteCarte()
                }

                if !dossier.documents.isEmpty {
                    section("Documents") {
                        ForEach(dossier.documents) { element in
                            LigneElement(element: element, chargement: app.documents.chargement == element.pdf) {
                                if let pdf = element.pdf {
                                    Task { await app.documents.ouvrir(pdf, nom: "\(element.numeroAffiche ?? element.libelle).pdf", api: app.session.api) }
                                }
                            }
                        }
                    }
                    .apparitionEnCascade(index: 3, visible: visible)
                }

                if !dossier.achats.isEmpty || !dossier.facturesFournisseurs.isEmpty {
                    section("Achats fournisseurs") {
                        ForEach(dossier.achats) { element in
                            LigneElement(element: element, chargement: false, action: nil)
                        }
                        ForEach(dossier.facturesFournisseurs.filter { f in !dossier.achats.contains { $0.ref == f.numero } }) { f in
                            LigneFournisseur(facture: f)
                        }
                    }
                    .apparitionEnCascade(index: 4, visible: visible)
                }

                if let note = dossier.note, !note.isEmpty {
                    section("Notes") {
                        Text(note)
                            .styleTexte(15)
                            .foregroundStyle(Color.encre)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Espace.s)
                    }
                    .apparitionEnCascade(index: 5, visible: visible)
                }
            }
            .padding(.horizontal, Espace.bord)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(FondAmbiant())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            visible = true
            await modele.charger()
        }
    }

    private func infoDate(_ libelle: String, _ valeur: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(libelle).styleSurtitre()
            Text(valeur).styleTexte(15, relativeTo: .subheadline, graisse: .semibold).foregroundStyle(Color.encre).monospacedDigit()
        }
    }

    private func section<Contenu: View>(_ titre: String, @ViewBuilder contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: titre)
            VStack(spacing: 0) { contenu() }
                .padding(.horizontal, Espace.m)
                .padding(.vertical, Espace.xxs)
                .surfaceCarte(rayon: 22)
        }
    }
}

struct LigneElement: View {
    var element: ElementDossier
    var chargement: Bool
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: Espace.s) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.surfaceCreuse)
                    Image(systemName: icone).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.bronze)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(element.libelle).styleTexte(15, relativeTo: .subheadline, graisse: .semibold)
                        .foregroundStyle(Color.encre).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if let numero = element.numeroAffiche {
                            Text(numero).font(Police.reference(11)).foregroundStyle(Color.encrePale)
                        }
                        if let statut = element.statut, !statut.isEmpty {
                            Text(statut).styleTexte(12, relativeTo: .caption, graisse: .medium).foregroundStyle(couleurStatut(statut))
                        }
                        if let echeance = element.echeance, !echeance.isEmpty {
                            Text("éch. \(DateEndry.courte(echeance))").styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
                        }
                    }
                }
                Spacer(minLength: Espace.xs)
                if let montant = element.montantAffiche {
                    MontantView(montant: montant, taille: 15, afficherCentimes: false, style: .subheadline)
                }
                if chargement {
                    ProgressView()
                } else if action != nil, element.pdf != nil {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.encrePale)
                }
            }
            .padding(.vertical, Espace.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil || element.pdf == nil)
        .accessibilityElement(children: .combine)
    }

    private var icone: String {
        switch element.type {
        case .offre: "doc.richtext"
        case .facture: "doc.text"
        case .achat: "shippingbox"
        case .autre: "doc"
        }
    }

    private func couleurStatut(_ statut: String) -> Color {
        let s = statut.lowercased()
        if s.contains("retard") { return .rouille }
        if s.contains("pay") || s.contains("accept") { return .vertControle }
        return .encrePale
    }
}

struct LigneFournisseur: View {
    var facture: FactureFournisseur

    var body: some View {
        HStack(spacing: Espace.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(facture.fournisseur).styleTexte(15, relativeTo: .subheadline, graisse: .semibold).foregroundStyle(Color.encre)
                HStack(spacing: 6) {
                    Text(facture.numero).font(Police.reference(11)).foregroundStyle(Color.encrePale)
                    if let echeance = facture.echeance {
                        Text("· éch. \(DateEndry.courte(echeance))").styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
                    }
                }
                if let objet = facture.objet {
                    Text(objet).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce).lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                MontantView(montant: facture.montant, taille: 15, afficherCentimes: false, style: .subheadline)
                if let jours = facture.joursRestants {
                    Text(jours < 0 ? "échue" : jours == 0 ? "aujourd’hui" : "dans \(jours) j")
                        .styleTexte(11, relativeTo: .caption2, graisse: .semibold)
                        .foregroundStyle(jours <= 3 ? Color.rouille : Color.encrePale)
                }
            }
        }
        .padding(.vertical, Espace.s)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Dossier") {
    let app = ModeleApp()
    app.activerDemo()
    return NavigationStack {
        DossierView(modele: ModeleDossier(dossier: Fixtures.dossierDetaille, api: APIDemo()))
            .preferredColorScheme(.dark)
    }
    .environment(app)
}
