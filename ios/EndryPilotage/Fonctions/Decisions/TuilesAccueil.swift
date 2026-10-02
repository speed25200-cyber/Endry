import EndryKit
import SwiftUI

// MARK: - En-tête

/// En-tête Maison Endry : monogramme, « ENDRY SA » en Cinzel et la devise ; à droite, des boutons ronds de verre
/// (rechercher, écrire au bureau, réglages).
struct EnTeteMaison: View {
    @Environment(ModeleApp.self) private var app
    var initiale: String?

    var body: some View {
        HStack(spacing: Espace.xs) {
            Image("MonogrammeEndry")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("ENDRY SA")
                    .font(Police.etiquette(12.5))
                    .tracking(3)
                    .foregroundStyle(Color.bronze)
                Text("SANITAIRE · CHAUFFAGE · VENTILATION")
                    .font(Police.etiquette(7))
                    .tracking(1.4)
                    .foregroundStyle(Color.encreDouce)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Endry SA, sanitaire, chauffage, ventilation"))
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Espace.xs)
            BoutonRondVerre(libelle: "Rechercher", identifiant: "bouton-recherche") {
                app.recherchePresentee = true
            } contenu: {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .regular))
            }
            if app.conversation != nil {
                BoutonRondVerre(libelle: "Écrire au bureau", identifiant: "ecrire-bureau") {
                    app.ouvrirConversation()
                } contenu: {
                    Image(systemName: "text.bubble").font(.system(size: 15, weight: .regular))
                }
            }
            BoutonRondVerre(libelle: app.session.estDemo ? "Profil et réglages, mode démo" : "Profil et réglages",
                            identifiant: "bouton-reglages") {
                app.reglagesPresentes = true
            } contenu: {
                if let initiale {
                    Text(initiale).font(Police.serif(19, relativeTo: .headline))
                } else {
                    Image(systemName: "person").font(.system(size: 15, weight: .regular))
                }
            }
        }
    }
}

// MARK: - Finances et chantiers

/// Tuile Finances : à encaisser (avec la part non échue en vert), à payer sous 7 jours.
struct TuileFinances: View {
    var accueil: Accueil
    var ouvrir: () -> Void
    @AppStorage(ModeDevantClient.cle) private var devantClient = false

    var body: some View {
        Button(action: ouvrir) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Finances").etiquetteMaison()
                Spacer(minLength: Espace.s)
                ligne("À encaisser", accueil.encaisser.total)
                BarreFine(part: partNonEchue, couleur: .sauge)
                    .padding(.top, 4)
                    .padding(.bottom, 7)
                if devantClient {
                    ligne("Offres", accueil.offres.total)
                } else {
                    ligne("À payer · 7 j", accueil.payer.totalSemaine)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .tuileMaison(rayon: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActionPressee())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Ouvre l’espace Finances"))
        .accessibilityIdentifier("tuile-finances")
    }

    /// Part de l'argent à encaisser qui n'est pas encore échue.
    private var partNonEchue: Double {
        let total = accueil.encaisser.total
        guard total > 0 else { return 0 }
        return accueil.encaisser.anciennete.aEchoir / total
    }

    private func ligne(_ titre: String, _ montant: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titre)
                .styleTexte(13, relativeTo: .caption)
                .foregroundStyle(Color.encreDouce)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(FormatSuisse.francs(montant))
                .font(Police.serif(23, relativeTo: .headline))
                .monospacedDigit()
                .foregroundStyle(Color.encre)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Tuile Chantiers : numéro de semaine et deux chantiers avec leur étape (n / 7).
struct TuileChantiers: View {
    var semaine: [Semaine]
    /// Chantiers en cours (acceptés → réalisés) : montrés quand la semaine n'a rien de planifié.
    var enCours: [Dossier] = []
    var ouvrir: () -> Void

    var body: some View {
        Button(action: ouvrir) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Chantiers").etiquetteMaison()
                    Spacer(minLength: 4)
                    Text("Sem. \(Self.numeroSemaine())")
                        .font(Police.mono(11.5))
                        .foregroundStyle(Color.encreDouce)
                }
                Spacer(minLength: Espace.s)
                if !semaine.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(semaine.prefix(2)) { chantier in
                            ligne(titre: chantier.titre, client: chantier.client,
                                  etape: chantier.etape.flatMap(EtapeChantier.init(rawValue:)))
                        }
                    }
                } else if !enCours.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(enCours.prefix(2)) { dossier in
                            ligne(titre: dossier.titre, client: dossier.client,
                                  etape: EtapeChantier.depuisIndex(dossier.etapeIndex))
                        }
                    }
                } else {
                    Text("Rien de planifié")
                        .styleTexte(13, relativeTo: .caption)
                        .foregroundStyle(Color.encreDouce)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .tuileMaison(rayon: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActionPressee())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Ouvre le planning"))
        .accessibilityIdentifier("tuile-chantiers")
    }

    private func ligne(titre: String, client: String?, etape: EtapeChantier?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.nomCourt(titre: titre, client: client))
                    .styleTexte(13, relativeTo: .caption)
                    .foregroundStyle(Color.encre)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let etape {
                    Text("\(etape.index + 1)/\(EtapeChantier.allCases.count)")
                        .font(Police.mono(11.5))
                        .foregroundStyle(Color.encreDouce)
                }
            }
            BarreFine(part: etape.map { Double($0.index + 1) / Double(EtapeChantier.allCases.count) } ?? 0)
        }
    }

    /// Le client s'il est connu (« Villa Morel », « Kaveh Gordji »), sinon le début du titre.
    static func nomCourt(titre: String, client: String?) -> String {
        if let client, !client.isEmpty { return client }
        return FriseSemaineView.titreCourt(titre)
    }

    static func numeroSemaine(_ date: Date = Date()) -> Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: date)
    }
}

extension FormatSuisse {
    /// `49673.4` → `49’673` : montant arrondi au franc, sans devise (grands chiffres des tuiles).
    static func francs(_ montant: Double) -> String {
        let p = parties(montant.rounded())
        return "\(p.signe)\(p.francs)"
    }
}
