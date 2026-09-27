import EndryKit
import SwiftUI

/// Réglages du suivi des offres, gardés sur l'iPhone.
enum ReglagesSuivi {
    static let cleSeuil = "suivi-offres-seuil"
    static let cleEcartees = "suivi-offres-ecartees"

    static func ecartees(_ brut: String) -> Set<String> {
        Set(brut.split(separator: ",").map(String.init))
    }
}

extension ModeleApp {
    /// Offres émises depuis le seuil réglé, sans réponse, non écartées.
    var offresASuivre: [OffreASuivre] {
        let defauts = UserDefaults.standard
        let seuil = defauts.object(forKey: ReglagesSuivi.cleSeuil) as? Int ?? SuiviOffres.seuilParDefaut
        let ecartees = ReglagesSuivi.ecartees(defauts.string(forKey: ReglagesSuivi.cleEcartees) ?? "")
        return SuiviOffres.aSuivre(argent?.argent?.offres.offres ?? [], seuil: seuil, ecartees: ecartees)
    }
}

// MARK: - Offres sans réponse

/// Carte « Offres sans réponse » (Finances) : le bureau prépare un message de suivi, le patron le valide.
struct CarteOffresASuivre: View {
    @Environment(ModeleApp.self) private var app
    @AppStorage(ReglagesSuivi.cleSeuil) private var seuil = SuiviOffres.seuilParDefaut
    @AppStorage(ReglagesSuivi.cleEcartees) private var ecarteesBrut = ""
    var offres: [Offre]
    @State private var enPreparation: OffreASuivre?

    private var liste: [OffreASuivre] {
        SuiviOffres.aSuivre(offres, seuil: seuil, ecartees: ReglagesSuivi.ecartees(ecarteesBrut))
    }

    var body: some View {
        if !liste.isEmpty {
            VStack(alignment: .leading, spacing: Espace.s) {
                EnTeteSection(titre: "Sans réponse", detail: "depuis \(seuil) jours et plus")
                VStack(spacing: 0) {
                    ForEach(Array(liste.enumerated()), id: \.element.id) { index, a in
                        ligne(a)
                        if index < liste.count - 1 { Rectangle().fill(Color.filet).frame(height: 0.5) }
                    }
                }
                .padding(.horizontal, Espace.m)
                .surfaceCarte(rayon: 22)
                Text("Suivi d’offre préparé par le bureau, jamais envoyé sans votre Oui. Aucune relance de facture.")
                    .styleTexte(12, relativeTo: .caption)
                    .foregroundStyle(Color.encrePale)
            }
            .sheet(item: $enPreparation) { a in
                FeuillePreparation(
                    titre: "Suivi de l’offre \(a.offre.numero)",
                    sousTitre: "\(a.offre.client) · \(a.offre.titre)",
                    explication: "Le bureau prépare un message courtois pour savoir où en est le client. Il apparaîtra dans vos décisions ; rien ne part sans votre Oui.",
                    suggestions: ["Ton chaleureux", "Proposer une variante moins chère", "Rappeler la date de validité", "Proposer une visite"]
                ) { consignes in
                    guard let api = app.session.api else { return .failure(.horsLigne) }
                    do { return .success(try await api.preparerSuivi(a, consignes: consignes)) } catch { return .failure(error) }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func ligne(_ a: OffreASuivre) -> some View {
        HStack(alignment: .center, spacing: Espace.s) {
            VStack(alignment: .leading, spacing: 3) {
                Text(a.offre.client).styleTexte(15, relativeTo: .subheadline, graisse: .semibold).foregroundStyle(Color.encre)
                Text("\(a.offre.numero) · \(a.offre.titre)").styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encreDouce).lineLimit(1)
                Text(a.urgence)
                    .styleTexte(11, relativeTo: .caption2, graisse: .semibold)
                    .foregroundStyle((a.expireDans ?? 99) <= 7 ? Color.ambre : Color.encrePale)
            }
            Spacer(minLength: Espace.xs)
            Button {
                enPreparation = a
            } label: {
                Text("Préparer un suivi")
                    .styleTexte(13, relativeTo: .footnote, graisse: .semibold)
                    .foregroundStyle(Color.espressoProfond)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.degradeOr, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("suivi-\(a.offre.numero)")
        }
        .padding(.vertical, Espace.s)
        .contextMenu {
            Button("Ne plus suivre cette offre", systemImage: "eye.slash") {
                var e = ReglagesSuivi.ecartees(ecarteesBrut)
                e.insert(a.id)
                ecarteesBrut = e.sorted().joined(separator: ",")
            }
        }
    }
}

// MARK: - Entretiens

/// Carte d'entrée (Entreprise) : entretiens à planifier d'ici un mois.
struct CarteEntretiens: View {
    var modele: ModeleEntretiens

    var body: some View {
        NavigationLink {
            EntretiensView(modele: modele)
        } label: {
            HStack(spacing: Espace.m) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.bronze)
                    .frame(width: 44, height: 44)
                    .background(Color.or.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Entretiens récurrents").styleTexte(16, graisse: .semibold).foregroundStyle(Color.encre)
                    Text(detail).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
                }
                Spacer()
                if !modele.aPlanifier.isEmpty {
                    Text("\(modele.aPlanifier.count)")
                        .font(Police.titre(15, relativeTo: .subheadline))
                        .foregroundStyle(Color.espressoProfond)
                        .frame(minWidth: 28, minHeight: 28)
                        .background(.degradeOr, in: Circle())
                }
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Color.encrePale)
            }
            .padding(Espace.m)
            .surfaceCarte(rayon: 20)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("carte-entretiens")
        .task { if modele.etat == .initial { await modele.charger() } }
    }

    private var detail: String {
        if !modele.disponible { return "Chaudières, boilers, adoucisseurs : bientôt fournis par le bureau" }
        let n = modele.aPlanifier.count
        return n == 0 ? "Rien à planifier ce mois" : "\(n) à planifier d’ici un mois"
    }
}

struct EntretiensView: View {
    @Environment(ModeleApp.self) private var app
    var modele: ModeleEntretiens
    @State private var enPreparation: Entretien?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espace.l) {
                VStack(alignment: .leading, spacing: Espace.xxs) {
                    Text("Revenus réguliers").styleSurtitre()
                    Text("Entretiens").styleTitre(34, relativeTo: .largeTitle).foregroundStyle(Color.encre)
                    Text("Repérés par le bureau dans Bexio. Une proposition de rendez-vous se prépare en un geste ; elle attend votre Oui.")
                        .styleTexte(14).foregroundStyle(Color.encreDouce)
                }
                .padding(.top, Espace.m)

                if !modele.disponible {
                    VStack(spacing: Espace.m) {
                        EtatVide(titre: "Bientôt", message: "Le PC ne fournit pas encore la liste des entretiens. Demandez au bureau de la dresser : il la préparera à partir de Bexio.",
                                 icone: "wrench.and.screwdriver")
                        Button("Demander la liste au bureau") {
                            Task {
                                let r = await app.saisie?.transmettre(demande: "[Pour l’agent Secrétariat] Dresser la liste des entretiens périodiques à venir (chaudières, boilers, adoucisseurs, pompes à chaleur) à partir de Bexio, avec les échéances. Ne rien envoyer aux clients.")
                                app.toast = Toast(r == .transmise ? "Demandé au bureau." : "Gardé : partira au retour du réseau.")
                            }
                        }
                        .buttonStyle(BoutonSecondaire())
                    }
                } else if case .chargement = modele.etat {
                    Squelette(hauteur: 180, rayon: Espace.rayon)
                } else if case .erreur(let e) = modele.etat {
                    VueErreur(erreur: e) { Task { await modele.charger() } }
                } else if modele.entretiens.isEmpty {
                    EtatVide(titre: "Aucun entretien", message: "Le bureau n’a repéré aucun entretien périodique.")
                } else {
                    ForEach(modele.groupes) { groupe in
                        VStack(alignment: .leading, spacing: Espace.s) {
                            EnTeteSection(titre: groupe.titre, detail: "\(groupe.entretiens.count)")
                            VStack(spacing: 0) {
                                ForEach(Array(groupe.entretiens.enumerated()), id: \.element.id) { i, e in
                                    ligne(e)
                                    if i < groupe.entretiens.count - 1 { Rectangle().fill(Color.filet).frame(height: 0.5) }
                                }
                            }
                            .padding(.horizontal, Espace.m)
                            .surfaceCarte(rayon: 22)
                        }
                    }
                }
            }
            .padding(.horizontal, Espace.bord)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .refreshable { await modele.charger() }
        .background(FondAmbiant())
        .navigationBarTitleDisplayMode(.inline)
        .task { await modele.charger() }
        .sheet(item: $enPreparation) { e in
            FeuillePreparation(
                titre: "Entretien — \(e.client)",
                sousTitre: [e.appareil, e.lieu].compactMap { $0 }.joined(separator: " · "),
                explication: "Le bureau prépare une proposition de rendez-vous au client. Elle apparaîtra dans vos décisions ; rien ne part sans votre Oui.",
                suggestions: ["Plutôt le matin", "Cette semaine si possible", "Proposer deux dates", "Rappeler le tarif forfaitaire"]
            ) { consignes in
                await modele.proposer(e, consignes: consignes)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func ligne(_ e: Entretien) -> some View {
        HStack(spacing: Espace.s) {
            VStack(alignment: .leading, spacing: 3) {
                Text(e.client).styleTexte(15, graisse: .semibold).foregroundStyle(Color.encre)
                Text(e.appareil).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce).lineLimit(2)
                HStack(spacing: 6) {
                    if let lieu = e.lieu { Text(lieu) }
                    if let echeance = e.echeance { Text("· échéance \(DateEndry.courte(echeance))") }
                    if let p = e.periodicite { Text("· \(p)") }
                }
                .styleTexte(11, relativeTo: .caption2)
                .foregroundStyle(Color.encrePale)
            }
            Spacer(minLength: Espace.xs)
            if e.peutProposer {
                Button {
                    enPreparation = e
                } label: {
                    if modele.enPreparation == e.id {
                        ProgressView()
                    } else {
                        Text("Proposer")
                            .styleTexte(13, relativeTo: .footnote, graisse: .semibold)
                            .foregroundStyle(Color.espressoProfond)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.degradeOr, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("proposer-\(e.id)")
            } else if let reference = e.decisionReference {
                Button {
                    app.ouvrir(reference: reference)
                } label: {
                    Label(e.statut.libelle, systemImage: "checkmark.seal")
                        .styleTexte(12, relativeTo: .caption, graisse: .semibold)
                        .foregroundStyle(Color.vertControle)
                }
                .buttonStyle(.plain)
            } else {
                Text(e.statut.libelle).styleTexte(12, relativeTo: .caption, graisse: .semibold).foregroundStyle(Color.encrePale)
            }
        }
        .padding(.vertical, Espace.s)
    }
}

// MARK: - Préparation par le bureau

/// Feuille commune : consignes facultatives, « Préparer », puis la décision à valider.
struct FeuillePreparation: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    var titre: String
    var sousTitre: String
    var explication: String
    var suggestions: [String]
    var preparer: (String) async -> Result<ReponsePreparation, ErreurAPI>

    @State private var consignes = ""
    @State private var envoi = false
    @State private var resultat: Result<ReponsePreparation, ErreurAPI>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.m) {
                    Text(sousTitre).styleTexte(14).foregroundStyle(Color.encreDouce)
                    switch resultat {
                    case .success(let r):
                        Label(r.message ?? "Préparé.", systemImage: "checkmark.seal.fill")
                            .styleTexte(16, graisse: .semibold)
                            .foregroundStyle(Color.vertControle)
                        if let reference = r.decisionReference {
                            Button {
                                fermer()
                                app.ouvrir(reference: reference)
                            } label: { Label("Voir la décision", systemImage: "arrow.right.circle.fill") }
                                .buttonStyle(BoutonPrincipal())
                        } else {
                            Text("La décision apparaîtra dans « Aujourd’hui » dès que le bureau l’aura préparée.")
                                .styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encrePale)
                        }
                        Button("Terminer") { fermer() }.buttonStyle(BoutonSecondaire())
                    case .failure(let e):
                        Label(e.message, systemImage: "exclamationmark.triangle.fill")
                            .styleTexte(15, graisse: .medium).foregroundStyle(Color.rouille)
                        formulaire
                    case nil:
                        formulaire
                    }
                }
                .padding(Espace.l)
            }
            .navigationTitle(titre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { fermer() } } }
        }
    }

    @ViewBuilder
    private var formulaire: some View {
        Text(explication).styleTexte(14).foregroundStyle(Color.encre)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Espace.xs) {
                ForEach(suggestions, id: \.self) { s in
                    Button(s) { consignes = consignes.isEmpty ? s : consignes + ". " + s }
                        .styleTexte(13, relativeTo: .footnote, graisse: .medium)
                        .foregroundStyle(Color.encre)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.surfaceCreuse, in: Capsule())
                        .buttonStyle(.plain)
                }
            }
        }
        TextField("Consignes pour le bureau (facultatif)", text: $consignes, axis: .vertical)
            .styleTexte(15)
            .lineLimit(2...5)
            .padding(Espace.s)
            .surfaceCarte(rayon: 16)
        Button {
            Task {
                envoi = true
                resultat = await preparer(consignes)
                envoi = false
            }
        } label: {
            HStack(spacing: Espace.xs) {
                if envoi { ProgressView().tint(Color.fond) } else { Image(systemName: "sparkles") }
                Text(envoi ? "Préparation…" : "Faire préparer par le bureau")
            }
        }
        .buttonStyle(BoutonPrincipal())
        .disabled(envoi)
        .accessibilityIdentifier("preparer")
    }
}
