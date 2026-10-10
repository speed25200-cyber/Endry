import EndryKit
import SwiftUI

/// Poste de pilotage — « Pouls de l'entreprise » : la trésorerie des factures ouvertes (à encaisser face à
/// à payer, solde net), puis quatre instruments : en retard, à décider, chantiers en cours, offres ouvertes.
/// Chaque chiffre mène à son espace. Devant le client : rien de ce qui est à payer n'apparaît.
struct PoulsEntreprise: View {
    @Environment(ModeleApp.self) private var app
    @AppStorage(ModeDevantClient.cle) private var devantClient = false
    var accueil: Accueil
    var cartes: [Carte]
    var chantiersEnCours: [Dossier]
    var majLe: Date?
    var ouvrirDecisions: () -> Void

    var body: some View {
        let chiffres = Chiffres(accueil: accueil, cartes: cartes, enCours: chantiersEnCours)
        VStack(alignment: .leading, spacing: 10) {
            TitreSection(titre: "Pouls de l’entreprise", repere: repereMaj)
            tresorerie(chiffres)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                Indicateur(symbole: "exclamationmark.triangle", titre: "En retard",
                           valeur: "\(chiffres.retards)", unite: chiffres.retards == 1 ? "facture" : "factures",
                           detail: chiffres.retards == 0 ? "Tout est dans les délais"
                                                         : "CHF \(FormatSuisse.francs(chiffres.montantRetard)) · \(chiffres.plusVieux) j",
                           ton: chiffres.retards == 0 ? .sain : .alerte,
                           identifiant: "instrument-retards") {
                    ouvrir(.encaisser)
                }
                Indicateur(symbole: "checkmark.seal", titre: "À décider",
                           valeur: "\(cartes.count)",
                           detail: chiffres.envois > 0 ? "dont \(chiffres.envois) \(chiffres.envois == 1 ? "envoi" : "envois")"
                                                       : cartes.isEmpty ? "Rien n’attend" : "à valider d’un geste",
                           identifiant: "instrument-decisions", action: ouvrirDecisions)
                Indicateur(symbole: "hammer", titre: "Chantiers",
                           valeur: "\(chantiersEnCours.count)", unite: "en cours",
                           detail: "\(accueil.chantiers7Jours.count) cette semaine",
                           identifiant: "instrument-chantiers", action: ouvrirPlanning) {
                    SegmentsAvancement(allumes: chiffres.avancementMoyen, total: EtapeChantier.allCases.count)
                        .padding(.top, 8)
                }
                Indicateur(symbole: "doc.text", titre: "Offres",
                           valeur: "\(accueil.offres.offres.count)", unite: accueil.offres.offres.count == 1 ? "ouverte" : "ouvertes",
                           detail: "CHF \(FormatSuisse.francs(accueil.offres.total))",
                           identifiant: "instrument-offres") {
                    ouvrir(.offres)
                }
            }
        }
    }

    /// « à l'instant », « maj 10:42 ».
    private var repereMaj: String? {
        guard let majLe else { return nil }
        if Date().timeIntervalSince(majLe) < 120 { return "à l’instant" }
        return "maj " + LigneJournal.heure(majLe)
    }

    // MARK: - Trésorerie

    private func tresorerie(_ c: Chiffres) -> some View {
        Button { ouvrir(.encaisser) } label: {
            VStack(alignment: .leading, spacing: 0) {
                LibelleInstrument(symbole: "banknote", titre: devantClient ? "À encaisser · factures ouvertes" : "Trésorerie · factures ouvertes",
                                  ton: devantClient || c.net >= 0 ? .sain : .alerte) {
                    if !devantClient {
                        Text(c.net >= 0 ? "Solde positif" : "Solde négatif")
                            .font(.system(size: UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 11.5), weight: .semibold))
                            .foregroundStyle(c.net >= 0 ? Color.sauge : Color.rouille)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((c.net >= 0 ? Color.sauge : Color.rouille).opacity(0.13), in: Capsule())
                    }
                }
                ChiffreInstrument(valeur: FormatSuisse.francs(devantClient ? accueil.encaisser.total : c.net), prefixe: "CHF", taille: 42)
                    .padding(.top, 12)
                if devantClient {
                    // Ancienneté de ce qui est dû : non échu, puis de plus en plus en retard.
                    let a = accueil.encaisser.anciennete
                    BarreParts(parts: [(a.aEchoir, .sauge), (a.jours0a30, .signal), (a.jours31a60, .etiquette), (a.plus60, .rouille)])
                        .padding(.top, 14)
                    legende(("Non échu", a.aEchoir), ("Échu", a.jours0a30 + a.jours31a60 + a.plus60))
                } else {
                    BarreParts(parts: [(accueil.encaisser.total, .sauge), (accueil.payer.total, .rouille)])
                        .padding(.top, 14)
                    legende(("À encaisser", accueil.encaisser.total), ("À payer", accueil.payer.total))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tuileMaison(rayon: 24)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(ActionPressee())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Ouvre Finances"))
        .accessibilityIdentifier("instrument-tresorerie")
    }

    private func legende(_ gauche: (String, Double), _ droite: (String, Double)) -> some View {
        HStack(alignment: .top) {
            colonne(gauche.0, gauche.1, alignement: .leading)
            Spacer(minLength: 8)
            colonne(droite.0, droite.1, alignement: .trailing)
        }
        .padding(.top, 10)
    }

    private func colonne(_ titre: String, _ montant: Double, alignement: HorizontalAlignment) -> some View {
        VStack(alignment: alignement, spacing: 2) {
            Text(titre)
                .font(.system(size: UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 12.5)))
                .foregroundStyle(Color.encreDouce)
            Text(FormatSuisse.francs(montant))
                .font(Police.serif(18, relativeTo: .headline))
                .foregroundStyle(Color.encre)
        }
    }

    // MARK: - Navigation

    private func ouvrir(_ vue: ArgentView.VueFinances) {
        app.vueFinances = vue
        app.onglet = .finances
    }

    private func ouvrirPlanning() {
        app.vueChantiers = .pipeline
        app.onglet = .chantiers
    }

    /// Chiffres calculés une fois par rendu, à partir de ce que le PC a déjà envoyé (rien d'inventé).
    struct Chiffres {
        var retards = 0
        var montantRetard: Double = 0
        var plusVieux = 0
        var envois = 0
        var avancementMoyen = 0
        var net: Double = 0

        init(accueil: Accueil, cartes: [Carte], enCours: [Dossier]) {
            for facture in accueil.encaisser.factures where facture.retardJours > 0 {
                retards += 1
                montantRetard += facture.montant
                plusVieux = max(plusVieux, facture.retardJours)
            }
            envois = cartes.filter(\.partChezUnTiers).count
            if !enCours.isEmpty {
                let somme = enCours.reduce(0) { $0 + $1.etapeIndex + 1 }
                avancementMoyen = Int((Double(somme) / Double(enCours.count)).rounded())
            }
            net = accueil.encaisser.total - accueil.payer.total
        }
    }
}
