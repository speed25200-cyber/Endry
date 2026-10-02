import EndryKit
import SwiftUI

/// Chantier « Maison Endry » (maquette E) : photo fondue dans le brun, retour et lieu en verre (itinéraire),
/// client en Cinzel, titre en Cormorant, avancement en 7 étapes, offre et période, décision en attente,
/// outils sur place, documents, achats, notes, et « Dicter pour ce chantier ».
struct DossierView: View {
    @AppStorage(ModeDevantClient.cle) private var devantClient = false
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @Environment(\.openURL) private var ouvrirLien
    @State var modele: ModeleDossier
    @State private var visible = false

    var body: some View {
        let dossier = modele.dossier
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                enTete(dossier)
                    .apparitionEnCascade(index: 0, visible: visible)

                avancement(dossier)
                    .padding(.top, Espace.xl)
                    .apparitionEnCascade(index: 1, visible: visible)

                resume(dossier)
                    .padding(.top, Espace.l)
                    .apparitionEnCascade(index: 2, visible: visible)

                Text("Sur place").etiquetteMaison()
                    .padding(.top, Espace.xl)
                // Sur place : régie à faire signer, bon du fournisseur, relevé pour l'offre.
                RangeeOutilsTerrain(chantierId: dossier.id)
                    .padding(.top, Espace.s)
                    .apparitionEnCascade(index: 3, visible: visible)

                if !dossier.documents.isEmpty {
                    Text("Documents").etiquetteMaison()
                        .padding(.top, Espace.xl)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(dossier.documents) { element in
                                Button {
                                    if let pdf = element.pdf {
                                        Task { await app.documents.ouvrir(pdf, nom: "\(element.numeroAffiche ?? element.libelle).pdf", api: app.session.api) }
                                    }
                                } label: {
                                    Text("\(element.type == .offre ? "Offre" : "Facture") \(element.numeroAffiche ?? element.libelle).pdf")
                                        .font(Police.mono(11))
                                        .foregroundStyle(Color.encre)
                                        .lineLimit(1)
                                        .padding(.horizontal, 14)
                                        .frame(height: 36)
                                        .verreMaison(Capsule())
                                }
                                .buttonStyle(ActionPressee())
                                .disabled(element.pdf == nil)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                    .padding(.top, Espace.xs)
                }

                if devantClient, !dossier.achats.isEmpty || !dossier.facturesFournisseurs.isEmpty {
                    BlocMasqueClient(titre: "Achats fournisseurs").padding(.top, Espace.xl)
                } else if !dossier.achats.isEmpty || !dossier.facturesFournisseurs.isEmpty {
                    section("Achats fournisseurs") {
                        ForEach(dossier.achats) { element in
                            LigneElement(element: element, chargement: false, action: nil)
                        }
                        ForEach(dossier.facturesFournisseurs.filter { f in !dossier.achats.contains { $0.ref == f.numero } }) { f in
                            LigneFournisseur(facture: f)
                        }
                    }
                    .padding(.top, Espace.xl)
                }

                if let note = dossier.note, !note.isEmpty {
                    section("Notes") {
                        Text(note)
                            .styleTexte(15)
                            .foregroundStyle(Color.encre)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Espace.s)
                    }
                    .padding(.top, Espace.xl)
                }

                RangeeNouveauDocument(chantierId: dossier.id)
                    .padding(.top, Espace.xl)

                // Ce que vous avez décidé pour ce chantier, et ce que le bureau en a fait.
                ActiviteChantier(chantierId: dossier.id)
                    .padding(.top, Espace.l)

                if modele.horsLigne {
                    BandeauHorsLigne(majLe: nil).padding(.top, Espace.m)
                }
                if case .chargement = modele.etat, dossier.elements.isEmpty {
                    SqueletteCarte().padding(.top, Espace.m)
                }

                Button {
                    app.dicter(pour: dossier)
                } label: {
                    Label("Dicter pour ce chantier", systemImage: "waveform")
                        .styleTexte(17, relativeTo: .body)
                        .foregroundStyle(Color.boutonTexte)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.bouton, in: Capsule())
                        .shadow(color: Color.ombre, radius: 16, y: 10)
                }
                .buttonStyle(ActionPressee())
                .padding(.top, Espace.xl)
                .accessibilityIdentifier("dicter-chantier")
            }
            .largeurLisible(Adaptatif.lecture)
            .padding(.horizontal, Espace.bord)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(FondMaison(photo: nil))
        .toolbar(.hidden, for: .navigationBar)
        .task {
            visible = true
            await modele.charger()
        }
    }

    // MARK: - En-tête

    private func enTete(_ dossier: Dossier) -> some View {
        ZStack(alignment: .bottomLeading) {
            PhotoVivante(nom: PhotosMarque.pour(id: dossier.id), mention: false)
                .frame(height: 340)
                .opacity(0.55)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.45),
                                             .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .padding(.horizontal, -Espace.bord)
            VStack(alignment: .leading, spacing: 8) {
                if !dossier.client.isEmpty {
                    Text(dossier.client).etiquetteMaison(10.5, couleur: .signal)
                }
                titre(dossier.titre)
            }
            .padding(.bottom, 4)
        }
        .overlay(alignment: .top) {
            HStack {
                Button { fermer() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.encre)
                        .frame(width: 40, height: 40)
                        .verreMaison(Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(ActionPressee())
                .accessibilityLabel(Text("Retour"))
                .accessibilityIdentifier("retour-chantier")
                Spacer()
                if let lieu = dossier.lieu {
                    Button {
                        let requete = lieu.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? lieu
                        if let lien = URL(string: "maps://?daddr=\(requete)") { ouvrirLien(lien) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse").font(.system(size: 14))
                            Text(lieu).styleTexte(15, relativeTo: .subheadline).lineLimit(1)
                        }
                        .foregroundStyle(Color.encre)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .verreMaison(Capsule())
                    }
                    .buttonStyle(ActionPressee())
                    .accessibilityHint(Text("Ouvre l’itinéraire dans Plans"))
                    .accessibilityIdentifier("itineraire-chantier")
                }
            }
            .padding(.top, Espace.xs)
        }
    }

    /// Titre en Cormorant ; ce qui suit le tiret long passe en italique (« Villa Morel — *PAC air-eau* »).
    private func titre(_ texte: String) -> some View {
        let morceaux = texte.components(separatedBy: " — ")
        let debut = morceaux.first ?? texte
        let fin = morceaux.dropFirst().joined(separator: " — ")
        return Text("\(Text(debut))\(Text(fin.isEmpty ? "" : " — "))\(Text(fin).font(Police.serif(40, relativeTo: .largeTitle, italique: true)))")
            .font(Police.serif(40, relativeTo: .largeTitle))
            .foregroundStyle(Color.encre)
            .tracking(-0.4)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Avancement

    private func avancement(_ dossier: Dossier) -> some View {
        let etapes = EtapeChantier.allCases
        let courant = min(max(dossier.etapeIndex, 0), etapes.count - 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Avancement").etiquetteMaison()
                Spacer()
                Text("Étape \(courant + 1) / \(etapes.count) · \(dossier.etapeLibelle)")
                    .font(Police.mono(10.5))
                    .foregroundStyle(Color.encreDouce)
            }
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(etapes.enumerated()), id: \.offset) { index, etape in
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule()
                            .fill(index < courant ? Color.encre : index == courant ? Color.signal : Color.filetFort)
                            .frame(height: 3)
                        Text(etape.libelle)
                            .styleTexte(11, relativeTo: .caption2)
                            .foregroundStyle(index <= courant ? Color.encre : Color.encreDouce)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Avancement : étape \(courant + 1) sur \(etapes.count), \(dossier.etapeLibelle)"))
    }

    // MARK: - Offre, période, décision

    private func resume(_ dossier: Dossier) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Espace.m) {
                if let montant = dossier.montant, !devantClient {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Offre").font(Police.mono(10.5)).foregroundStyle(Color.encreDouce)
                        Text(FormatSuisse.francs(montant))
                            .font(Police.serif(30, relativeTo: .title))
                            .monospacedDigit()
                            .foregroundStyle(Color.encre)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Période").font(Police.mono(10.5)).foregroundStyle(Color.encreDouce)
                    Text(periode(dossier))
                        .styleTexte(17, relativeTo: .body)
                        .monospacedDigit()
                        .foregroundStyle(Color.encre)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 16)
            if dossier.decisionEnAttente {
                Rectangle().fill(Color.filet).frame(height: Espace.filet)
                Button {
                    if let reference = dossier.referenceDecision { app.referenceCiblee = reference }
                    app.onglet = .aujourdhui
                } label: {
                    HStack(spacing: 8) {
                        Text("\(Text("Décision en attente").foregroundStyle(Color.encre))\(Text(" · à décider dans l’accueil").foregroundStyle(Color.encreDouce))")
                            .styleTexte(15, relativeTo: .subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Circle().fill(Color.signal).frame(width: 9, height: 9)
                    }
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("decision-chantier")
            }
        }
        .padding(.horizontal, 16)
        .tuileMaison(rayon: 26)
    }

    private func periode(_ dossier: Dossier) -> String {
        if let debut = dossier.dateDebut {
            let d = DateEndry.jourMois(debut)
            if let fin = dossier.dateFin, fin != debut { return "\(d) – \(DateEndry.jourMois(fin))" }
            return d
        }
        return dossier.dates ?? "À planifier"
    }

    private func section<Contenu: View>(_ titre: String, @ViewBuilder contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            Text(titre).etiquetteMaison()
            VStack(spacing: 0) { contenu() }
                .padding(.horizontal, Espace.m)
                .padding(.vertical, Espace.xxs)
                .tuileMaison(rayon: 22)
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
                                .lineLimit(1).fixedSize()
                        }
                        if let statut = element.statut, !statut.isEmpty {
                            Text(statut).styleTexte(12, relativeTo: .caption, graisse: .medium).foregroundStyle(couleurStatut(statut))
                                .lineLimit(1).fixedSize()
                        }
                        if let echeance = element.echeance, !echeance.isEmpty {
                            Text("éch. \(DateEndry.courte(echeance))").styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
                                .lineLimit(1).minimumScaleFactor(0.8)
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
