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
            ConteneurVerre {
                HStack(spacing: Espace.xs) {
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
    }
}

// MARK: - Montants

extension FormatSuisse {
    /// `49673.4` → `49’673` : montant arrondi au franc, sans devise (grands chiffres des tuiles).
    static func francs(_ montant: Double) -> String {
        let p = parties(montant.rounded())
        return "\(p.signe)\(p.francs)"
    }
}
