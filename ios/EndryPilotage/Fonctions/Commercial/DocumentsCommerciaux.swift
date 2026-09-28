import EndryKit
import SwiftUI

// MARK: - Nouvelle offre, nouvelle facture : le patron décrit, le bureau prépare, le Oui reste au patron

/// Rédaction demandée (Finances, fiche chantier, offre signée, Siri).
struct DemandeCreation: Identifiable, Equatable {
    let id = UUID()
    var type: TypeDemandeDocument
    var chantierId: String?
    var offre: OffreSignee?
}

/// Deux boutons : « Nouvelle offre », « Nouvelle facture ».
struct RangeeNouveauDocument: View {
    @Environment(ModeleApp.self) private var app
    var chantierId: String?

    var body: some View {
        HStack(spacing: Espace.s) {
            bouton(.offre, titre: "Nouvelle offre", icone: "doc.badge.plus")
            bouton(.facture, titre: "Nouvelle facture", icone: "doc.text.fill")
        }
    }

    private func bouton(_ type: TypeDemandeDocument, titre: String, icone: String) -> some View {
        Button {
            app.nouveauDocument(type, chantier: chantierId)
        } label: {
            Label(titre, systemImage: icone)
                .styleTexte(14, relativeTo: .subheadline, graisse: .semibold)
                .foregroundStyle(Color.encre)
                .frame(maxWidth: .infinity, minHeight: 48)
                .surfaceCarte(rayon: 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nouveau-\(type.rawValue)")
    }
}

struct NouveauDocumentView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    let offreSource: OffreSignee?

    @State private var demande: DemandeDocument
    @State private var chantierId: String?
    @State private var libre = ""
    @State private var photos: [FormulaireMultipart.Fichier] = []
    @State private var dictee = Dictee()
    @State private var analyse = false
    @State private var envoi = false
    @State private var acompte = false
    @State private var resultat: ModeleSaisie.ResultatTerrain?
    @FocusState private var saisieActive: Bool

    init(creation: DemandeCreation, dossier: Dossier?) {
        offreSource = creation.offre
        var d: DemandeDocument
        if let offre = creation.offre {
            d = DemandeDocument.facture(depuis: offre)
        } else {
            d = DemandeDocument(type: creation.type, chantierId: dossier?.id, chantier: dossier?.titre, client: dossier?.client ?? "")
        }
        _demande = State(initialValue: d)
        _chantierId = State(initialValue: d.chantierId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.m) {
                    if let resultat {
                        ResultatEnvoiTerrain(resultat: resultat) { fermer() }.padding(.top, Espace.l)
                    } else {
                        formulaire
                    }
                }
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, Espace.xxl)
                .animation(.endry, value: resultat)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FondAmbiant())
            .navigationTitle(demande.type == .offre ? "Nouvelle offre" : "Nouvelle facture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { fermer() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { saisieActive = false }.fontWeight(.semibold).accessibilityIdentifier("clavier-ok")
                }
            }
        }
        .onChange(of: dictee.ecoute) { _, ecoute in
            guard !ecoute, !dictee.transcription.isEmpty else { return }
            Task { await remplir(depuis: dictee.transcription) }
        }
        .onChange(of: chantierId) { _, id in
            guard let d = app.dossier(id) else { return }
            if demande.client.trimmingCharacters(in: .whitespaces).isEmpty { demande.client = d.client }
        }
    }

    // MARK: Formulaire

    @ViewBuilder
    private var formulaire: some View {
        if offreSource == nil {
            Picker("Document", selection: $demande.type) {
                ForEach(TypeDemandeDocument.allCases) { Text($0.titre).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.top, Espace.s)
        }
        Text("Dites ce qu’il faut : l’assistant prépare \(demande.type == .offre ? "l’offre" : "la facture") dans Bexio. Elle vous attendra dans Aujourd’hui : rien ne part au client sans votre Oui.")
            .styleTexte(14).foregroundStyle(Color.encreDouce)

        HStack(spacing: Espace.s) {
            BoutonMicroCompact(ecoute: dictee.ecoute, niveau: dictee.niveau) { Task { await dictee.basculer() } }
            VStack(alignment: .leading, spacing: 2) {
                Text(analyse ? "Je mets en forme…" : dictee.ecoute ? (dictee.transcription.isEmpty ? "J’écoute…" : dictee.transcription)
                     : "Dicter \(demande.type == .offre ? "l’offre" : "la facture")")
                    .styleTexte(15, graisse: .medium).lineLimit(4)
                Text("« Offre pour Mme Gander : adoucisseur, pose, une journée à deux. »")
                    .styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
            }
            if analyse { ProgressView() }
        }
        .padding(Espace.m)
        .surfaceCarte(rayon: 20)

        ChoixChantier(chantierId: $chantierId, libre: $libre)

        SectionTerrain(titre: "Client", icone: "person") {
            TextField("Nom du client", text: $demande.client)
                .textContentType(.name).focused($saisieActive)
                .styleTexte(16, graisse: .medium)
                .accessibilityIdentifier("champ-client")
            TextField("E-mail (facultatif)", text: Binding(get: { demande.clientEmail ?? "" }, set: { demande.clientEmail = $0.isEmpty ? nil : $0 }))
                .keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never)
                .focused($saisieActive).styleTexte(15)
            TextField("Adresse (facultatif)", text: Binding(get: { demande.clientAdresse ?? "" }, set: { demande.clientAdresse = $0.isEmpty ? nil : $0 }),
                      axis: .vertical)
                .textContentType(.fullStreetAddress).focused($saisieActive).styleTexte(15).lineLimit(1...3)
        }

        SectionTerrain(titre: "Objet", icone: "text.alignleft") {
            TextField(demande.type == .offre ? "Ex. Remplacement du chauffe-eau 300 l" : "Ex. Travaux de la salle de bains", text: $demande.objet, axis: .vertical)
                .focused($saisieActive).styleTexte(16, graisse: .medium).lineLimit(1...3)
                .accessibilityIdentifier("champ-objet")
        }

        SectionTerrain(titre: "Lignes", icone: "list.bullet") {
            ForEach($demande.lignes) { $ligne in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Désignation", text: $ligne.designation, axis: .vertical)
                            .focused($saisieActive).styleTexte(15, graisse: .medium).lineLimit(1...2)
                        Button(role: .destructive) {
                            demande.lignes.removeAll { $0.id == ligne.id }
                        } label: { Image(systemName: "minus.circle.fill").foregroundStyle(Color.rouille) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Retirer la ligne"))
                    }
                    HStack(spacing: Espace.s) {
                        TextField("Qté", value: $ligne.quantite, format: .number)
                            .keyboardType(.decimalPad).focused($saisieActive).frame(width: 64)
                        TextField("Unité", text: Binding(get: { ligne.unite ?? "" }, set: { ligne.unite = $0.isEmpty ? nil : $0 }))
                            .textInputAutocapitalization(.never).focused($saisieActive).frame(width: 70)
                        TextField("Prix HT (facultatif)", value: $ligne.prixUnitaire, format: .number)
                            .keyboardType(.decimalPad).focused($saisieActive)
                    }
                    .styleTexte(14)
                    .foregroundStyle(Color.encreDouce)
                }
                .padding(.vertical, 4)
                Divider().overlay(Color.encrePale.opacity(0.2))
            }
            Button {
                demande.lignes.append(LigneDemandee(designation: ""))
            } label: { Label("Ajouter une ligne", systemImage: "plus.circle") }
                .styleTexte(14, graisse: .semibold).foregroundStyle(Color.bronze)
            Text("Sans prix, le bureau applique ses tarifs.")
                .styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
        }

        if demande.type == .facture {
            SectionTerrain(titre: "Facture", icone: "doc.text") {
                TextField("Offre de base (ex. AN-00028), facultatif",
                          text: Binding(get: { demande.offreNumero ?? "" }, set: { demande.offreNumero = $0.isEmpty ? nil : $0 }))
                    .textInputAutocapitalization(.characters).focused($saisieActive).styleTexte(15)
                Toggle("Facture d’acompte", isOn: Binding(get: { demande.acomptePourcent != nil },
                                                           set: { demande.acomptePourcent = $0 ? 30 : nil }))
                    .styleTexte(15).tint(Color.bronze)
                if let a = demande.acomptePourcent {
                    Stepper("Acompte : \(a) %", value: Binding(get: { a }, set: { demande.acomptePourcent = $0 }), in: 10...90, step: 5)
                        .styleTexte(15)
                }
                Stepper("Paiement à \(demande.delaiPaiementJours ?? 30) jours",
                        value: Binding(get: { demande.delaiPaiementJours ?? 30 }, set: { demande.delaiPaiementJours = $0 }), in: 10...90, step: 5)
                    .styleTexte(15)
            }
        } else {
            SectionTerrain(titre: "Offre", icone: "calendar") {
                Stepper("Valable \(demande.validiteJours ?? 30) jours",
                        value: Binding(get: { demande.validiteJours ?? 30 }, set: { demande.validiteJours = $0 }), in: 10...120, step: 5)
                    .styleTexte(15)
            }
        }

        SectionTerrain(titre: "Consignes pour l’assistant", icone: "text.bubble") {
            TextField("Variante, délai, remarque pour le client…", text: $demande.consignes, axis: .vertical)
                .focused($saisieActive).styleTexte(15).lineLimit(2...8)
        }
        SectionTerrain(titre: "Photos", icone: "camera") {
            PhotosTerrain(photos: $photos, prefixe: demande.type.rawValue)
        }

        let manques = demandeComplete.manques
        if !manques.isEmpty {
            Label("Il manque " + manques.joined(separator: " et ") + ".", systemImage: "info.circle")
                .styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
        }
        Button {
            saisieActive = false
            Task { await transmettre() }
        } label: {
            HStack(spacing: Espace.xs) {
                if envoi { ProgressView().tint(Color.fond) } else { Image(systemName: "paperplane.fill") }
                Text(envoi ? "Transmission…" : "Transmettre au bureau")
            }
        }
        .buttonStyle(BoutonPrincipal())
        .disabled(envoi || !manques.isEmpty)
        .accessibilityIdentifier("transmettre-document")
    }

    // MARK: Actions

    private var demandeComplete: DemandeDocument {
        var d = demande
        d.chantierId = chantierId
        d.chantier = app.chantierPropose(chantierId)?.titre ?? (libre.isEmpty ? d.chantier : libre)
        d.lignes = d.lignes.filter { !$0.designation.trimmingCharacters(in: .whitespaces).isEmpty }
        return d
    }

    private func remplir(depuis texte: String) async {
        analyse = true
        defer { analyse = false }
        let r = await ExtractionIA.document(texte, type: demande.type)
        if demande.client.trimmingCharacters(in: .whitespaces).isEmpty, !r.client.isEmpty { demande.client = r.client }
        if demande.objet.trimmingCharacters(in: .whitespaces).isEmpty, !r.objet.isEmpty { demande.objet = r.objet }
        let existantes = Set(demande.lignes.map { $0.designation.lowercased() })
        demande.lignes.removeAll { $0.designation.trimmingCharacters(in: .whitespaces).isEmpty }
        demande.lignes += r.lignes.filter { !existantes.contains($0.designation.lowercased()) }
        // La dictée complète part aussi, telle quelle : l'assistant y trouve ce que les lignes n'ont pas pris.
        let consignes = demande.consignes.trimmingCharacters(in: .whitespacesAndNewlines)
        demande.consignes = consignes.isEmpty ? texte : consignes + "\n" + texte
    }

    private func transmettre() async {
        envoi = true
        let r = await app.transmettre(demandeComplete.envoi(photos: photos))
        envoi = false
        withAnimation(.endry) { resultat = r }
        if case .transmis = r { await app.decisions?.charger() }
    }
}

// MARK: - Offres signées

struct SectionOffresSignees: View {
    @Environment(ModeleApp.self) private var app
    var modele: ModeleOffresSignees

    var body: some View {
        if !modele.offres.isEmpty {
            VStack(alignment: .leading, spacing: Espace.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Offres signées").styleTitre(22, relativeTo: .title3).foregroundStyle(Color.encre)
                        .accessibilityAddTraits(.isHeader)
                    if modele.aPlanifier > 0 {
                        Pastille(texte: "\(modele.aPlanifier) à planifier", couleur: .or, icone: "calendar.badge.exclamationmark")
                    }
                    Spacer()
                }
                if !modele.parLePC {
                    Text("D’après les chantiers acceptés. Le détail des signatures reçues (e-mail, courrier) arrivera quand le PC appliquera le contrat v1.5.")
                        .styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
                }
                ForEach(modele.groupes.map { $0.suite }, id: \.self) { suite in
                    let liste = modele.offres.filter { $0.suite == suite }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(suite.libelle.uppercased())
                            .tracking(1.6)
                            .styleTexte(11, relativeTo: .caption2, graisse: .semibold)
                            .foregroundStyle(Color.bronze)
                            .padding(.top, Espace.s)
                        ForEach(Array(liste.enumerated()), id: \.element.id) { index, offre in
                            if index > 0 { Divider().overlay(Color.encrePale.opacity(0.2)) }
                            LigneOffreSignee(offre: offre)
                        }
                    }
                    .padding(.horizontal, Espace.m)
                    .padding(.bottom, Espace.xs)
                    .surfaceCarte(rayon: 20)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("offres-signees")
        }
    }
}

struct LigneOffreSignee: View {
    @Environment(ModeleApp.self) private var app
    var offre: OffreSignee

    var body: some View {
        HStack(alignment: .top, spacing: Espace.s) {
            Image(systemName: offre.source.icone)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.bronze)
                .frame(width: 34, height: 34)
                .background(Color.or.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(offre.client).styleTexte(15, graisse: .semibold).foregroundStyle(Color.encre).lineLimit(2)
                    Spacer(minLength: Espace.xs)
                    if let m = offre.montant, m > 0 {
                        MontantView(montant: m, taille: 15, afficherCentimes: false, style: .subheadline)
                    }
                }
                Text([offre.numero, offre.titre].compactMap { $0 }.joined(separator: " · "))
                    .styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce).lineLimit(2)
                if let reception = reception {
                    Text(reception).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale).lineLimit(2)
                }
            }
            Menu {
                if let doc = offre.documentSigne {
                    Button("Voir l’offre signée", systemImage: "signature") { ouvrir(doc, nom: "\(offre.numero ?? "offre") signée") }
                }
                if let doc = offre.document {
                    Button("Voir l’offre", systemImage: "doc") { ouvrir(doc, nom: offre.numero ?? "offre") }
                }
                Button("Facturer l’acompte", systemImage: "doc.text.fill") { app.nouveauDocument(.facture, offre: offre) }
                if let id = offre.chantierId {
                    Button("Ouvrir le chantier", systemImage: "hammer") { app.ouvrirChantier(id) }
                }
                if let ref = offre.decisionReference, app.suiviActions?.pour(reference: ref) != nil {
                    Button("Suivi", systemImage: "list.bullet.below.rectangle") { app.ouvrirSuivi("D:" + ref) }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundStyle(Color.bronze)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel(Text("Actions pour l’offre \(offre.numero ?? offre.client)"))
            .accessibilityIdentifier("actions-offre-\(offre.id)")
        }
        .padding(.vertical, Espace.s)
    }

    private var reception: String? {
        guard !offre.deduite else { return nil }
        var t = "Signée"
        if let s = offre.signeeLe { t += " le \(DateEndry.courte(s))" }
        if offre.source != .inconnue { t += ", reçue \(offre.source.libelle)" }
        if let r = offre.recueLe, r.prefix(10) != (offre.signeeLe ?? "").prefix(10) { t += " le \(DateEndry.courte(String(r.prefix(10))))" }
        if let e = offre.expediteur { t += " · \(e)" }
        return t
    }

    private func ouvrir(_ chemin: String, nom: String) {
        Task { await app.documents.ouvrir(chemin, nom: nom + ".pdf", api: app.session.api) }
    }
}
