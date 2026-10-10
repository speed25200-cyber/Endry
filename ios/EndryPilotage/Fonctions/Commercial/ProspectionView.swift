import SwiftUI
import EndryKit

/// Carte de l'accueil : la prospection a sa place à elle, toujours visible.
struct CarteProspection: View {
    @Environment(ModeleApp.self) private var app
    @State private var ouverte = false
    @State private var nouvelles = 0
    @State private var enCours = false

    var body: some View {
        Button { ouverte = true } label: {
            HStack(spacing: Espace.m) {
                Image(systemName: "scope")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Color.bronze)
                    .frame(width: 52, height: 52)
                    .background(Color.or.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Prospection")
                        .font(Police.serif(25, relativeTo: .title2))
                        .foregroundStyle(Color.encre)
                    Text(sousTitre)
                        .styleTexte(13.5, relativeTo: .footnote)
                        .foregroundStyle(Color.encreDouce)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if nouvelles > 0 {
                    Text(String(nouvelles))
                        .font(Police.serif(26, relativeTo: .title2))
                        .foregroundStyle(Color.encrePapier)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(
                            LinearGradient(colors: [Color.orClair, Color.or], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Circle())
                        .accessibilityLabel(Text("\(nouvelles) nouvelles pistes"))
                } else {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Color.encrePale)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tuileMaison(rayon: 26)
        }
        .buttonStyle(ActionPressee())
        .accessibilityIdentifier("carte-prospection")
        .sheet(isPresented: $ouverte, onDismiss: { Task { await charger() } }) {
            ProspectionView().apercuDocuments()
        }
        .task { await charger() }
    }

    private var sousTitre: String {
        if enCours { return "Recherche en cours : les pistes arrivent dans quelques minutes." }
        switch nouvelles {
        case 0: return "Le bureau cherche de nouveaux chantiers chaque semaine."
        case 1: return "1 nouvelle piste à regarder."
        default: return "\(nouvelles) nouvelles pistes à regarder."
        }
    }

    private func charger() async {
        guard let api = app.session.api, !app.session.estDemo else { return }
        if let carnet = try? await api.carnetPistes() {
            nouvelles = carnet.nouvelles ?? carnet.pistes.filter(\.estNouvelle).count
            enCours = carnet.enCours ?? false
        }
    }
}

/// Le carnet de pistes : ce que le bureau a trouvé cette semaine dans les sources publiques.
/// « Préparer le contact » : le bureau rédige UN message sur mesure, qui arrive en décision. Rien ne part d'ici.
struct ProspectionView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @Environment(\.openURL) private var ouvrirLien
    @State private var carnet: CarnetPistes?
    @State private var filtre = Filtre.nouvelles
    @State private var chargement = true
    @State private var message: String?
    @State private var enAction: String?

    enum Filtre: Hashable { case nouvelles, suivies, ecartees }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.l) {
                    enTete
                    SelecteurSegments(options: [
                        OptionSegment(valeur: Filtre.nouvelles, titre: "Nouvelles"),
                        OptionSegment(valeur: Filtre.suivies, titre: "Suivies"),
                        OptionSegment(valeur: Filtre.ecartees, titre: "Écartées"),
                    ], selection: $filtre)

                    if let message {
                        Label(message, systemImage: "info.circle")
                            .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                            .foregroundStyle(Color.encre)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .tuileMaison(rayon: 20)
                    }

                    if chargement && carnet == nil {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, Espace.xl)
                    } else if visibles.isEmpty {
                        vide
                    } else {
                        VStack(spacing: Espace.m) {
                            ForEach(visibles) { piste in
                                carte(piste)
                            }
                        }
                    }
                }
                .padding(.horizontal, Espace.bord)
                .padding(.top, Espace.s)
                .padding(.bottom, Espace.xl)
                .verrouillerLargeur()
            }
            .scrollIndicators(.hidden)
            .refreshable { await charger() }
            .background(FondMaison(discret: true))
            .navigationTitle("Prospection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { fermer() } } }
        }
        .task { await charger() }
    }

    // MARK: - En-tête

    private var enTete: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            Text("Nouveaux chantiers").etiquetteMaison()
            TitreAdaptatif(texte: titre, grand: 40, lignes: 2)
            Text(carnet?.rythme ?? "Recherche chaque semaine dans les mises à l’enquête, les appels d’offres et les projets annoncés.")
                .styleTexte(14, relativeTo: .subheadline)
                .foregroundStyle(Color.encreDouce)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await chercher() }
            } label: {
                HStack(spacing: Espace.xs) {
                    if carnet?.enCours == true { ProgressView().tint(Color.encre) }
                    Text(carnet?.enCours == true ? "Recherche en cours…" : "Chercher maintenant")
                }
            }
            .buttonStyle(BoutonSecondaire())
            .disabled(carnet?.enCours == true || enAction != nil)
            .accessibilityIdentifier("chercher-pistes")
        }
        .padding(.top, Espace.s)
    }

    private var titre: String {
        let n = carnet?.pistes.filter(\.estNouvelle).count ?? 0
        switch n {
        case 0: return "Aucune nouvelle piste"
        case 1: return "1 nouvelle piste"
        default: return "\(n) nouvelles pistes"
        }
    }

    private var vide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(filtre == .nouvelles ? "Rien de nouveau pour l’instant." : "Rien ici.")
                .styleTexte(16, graisse: .semibold)
                .foregroundStyle(Color.encre)
            Text("Chaque piste vient d’une page publique vérifiée. Le bureau n’envoie rien : vous choisissez, il prépare, vous validez.")
                .styleTexte(14, relativeTo: .subheadline)
                .foregroundStyle(Color.encreDouce)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tuileMaison(rayon: 24)
    }

    // MARK: - Une piste

    private func carte(_ piste: Piste) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(piste.typeLibelle ?? "Piste").etiquetteMaison()
                Spacer(minLength: Espace.s)
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { rang in
                        Circle()
                            .fill(rang < (piste.score ?? 3) ? Color.bronze : Color.filet)
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityLabel(Text("Intérêt \(piste.score ?? 3) sur 5"))
            }

            Text(piste.titre)
                .font(Police.serif(23, relativeTo: .title3))
                .foregroundStyle(Color.encre)
                .fixedSize(horizontal: false, vertical: true)

            if !piste.endroit.isEmpty || piste.echeance?.isEmpty == false {
                Text([piste.endroit, piste.echeance ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Police.mono(11.5))
                    .foregroundStyle(Color.encreDouce)
            }

            if let resume = piste.resume, !resume.isEmpty {
                Text(resume)
                    .styleTexte(14.5)
                    .foregroundStyle(Color.encre)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let pourquoi = piste.pourquoi, !pourquoi.isEmpty {
                Text(pourquoi)
                    .styleTexte(13.5, relativeTo: .footnote)
                    .foregroundStyle(Color.encreDouce)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let acteurs = [Self.acteur("Maître d’ouvrage", piste.maitreOuvrage), Self.acteur("Architecte", piste.architecte),
                           Self.acteur("Contact", piste.contact)].compactMap { $0 }
            if !acteurs.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(acteurs, id: \.self) { ligne in
                        Text(ligne).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
                    }
                }
            }

            if let adresse = piste.sourceUrl, let url = URL(string: adresse) {
                Button { ouvrirLien(url) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "link").font(.system(size: 11, weight: .semibold))
                        Text(piste.source?.isEmpty == false ? (piste.source ?? "Source") : "Voir la source")
                            .styleTexte(13, relativeTo: .footnote, graisse: .medium)
                    }
                    .foregroundStyle(Color.bronze)
                }
                .buttonStyle(.plain)
            }

            actions(piste)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tuileMaison(rayon: 26)
        .opacity(enAction == piste.id ? 0.6 : 1)
    }

    @ViewBuilder private func actions(_ piste: Piste) -> some View {
        if piste.enPreparation {
            Label("Message en préparation : il arrivera dans vos décisions.", systemImage: "hourglass")
                .styleTexte(13.5, relativeTo: .footnote, graisse: .medium)
                .foregroundStyle(Color.encreDouce)
        } else if piste.estEcartee {
            Button("Remettre dans les nouvelles") { Task { await agir(piste, "garder") } }
                .buttonStyle(BoutonSecondaire())
                .disabled(enAction != nil)
        } else if piste.estNouvelle {
            HStack(spacing: Espace.s) {
                Button("Préparer le contact") { Task { await agir(piste, "contacter") } }
                    .buttonStyle(BoutonPrincipal())
                Button("Écarter") { Task { await agir(piste, "ecarter") } }
                    .buttonStyle(BoutonSecondaire())
            }
            .disabled(enAction != nil)
        }
    }

    private static func acteur(_ role: String, _ nom: String?) -> String? {
        guard let nom, !nom.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return "\(role) : \(nom)"
    }

    // MARK: - Données

    private var visibles: [Piste] {
        let toutes = carnet?.pistes ?? []
        switch filtre {
        case .nouvelles: return toutes.filter(\.estNouvelle)
        case .ecartees: return toutes.filter(\.estEcartee)
        case .suivies: return toutes.filter { !$0.estNouvelle && !$0.estEcartee }
        }
    }

    private func charger() async {
        guard let api = app.session.api else { return }
        if let recu = try? await api.carnetPistes() { carnet = recu }
        chargement = false
    }

    private func chercher() async {
        guard let api = app.session.api else { return }
        enAction = "recherche"
        do throws(ErreurAPI) {
            message = try await api.lancerRecherchePistes().message
        } catch {
            message = error.message
        }
        enAction = nil
        await charger()
    }

    private func agir(_ piste: Piste, _ action: String) async {
        guard let api = app.session.api else { return }
        enAction = piste.id
        do throws(ErreurAPI) {
            message = try await api.agirSurPiste(piste.id, action: action).message
        } catch {
            message = error.message
        }
        enAction = nil
        await charger()
    }
}
