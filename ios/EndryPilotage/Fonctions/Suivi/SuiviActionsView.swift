import EndryKit
import SwiftUI

// MARK: - Suivi de chaque geste : ce que vous avez décidé, ce que le bureau en a fait

extension EtatSuivi {
    var couleur: Color {
        switch self {
        case .transmis: .ambre
        case .enCours: .bronze
        case .fait: .vertControle
        case .erreur: .rouille
        case .ecarte: .encrePale
        case .corrige: .bronze
        }
    }

    var icone: String {
        switch self {
        case .transmis: "clock.fill"
        case .enCours: "gearshape.2.fill"
        case .fait: "checkmark"
        case .erreur: "exclamationmark.triangle.fill"
        case .ecarte: "xmark"
        case .corrige: "pencil"
        }
    }
}

enum LibelleSuivi {
    /// « Vous », « Le bureau », « L'assistant · Achats ».
    static func qui(_ qui: String) -> String {
        switch qui {
        case "vous": "Vous"
        case "bureau": "Le bureau"
        default: AgentBureau(rawValue: qui).map { "L’assistant · \($0.nom)" } ?? qui.capitalized
        }
    }

    static func icone(_ qui: String) -> String {
        switch qui {
        case "vous": "person.fill"
        case "bureau": "building.2.fill"
        default: AgentBureau(rawValue: qui)?.icone ?? "sparkles"
        }
    }

    static func source(_ s: SourceSuivi) -> String {
        switch s {
        case .pc: "Compte rendu du bureau"
        case .journal: "D’après le journal du bureau"
        case .saisies: "D’après l’historique des saisies"
        case .geste: "En attente du compte rendu du bureau"
        }
    }
}

/// Pastille d'état : icône animée tant que le bureau travaille.
struct PastilleEtatSuivi: View {
    var etat: EtatSuivi
    var taille: CGFloat = 36
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations
    private var animer: Bool { !reduireAnimations && !Configuration.testsUI }

    var body: some View {
        ZStack {
            Circle().fill(etat.couleur.opacity(0.16))
            Image(systemName: etat.icone)
                .font(.system(size: taille * 0.42, weight: .bold))
                .foregroundStyle(etat.couleur)
                // Animation brève et bornée : jamais de boucle infinie (batterie, et les tests d'interface attendent
                // que l'écran soit immobile).
                .symbolEffect(.rotate, options: .repeat(.periodic(3, delay: 0.4)), isActive: animer && etat == .enCours)
                .symbolEffect(.pulse, options: .repeat(.periodic(3, delay: 0.4)), isActive: animer && etat == .transmis)
        }
        .frame(width: taille, height: taille)
        .accessibilityHidden(true)
    }
}

struct LigneSuivi: View {
    var action: ActionSuivie

    var body: some View {
        HStack(alignment: .top, spacing: Espace.s) {
            PastilleEtatSuivi(etat: action.etat)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(action.etat.libelle.uppercased())
                        .tracking(1.2)
                        .styleTexte(10, relativeTo: .caption2, graisse: .semibold)
                        .foregroundStyle(action.etat.couleur)
                    Text(action.libelleGeste).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
                    if let agent = action.agent, let a = AgentBureau(rawValue: agent) {
                        Text("· \(a.nom)").styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
                    }
                }
                Text(action.titre)
                    .styleTexte(15, graisse: .semibold)
                    .foregroundStyle(Color.encre)
                    .lineLimit(2)
                Text(action.ligneResultat)
                    .styleTexte(13, relativeTo: .footnote)
                    .foregroundStyle(Color.encreDouce)
                    .lineLimit(2)
                if !action.envois.isEmpty {
                    Label("Envoyé à \(action.envois.map(\.destinataire).joined(separator: ", "))", systemImage: "paperplane.fill")
                        .styleTexte(12, relativeTo: .caption, graisse: .semibold)
                        .foregroundStyle(Color.bronze)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Color.encrePale).padding(.top, 10)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Accueil : « Fait récemment »

struct SectionFaitRecemment: View {
    @Environment(ModeleApp.self) private var app
    var modele: ModeleSuiviActions
    @State private var toutVoir = false

    var body: some View {
        let recents = modele.recents()
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: Espace.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Fait récemment").styleTitre(22, relativeTo: .title3).foregroundStyle(Color.encre)
                        .accessibilityAddTraits(.isHeader)
                    if !modele.enAttente.isEmpty {
                        Pastille(texte: "\(modele.enAttente.count) en cours", couleur: .ambre, icone: "clock.fill")
                    }
                    Spacer()
                    Button("Tout voir") { toutVoir = true }
                        .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                        .foregroundStyle(Color.bronze)
                        .accessibilityIdentifier("suivi-tout-voir")
                }
                VStack(spacing: 0) {
                    ForEach(Array(recents.prefix(4).enumerated()), id: \.element.id) { index, action in
                        if index > 0 { Divider().overlay(Color.encrePale.opacity(0.2)) }
                        Button { app.ouvrirSuivi(action.id) } label: { LigneSuivi(action: action).padding(.vertical, Espace.s) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("suivi-\(action.reference ?? action.saisieId ?? action.id)")
                    }
                }
                .padding(.horizontal, Espace.m)
                .padding(.vertical, Espace.xs)
                .surfaceCarte(rayon: 20)
                .animation(.endry, value: recents.map(\.etat))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fait-recemment")
            .sheet(isPresented: $toutVoir) { JournalSuiviView(modele: modele) }
        }
    }
}

// MARK: - Fiche : ce qui s'est passé, de votre geste au résultat

struct FicheSuiviView: View {
    @Environment(\.dismiss) private var fermer
    var modele: ModeleSuiviActions
    var id: String

    var body: some View {
        NavigationStack {
            FicheSuiviContenu(modele: modele, id: id, fermer: { fermer() })
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
        }
    }
}

/// Contenu de la fiche, présentable en feuille ou poussé dans une pile de navigation.
struct FicheSuiviContenu: View {
    @Environment(ModeleApp.self) private var app
    var modele: ModeleSuiviActions
    var id: String
    var fermer: () -> Void = {}
    @State private var question = false
    @State private var demandeEnvoyee = false

    var body: some View {
        ScrollView {
            if let action = modele.action(id) {
                contenu(action)
                    .padding(Espace.bord)
                    .verrouillerLargeur()
            } else {
                EtatVide(titre: "Introuvable", message: "Cette action n’est plus dans le suivi (plus de 30 jours).", icone: "clock")
                    .padding(Espace.bord)
                    .verrouillerLargeur()
            }
        }
        .background(FondAmbiant())
        .refreshable { await modele.rafraichir(saisies: app.saisie?.historique ?? []) }
        .navigationTitle("Suivi")
        .navigationBarTitleDisplayMode(.inline)
        .task { await modele.rafraichir(saisies: app.saisie?.historique ?? []) }
    }

    @ViewBuilder
    private func contenu(_ a: ActionSuivie) -> some View {
        VStack(alignment: .leading, spacing: Espace.l) {
            HStack(spacing: Espace.m) {
                PastilleEtatSuivi(etat: a.etat, taille: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.etat.libelle).styleTitre(30, relativeTo: .largeTitle).foregroundStyle(a.etat.couleur)
                        .accessibilityIdentifier("suivi-etat")
                    Text(a.libelleGeste + (a.reference.map { " · \($0)" } ?? ""))
                        .styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encrePale)
                }
            }
            Text(a.titre).styleTitre(24, relativeTo: .title2).foregroundStyle(Color.encre)
            if !a.ligneResultat.isEmpty {
                Text(a.ligneResultat).styleTexte(16).foregroundStyle(Color.encreDouce)
            }

            SectionTerrain(titre: "Ce qui s’est passé", icone: "list.bullet.below.rectangle") {
                ForEach(Array(a.etapes.enumerated()), id: \.element.id) { index, etape in
                    ligneEtape(etape, derniere: index == a.etapes.count - 1)
                }
                if !a.etat.termine {
                    HStack(spacing: Espace.s) {
                        if Configuration.testsUI {
                            Image(systemName: "hourglass").foregroundStyle(Color.encrePale)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Text(attente(a)).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encrePale)
                    }
                }
                Text(LibelleSuivi.source(a.source) + (modele.majLe.map { " · relu à \(DateEndry.heure($0))" } ?? ""))
                    .styleTexte(11, relativeTo: .caption2).foregroundStyle(Color.encrePale)
            }

            if !a.fichiers.isEmpty {
                SectionTerrain(titre: "Produit par le bureau", icone: "doc.fill") {
                    ForEach(a.fichiers) { f in
                        HStack(spacing: Espace.s) {
                            Image(systemName: "doc.text.fill").foregroundStyle(Color.bronze)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.nom).styleTexte(15, graisse: .semibold).foregroundStyle(Color.encre)
                                if let e = f.emplacement { Text(e).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale) }
                            }
                            Spacer()
                            if let doc = f.document {
                                Button("Ouvrir") { Task { await app.documents.ouvrir(doc, nom: f.nom, api: app.session.api) } }
                                    .styleTexte(14, graisse: .semibold).foregroundStyle(Color.bronze)
                            }
                        }
                    }
                }
            }

            SectionTerrain(titre: "Envois à des tiers", icone: "paperplane") {
                if a.envois.isEmpty {
                    Label(texteSansEnvoi(a), systemImage: "checkmark.shield")
                        .styleTexte(14).foregroundStyle(Color.encreDouce)
                        .accessibilityIdentifier("suivi-aucun-envoi")
                } else {
                    ForEach(a.envois) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(e.destinataire, systemImage: e.canal == "courrier" ? "envelope.fill" : "paperplane.fill")
                                .styleTexte(15, graisse: .semibold).foregroundStyle(Color.encre)
                            Text([e.objet, e.le.map { "à \(DateEndry.heure($0))" }].compactMap { $0 }.joined(separator: " · "))
                                .styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
                        }
                    }
                }
            }

            if let chantier = a.chantierId, let dossier = app.dossier(chantier) {
                Button {
                    fermer()
                    app.ouvrirChantier(dossier.id)
                } label: { Label("Chantier : \(dossier.titre)", systemImage: "hammer") }
                    .buttonStyle(BoutonSecondaire())
            }
            if let nouvelle = a.decisionPreparee {
                Button {
                    fermer()
                    app.ouvrir(reference: nouvelle)
                } label: { Label("Voir la décision préparée", systemImage: "checkmark.seal") }
                    .buttonStyle(BoutonPrincipal())
            }
            if a.etat != .ecarte {
                Button {
                    question = true
                } label: { Label(demandeEnvoyee ? "Question transmise" : "Demander au bureau où ça en est", systemImage: "questionmark.bubble") }
                    .buttonStyle(BoutonSecondaire())
                    .disabled(demandeEnvoyee)
                    .confirmationDialog("Demander au bureau où en est cette action ?", isPresented: $question, titleVisibility: .visible) {
                        Button("Envoyer la question") { Task { await demander(a) } }
                    } message: {
                        Text("Le bureau s’en occupe et répond ; tout envoi reste une décision à glisser.")
                    }
            }
        }
    }

    private func ligneEtape(_ e: EtapeSuivi, derniere: Bool) -> some View {
        HStack(alignment: .top, spacing: Espace.s) {
            VStack(spacing: 0) {
                Image(systemName: e.estErreur ? "exclamationmark.triangle.fill" : LibelleSuivi.icone(e.qui))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(e.estErreur ? Color.rouille : e.qui == "vous" ? Color.espressoProfond : Color.bronze)
                    .frame(width: 28, height: 28)
                    .background(e.qui == "vous" ? AnyShapeStyle(.degradeOr) : AnyShapeStyle(Color.or.opacity(0.16)), in: Circle())
                if !derniere {
                    Rectangle().fill(Color.encrePale.opacity(0.3)).frame(width: 2).frame(minHeight: 18)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(LibelleSuivi.qui(e.qui)).styleTexte(12, relativeTo: .caption, graisse: .semibold).foregroundStyle(Color.bronze)
                    if let le = e.le { Text(DateEndry.heure(le)).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale) }
                }
                Text(e.titre).styleTexte(15, graisse: .medium).foregroundStyle(e.estErreur ? Color.rouille : Color.encre)
                if let d = e.detail, !d.isEmpty {
                    Text(d).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
                }
            }
            .padding(.bottom, derniere ? 0 : Espace.s)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func attente(_ a: ActionSuivie) -> String {
        if app.agents?.etat?.etat?.enService == false { return "L’assistant reprendra à son prochain passage." }
        return a.etat == .transmis ? "En attente du bureau…" : "Le bureau y travaille…"
    }

    private func texteSansEnvoi(_ a: ActionSuivie) -> String {
        switch a.etat {
        case .fait: return a.envoiTiersPrevu && !modele.comptesRendusPC
            ? "Aucun envoi consigné au journal pour l’instant."
            : "Rien n’est parti chez un tiers."
        case .ecarte: return "Rien n’est parti : vous avez écarté cette proposition."
        default: return a.envoiTiersPrevu ? "Envoi prévu à \(a.destinatairesPrevus.joined(separator: ", ")), pas encore consigné." : "Aucun envoi prévu."
        }
    }

    private func demander(_ a: ActionSuivie) async {
        let texte = "Question du patron : où en est « \(a.titre) »\(a.reference.map { " (\($0))" } ?? "") ? Qu’a-t-il été fait, avec quel résultat, qu’est-ce qui a été envoyé et à qui ?"
        guard let r = await app.saisie?.transmettre(demande: texte) else { return }
        if case .refusee(let m) = r {
            app.toast = Toast(m, style: .erreur)
            return
        }
        demandeEnvoyee = true
        modele.enregistrer(saisie: nil, texte: texte, nature: .question, chantierId: a.chantierId)
        app.toast = Toast(r == .transmise ? "Question transmise : le bureau s’en occupe." : "Gardée : partira au retour du réseau.")
    }
}

// MARK: - Tout le suivi

struct JournalSuiviView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    var modele: ModeleSuiviActions
    @State private var filtre = Filtre.tout

    enum Filtre: String, CaseIterable, Identifiable {
        case tout = "Tout", enCours = "En cours", envois = "Envois", erreurs = "Erreurs"
        var id: String { rawValue }
    }

    private var liste: [ActionSuivie] {
        switch filtre {
        case .tout: modele.actions
        case .enCours: modele.actions.filter { !$0.etat.termine }
        case .envois: modele.actions.filter { !$0.envois.isEmpty }
        case .erreurs: modele.actions.filter { $0.etat == .erreur }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filtre", selection: $filtre) {
                        ForEach(Filtre.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                let groupes = Dictionary(grouping: liste) { DateEndry.iso($0.le) }
                ForEach(groupes.keys.sorted(by: >), id: \.self) { jour in
                    Section(DateEndry.longue(DateEndry.lire(jour) ?? Date()).capitalizedPremiere) {
                        ForEach(groupes[jour] ?? []) { action in
                            NavigationLink { FicheSuiviContenu(modele: modele, id: action.id, fermer: { fermer() }) } label: { LigneSuivi(action: action) }
                        }
                    }
                }
                if liste.isEmpty {
                    Text(filtre == .tout ? "Rien encore : vos décisions et saisies apparaîtront ici avec leur résultat." : "Rien dans cette catégorie.")
                        .foregroundStyle(Color.encrePale)
                }
            }
            .scrollContentBackground(.hidden)
            .background(FondAmbiant())
            .refreshable { await modele.rafraichir(saisies: app.saisie?.historique ?? []) }
            .navigationTitle("Suivi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
        }
    }
}

// MARK: - Chantier : activité

struct ActiviteChantier: View {
    @Environment(ModeleApp.self) private var app
    var chantierId: String

    var body: some View {
        if let modele = app.suiviActions {
            let liste = modele.pour(chantier: chantierId)
            if !liste.isEmpty {
                VStack(alignment: .leading, spacing: Espace.s) {
                    Text("Activité").styleTitre(22, relativeTo: .title3).foregroundStyle(Color.encre)
                    VStack(spacing: 0) {
                        ForEach(Array(liste.prefix(6).enumerated()), id: \.element.id) { index, action in
                            if index > 0 { Divider().overlay(Color.encrePale.opacity(0.2)) }
                            NavigationLink { FicheSuiviContenu(modele: modele, id: action.id) } label: {
                                LigneSuivi(action: action).padding(.vertical, Espace.s)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Espace.m)
                    .surfaceCarte(rayon: 20)
                }
            }
        }
    }
}
