import EndryKit
import SwiftUI

/// Fiche complète d'une décision, ouverte en touchant sa carte :
/// photo d'ambiance, texte intégral, destinataires, contrôle qualité, pièces jointes, chantier lié et tous les gestes.
struct FicheDecision: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    var carte: Carte
    var modele: ModeleDecisions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    PhotoVivante(nom: PhotosMarque.pour(genre: carte.genre))
                        .frame(height: 210)
                        .overlay(VoilePhoto(haut: 0.35, bas: 1))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Proposition de l’assistant")
                            .font(Police.etiquette(Echelle.micro))
                            .textCase(.uppercase)
                            .tracking(2.2)
                            .foregroundStyle(Color.or)
                        if let date = carte.dateCreation {
                            Text("Préparée \(DateEndry.ilYa(date))")
                                .styleTexte(13, relativeTo: .footnote)
                                .foregroundStyle(Color.orClair.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, Espace.l)
                    .padding(.bottom, Espace.m)
                }

                CarteDecisionView(
                    carte: carte,
                    actionsPossibles: modele.actionsPossibles,
                    enCours: modele.enCours.contains(carte.reference),
                    enAvant: false,
                    enFiche: true,
                    agir: { action, consignes in
                        let ok = await modele.agir(action, sur: carte, consignes: consignes)
                        if ok { fermer() }
                        return ok
                    },
                    ouvrirPiece: { piece in
                        Task { await app.documents.ouvrir(piece.url, nom: piece.nom, api: app.session.api) }
                    }
                )
                .padding(.horizontal, Espace.l)
                .padding(.top, Espace.m)

                if let dossier = chantierLie {
                    Button {
                        fermer()
                        app.vueChantiers = .pipeline
                        app.onglet = .chantiers
                    } label: {
                        HStack(spacing: Espace.s) {
                            Image(PhotosMarque.pour(id: dossier.id))
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Chantier lié").styleSurtitre()
                                Text(dossier.titre).styleTexte(15, relativeTo: .subheadline, graisse: .semibold).foregroundStyle(Color.encre)
                                    .lineLimit(2)
                                Text([dossier.client, dossier.etapeLibelle].joined(separator: " · "))
                                    .styleTexte(13, relativeTo: .footnote)
                                    .foregroundStyle(Color.encreDouce)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(Color.bronze)
                        }
                        .padding(Espace.m)
                        .surfaceCarte(rayon: Espace.rayonPetit)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Espace.l)
                    .padding(.top, Espace.l)
                }

                Text("Rien ne part chez un tiers sans votre geste.")
                    .styleTexte(13, relativeTo: .footnote)
                    .foregroundStyle(Color.encrePale)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Espace.xl)
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.fond)
        .overlay(alignment: .topTrailing) {
            Button {
                fermer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.or)
                    .frame(width: 40, height: 40)
                    .background(Color.espresso.opacity(0.6), in: Circle())
                    .overlay(Circle().stroke(Color.or.opacity(0.35), lineWidth: Espace.filet))
            }
            .padding(Espace.m)
            .accessibilityLabel(Text("Fermer la fiche"))
            .accessibilityIdentifier("fermer-fiche")
        }
        .toast(Binding(get: { modele.toast }, set: { modele.toast = $0 }), decalageBas: Espace.l)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(Color.fond)
    }

    private var chantierLie: Dossier? {
        guard let id = carte.chantierId else { return nil }
        return app.chantiers?.tous.first { $0.id == id }
    }
}
