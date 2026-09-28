import EndryKit
import SwiftUI

/// Fiche client calculée à partir des chantiers, factures ouvertes et offres (aucune donnée inventée).
struct FicheClient: Identifiable, Hashable {
    var nom: String
    var lieux: [String]
    var chantiers: Int
    var aEncaisser: Double
    var retardMax: Int
    var offres: Double
    var decisionEnAttente: Bool

    var id: String { nom }
    var poids: Double { aEncaisser + offres }
}

/// Fiche fournisseur : factures à payer et achats à refacturer.
struct FicheFournisseur: Identifiable, Hashable {
    var nom: String
    var aPayer: Double
    var prochaineEcheance: Int?
    var aRefacturer: Double
    /// Numéro fourni par le PC, sinon celui enregistré sur cet iPhone.
    var telephone: String? = nil

    var id: String { nom }
}

enum Annuaire {
    static func clients(chantiers: [Dossier], argent: Argent?) -> [FicheClient] {
        var fiches: [String: FicheClient] = [:]
        func fiche(_ nom: String) -> FicheClient {
            fiches[nom] ?? FicheClient(nom: nom, lieux: [], chantiers: 0, aEncaisser: 0, retardMax: 0, offres: 0, decisionEnAttente: false)
        }
        for dossier in chantiers where !dossier.client.isEmpty {
            var f = fiche(dossier.client)
            f.chantiers += 1
            if let lieu = dossier.lieu, !f.lieux.contains(lieu) { f.lieux.append(lieu) }
            f.decisionEnAttente = f.decisionEnAttente || dossier.decisionEnAttente
            fiches[dossier.client] = f
        }
        for facture in argent?.encaisser.factures ?? [] {
            var f = fiche(facture.client)
            f.aEncaisser += facture.montant
            f.retardMax = max(f.retardMax, facture.retardJours)
            fiches[facture.client] = f
        }
        for offre in argent?.offres.offres ?? [] {
            var f = fiche(offre.client)
            f.offres += offre.montant
            fiches[offre.client] = f
        }
        return fiches.values.sorted { ($0.poids, $0.chantiers) > ($1.poids, $1.chantiers) }
    }

    static func fournisseurs(argent: Argent?) -> [FicheFournisseur] {
        var fiches: [String: FicheFournisseur] = [:]
        for facture in argent?.payer.factures ?? [] {
            var f = fiches[facture.fournisseur] ?? FicheFournisseur(nom: facture.fournisseur, aPayer: 0, prochaineEcheance: nil, aRefacturer: 0)
            f.aPayer += facture.montant
            if f.telephone == nil { f.telephone = facture.telephone }
            if let j = facture.joursRestants { f.prochaineEcheance = min(f.prochaineEcheance ?? j, j) }
            fiches[facture.fournisseur] = f
        }
        for achat in argent?.aRefacturer.achats ?? [] {
            guard let nom = achat.fournisseur else { continue }
            var f = fiches[nom] ?? FicheFournisseur(nom: nom, aPayer: 0, prochaineEcheance: nil, aRefacturer: 0)
            f.aRefacturer += achat.montant
            fiches[nom] = f
        }
        for (nom, fiche) in fiches where fiche.telephone == nil {
            fiches[nom]?.telephone = CarnetTelephones.numero(de: nom)
        }
        return fiches.values.sorted { $0.aPayer + $0.aRefacturer > $1.aPayer + $1.aRefacturer }
    }
}

/// Numéros de fournisseurs saisis par le patron, gardés sur cet iPhone seulement.
enum CarnetTelephones {
    private static let cle = "carnet-telephones-fournisseurs"

    static func numero(de fournisseur: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: cle) as? [String: String])?[fournisseur]
    }

    static func enregistrer(_ numero: String, pour fournisseur: String) {
        var carnet = (UserDefaults.standard.dictionary(forKey: cle) as? [String: String]) ?? [:]
        let propre = numero.trimmingCharacters(in: .whitespacesAndNewlines)
        carnet[fournisseur] = propre.isEmpty ? nil : propre
        UserDefaults.standard.set(carnet, forKey: cle)
    }

    /// Lien `tel:` (chiffres et « + » seulement).
    static func lien(_ numero: String) -> URL? {
        let chiffres = numero.filter { $0.isNumber || $0 == "+" }
        return chiffres.count >= 6 ? URL(string: "tel:\(chiffres)") : nil
    }
}

/// Espace Entreprise : clients, fournisseurs, activité, compte et sécurité.
struct EntrepriseView: View {
    @Environment(ModeleApp.self) private var app
    @State private var visible = false
    @State private var tousLesClients = false
    @State private var appareilsOuverts = false
    @AppStorage(ModeDevantClient.cle) private var devantClient = false

    private var clients: [FicheClient] {
        Annuaire.clients(chantiers: app.chantiers?.tous ?? [], argent: app.argent?.argent)
    }

    private var fournisseurs: [FicheFournisseur] { Annuaire.fournisseurs(argent: app.argent?.argent) }

    @Environment(\.horizontalSizeClass) private var classe

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.xl) {
                    entete
                        .apparitionEnCascade(index: 0, visible: visible)
                    indicateurs
                        .apparitionEnCascade(index: 1, visible: visible)
                    BasculeModeClient()
                        .apparitionEnCascade(index: 1, visible: visible)
                    // iPad : le bureau, l'équipe et l'assistant à gauche ; clients, fournisseurs et compte à droite.
                    Colonnes(espacement: Espace.xl) {
                        if let agents = app.agents {
                            SectionBureau(modele: agents)
                                .apparitionEnCascade(index: 2, visible: visible)
                        }
                        if let entretiens = app.entretiens {
                            CarteEntretiens(modele: entretiens)
                                .apparitionEnCascade(index: 2, visible: visible)
                        }
                        CarteEquipe()
                            .apparitionEnCascade(index: 2, visible: visible)
                        if let pilotage = app.pilotage, pilotage.disponible {
                            VStack(alignment: .leading, spacing: Espace.s) {
                                EnTeteSection(titre: "Claude, sur le PC")
                                CarteAssistantBureau(pilotage: pilotage)
                            }
                            .apparitionEnCascade(index: 2, visible: visible)
                        }
                    } droite: {
                        sectionClients
                            .apparitionEnCascade(index: 2, visible: visible)
                        if devantClient {
                            BlocMasqueClient(titre: "Fournisseurs")
                                .apparitionEnCascade(index: 3, visible: visible)
                        } else {
                            sectionFournisseurs
                                .apparitionEnCascade(index: 3, visible: visible)
                        }
                        sectionCompte
                            .apparitionEnCascade(index: 4, visible: visible)
                    }
                }
                .largeurLisible(Adaptatif.ecran)
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .tirerPourActualiser {
                await app.argent?.charger()
                await app.chantiers?.charger()
            }
            .background(FondAmbiant())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $appareilsOuverts) { AppareilsView() }
        }
        .toast(Binding(get: { app.pilotage?.toast }, set: { nouveau in if let p = app.pilotage { p.toast = nouveau } }))
        .task {
            await app.pilotage?.charger()
            if app.argent?.etat == .initial { await app.argent?.charger() }
            if app.chantiers?.etat == .initial { await app.chantiers?.charger() }
            visible = true
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            Text("Entreprise").styleSurtitre()
            HStack(alignment: .center, spacing: Espace.m) {
                LogoEndry(taille: 54)
                    .padding(8)
                    .background(MatiereEspresso(rayon: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.session.entreprise)
                        .styleTitre(28, relativeTo: .largeTitle)
                        .foregroundStyle(Color.encre)
                    Text("Sanitaire · Chauffage · Ventilation")
                        .styleTexte(13, relativeTo: .footnote)
                        .foregroundStyle(Color.encreDouce)
                }
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(app.session.connexionPerdue ? Color.rouille : Color.vertControle)
                    .frame(width: 7, height: 7)
                    .shadow(color: app.session.connexionPerdue ? Color.rouille : Color.vertControle, radius: 4)
                Text(etatConnexion)
                    .styleTexte(12, relativeTo: .caption, graisse: .medium)
                    .foregroundStyle(Color.encreDouce)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.surfaceCreuse, in: Capsule())
        }
        .padding(.top, Espace.m)
    }

    private var etatConnexion: String {
        if app.session.estDemo { return "Mode démo · données fictives" }
        if app.session.connexionPerdue { return "Connexion perdue" }
        return "Connecté · \(app.session.hoteAffiche ?? "serveur privé")"
    }

    // MARK: - Indicateurs

    private var indicateurs: some View {
        let argent = app.argent?.argent
        let actifs = (app.chantiers?.tous ?? []).filter { (2...4).contains($0.etapeIndex) }.count
        // Deux tuiles de front sur iPhone, quatre sur iPad.
        let colonnes = Array(repeating: GridItem(.flexible(), spacing: Espace.s), count: classe == .regular ? 4 : 2)
        return LazyVGrid(columns: colonnes, spacing: Espace.s) {
            TuileIndicateur(titre: "Chantiers en cours", valeur: "\(actifs)", detail: "acceptés → réalisés", icone: "hammer.fill")
            TuileIndicateur(titre: "Clients suivis", valeur: "\(clients.count)", detail: "chantiers, factures, offres", icone: "person.2.fill")
            TuileIndicateur(titre: "Secrétariat", valeur: argent?.heuresSecretariat.map { FormatSuisse.heures($0.heures) } ?? "—",
                            detail: argent?.heuresSecretariat?.mois ?? "ce mois", icone: "clock.fill")
            TuileIndicateur(titre: "Versements à identifier", valeur: "\(argent?.versementsNonIdentifies.count ?? 0)",
                            detail: "à rapprocher", icone: "questionmark.circle.fill",
                            alerte: (argent?.versementsNonIdentifies.count ?? 0) > 0)
        }
    }

    // MARK: - Clients

    private var sectionClients: some View {
        let liste = clients
        let affiches = tousLesClients ? liste : Array(liste.prefix(6))
        return VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: "Clients", detail: "\(liste.count)",
                          action: liste.count > 6 ? { withAnimation(.endry) { tousLesClients.toggle() } } : nil,
                          libelleAction: tousLesClients ? "Réduire" : "Tout voir")
            if liste.isEmpty {
                Squelette(hauteur: 180, rayon: Espace.rayon)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(affiches.enumerated()), id: \.element.id) { index, client in
                        LigneClient(client: client)
                        if index < affiches.count - 1 {
                            Rectangle().fill(Color.filet).frame(height: 0.5).padding(.leading, 62)
                        }
                    }
                }
                .padding(.horizontal, Espace.m)
                .padding(.vertical, Espace.xxs)
                .surfaceCarte(rayon: 24)
            }
        }
    }

    // MARK: - Fournisseurs

    private var sectionFournisseurs: some View {
        let liste = fournisseurs
        return VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: "Fournisseurs", detail: "\(liste.count)")
            if liste.isEmpty {
                Text("Aucune facture fournisseur ouverte.").styleTexte(14, relativeTo: .subheadline).foregroundStyle(Color.encrePale)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Espace.s) {
                        ForEach(liste) { f in
                            CarteFournisseur(fiche: f)
                                .scrollTransition(.interactive, axis: .horizontal) { contenu, phase in
                                    contenu.scaleEffect(phase.isIdentity ? 1 : 0.94).opacity(phase.isIdentity ? 1 : 0.6)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Compte & sécurité

    private var sectionCompte: some View {
        @Bindable var verrou = app.verrou
        return VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: "Compte & sécurité")
            VStack(spacing: 0) {
                LigneReglage(icone: "server.rack", titre: "Serveur", detail: app.session.hoteAffiche ?? "—") {
                    app.connexionPresentee = true
                }
                separateur
                HStack(spacing: Espace.m) {
                    IconeReglage(nom: "faceid")
                    Text("Verrouiller avec \(app.verrou.nomMethode)")
                        .styleTexte(15, relativeTo: .body, graisse: .medium)
                        .foregroundStyle(Color.encre)
                    Spacer()
                    Toggle("", isOn: $verrou.actif).labelsHidden().tint(Color.or)
                }
                .padding(.vertical, Espace.s)
                if !app.session.estDemo {
                    separateur
                    LigneReglage(icone: "iphone.gen3", titre: "Appareils connectés", detail: nil) {
                        appareilsOuverts = true
                    }
                    .accessibilityIdentifier("appareils-connectes")
                }
                separateur
                LigneReglage(icone: "link.badge.plus", titre: "Coller un nouveau lien", detail: nil) {
                    app.connexionPresentee = true
                }
                separateur
                LigneReglage(icone: "gearshape", titre: "Tous les réglages", detail: nil) {
                    app.reglagesPresentes = true
                }
            }
            .padding(.horizontal, Espace.m)
            .surfaceCarte(rayon: 24)
            Text("Aucun outil de suivi. Le jeton d’accès reste dans le trousseau de cet iPhone.")
                .styleTexte(11, relativeTo: .caption2)
                .foregroundStyle(Color.encrePale)
                .padding(.horizontal, Espace.xxs)
        }
    }

    private var separateur: some View {
        Rectangle().fill(Color.filet).frame(height: 0.5).padding(.leading, 48)
    }
}

// MARK: - Composants de l'espace Entreprise

struct TuileIndicateur: View {
    var titre: String
    var valeur: String
    var detail: String
    var icone: String
    var alerte = false

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            Image(systemName: icone)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(alerte ? AnyShapeStyle(Color.ambre) : AnyShapeStyle(.degradeOr))
                .frame(width: 30, height: 30)
                .background(Color.surfaceCreuse, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(valeur)
                .styleTitre(26, relativeTo: .title2)
                .foregroundStyle(Color.encre)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 1) {
                Text(titre).styleTexte(12, relativeTo: .caption, graisse: .semibold).foregroundStyle(Color.encreDouce)
                Text(detail).styleTexte(11, relativeTo: .caption2).foregroundStyle(Color.encrePale).lineLimit(1)
            }
        }
        .padding(Espace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte(rayon: 22)
        .accessibilityElement(children: .combine)
    }
}

struct LigneClient: View {
    var client: FicheClient

    private var initiales: String {
        let mots = client.nom
            .replacingOccurrences(of: "M. et Mme ", with: "")
            .replacingOccurrences(of: "Famille ", with: "")
            .replacingOccurrences(of: "Mme ", with: "")
            .replacingOccurrences(of: "M. ", with: "")
            .split(separator: " ")
        return mots.prefix(2).compactMap(\.first).map { String($0) }.joined().uppercased()
    }

    var body: some View {
        HStack(spacing: Espace.s) {
            Text(initiales)
                .font(Police.titre(15, relativeTo: .subheadline))
                .foregroundStyle(.degradeOr)
                .frame(width: 42, height: 42)
                .background(Color.surfaceCreuse, in: Circle())
                .overlay(Circle().strokeBorder(Color.or.opacity(0.35), lineWidth: 0.7))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(client.nom).styleTexte(15, relativeTo: .subheadline, graisse: .semibold).foregroundStyle(Color.encre).lineLimit(1)
                    if client.decisionEnAttente {
                        Circle().fill(Color.or).frame(width: 6, height: 6)
                            .accessibilityLabel(Text("Décision en attente"))
                    }
                }
                Text(sousTitre).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale).lineLimit(1)
            }
            Spacer(minLength: Espace.xs)
            VStack(alignment: .trailing, spacing: 3) {
                if client.aEncaisser > 0 {
                    MontantView(montant: client.aEncaisser, taille: 14, afficherCentimes: false, style: .subheadline)
                    Text(client.retardMax > 0 ? "\(client.retardMax) j de retard" : "à échoir")
                        .styleTexte(10, relativeTo: .caption2, graisse: .semibold)
                        .foregroundStyle(client.retardMax > 30 ? Color.rouille : client.retardMax > 0 ? Color.ambre : Color.vertControle)
                } else if client.offres > 0 {
                    MontantView(montant: client.offres, taille: 14, couleur: .encreDouce, afficherCentimes: false, style: .subheadline)
                    Text("offre en attente").styleTexte(10, relativeTo: .caption2, graisse: .semibold).foregroundStyle(Color.bronze)
                }
            }
        }
        .padding(.vertical, Espace.s)
        .accessibilityElement(children: .combine)
    }

    private var sousTitre: String {
        var morceaux: [String] = []
        if let lieu = client.lieux.first { morceaux.append(lieu) }
        if client.chantiers > 0 { morceaux.append("\(client.chantiers) chantier\(client.chantiers > 1 ? "s" : "")") }
        return morceaux.isEmpty ? "Client" : morceaux.joined(separator: " · ")
    }
}

struct CarteFournisseur: View {
    var fiche: FicheFournisseur
    @State private var saisieNumero = false
    @State private var numero = ""
    @State private var numeroLocal: String?

    private var telephone: String? { numeroLocal ?? fiche.telephone }

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.degradeOr)
                Spacer()
                if let telephone, let lien = CarnetTelephones.lien(telephone) {
                    Link(destination: lien) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.espressoProfond)
                            .frame(width: 36, height: 36)
                            .background(.degradeOr, in: Circle())
                    }
                    .accessibilityLabel(Text("Appeler \(fiche.nom)"))
                } else {
                    Button {
                        numero = ""
                        saisieNumero = true
                    } label: {
                        Image(systemName: "phone.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.bronze)
                            .frame(width: 36, height: 36)
                            .background(Color.surfaceCreuse, in: Circle())
                    }
                    .accessibilityLabel(Text("Ajouter le numéro de \(fiche.nom)"))
                }
            }
            Text(fiche.nom)
                .styleTexte(14, relativeTo: .subheadline, graisse: .semibold)
                .foregroundStyle(Color.encre)
                .lineLimit(2, reservesSpace: true)
            Spacer(minLength: 0)
            if fiche.aPayer > 0 {
                MontantView(montant: fiche.aPayer, taille: 18, afficherCentimes: false, style: .headline)
                if let j = fiche.prochaineEcheance {
                    Text(j <= 0 ? "échéance dépassée" : "échéance dans \(j) j")
                        .styleTexte(11, relativeTo: .caption2, graisse: .medium)
                        .foregroundStyle(j <= 3 ? Color.rouille : Color.encrePale)
                }
            }
            if fiche.aRefacturer > 0 {
                Text("\(FormatSuisse.chfArrondi(fiche.aRefacturer)) à refacturer")
                    .styleTexte(11, relativeTo: .caption2, graisse: .medium)
                    .foregroundStyle(Color.bronze)
            }
        }
        .padding(Espace.m)
        .frame(width: 178, height: 176, alignment: .topLeading)
        .surfaceCarte(rayon: 22)
        .accessibilityElement(children: .contain)
        .alert("Numéro de \(fiche.nom)", isPresented: $saisieNumero) {
            TextField("+41 21 000 00 00", text: $numero)
                .keyboardType(.phonePad)
            Button("Enregistrer") {
                CarnetTelephones.enregistrer(numero, pour: fiche.nom)
                numeroLocal = CarnetTelephones.numero(de: fiche.nom)
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Gardé sur cet iPhone seulement.")
        }
    }
}

struct IconeReglage: View {
    var nom: String

    var body: some View {
        Image(systemName: nom)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.degradeOr)
            .frame(width: 32, height: 32)
            .background(Color.surfaceCreuse, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct LigneReglage: View {
    var icone: String
    var titre: String
    var detail: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Espace.m) {
                IconeReglage(nom: icone)
                Text(titre).styleTexte(15, relativeTo: .body, graisse: .medium).foregroundStyle(Color.encre)
                Spacer()
                if let detail {
                    Text(detail).font(Police.reference(11)).foregroundStyle(Color.encrePale).lineLimit(1)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.encrePale)
            }
            .padding(.vertical, Espace.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Entreprise — démo") {
    let app = ModeleApp()
    app.activerDemo()
    return EntrepriseView()
        .environment(app)
        .preferredColorScheme(.dark)
}
