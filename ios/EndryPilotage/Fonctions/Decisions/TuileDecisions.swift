import EndryKit
import SwiftUI

/// Accueil Maison Endry : la pile « À décider ». Une tuile par décision, qu'on feuillette du doigt
/// (compteur « 02 / 04 ») ; le titre ouvre la fiche complète (Corriger, Non, pièces) ; le geste du bas dit « Oui ».
struct TuileDecisions: View {
    var modele: ModeleDecisions
    @Binding var visible: String?
    var zoom: Namespace.ID
    var ouvrir: (Carte) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        if modele.cartes.isEmpty {
            tuileVide
                .padding(.horizontal, Espace.bord)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(modele.cartes.enumerated()), id: \.element.id) { index, carte in
                        page(carte, index: index)
                            .matchedTransitionSource(id: carte.reference, in: zoom)
                            .padding(.horizontal, Espace.bord)
                            .containerRelativeFrame(.horizontal)
                            .scrollTransition(.interactive, axis: .horizontal) { contenu, phase in
                                contenu
                                    .opacity(phase.isIdentity ? 1 : 0.4)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.96)
                            }
                            .id(carte.reference)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visible)
            .animation(.endry(reduire: reduireAnimations), value: modele.cartes.map(\.reference))
            .accessibilityIdentifier("carrousel-decisions")
        }
    }

    // MARK: - Une décision

    private func page(_ carte: Carte, index: Int) -> some View {
        let enCours = modele.enCours.contains(carte.reference)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Espace.xs) {
                Text("À décider")
                    .etiquetteMaison()
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("titre-a-decider")
                Text(carte.genre)
                    .font(Police.mono(12))
                    .foregroundStyle(Color.encre)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Color.puce, in: Capsule())
                    .lineLimit(1)
                Spacer(minLength: Espace.xs)
                if !modele.decisionsAutorisees {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ambre)
                        .accessibilityLabel(Text("Lecture seule"))
                }
                compteur(index + 1, sur: modele.cartes.count)
            }

            Button { ouvrir(carte) } label: {
                TitreAdaptatif(texte: carte.titre, grand: 26, lignes: 3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Ouvre la fiche complète : texte, pièces, Corriger, Non"))
            .accessibilityIdentifier("apercu-\(carte.reference)")

            Spacer(minLength: Espace.s)

            geste(carte, enCours: enCours)
                .disabled(!modele.actionsPossibles || enCours)
                .padding(.top, 2)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tuileMaison(rayon: 26)
        .opacity(enCours ? 0.7 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("carte-\(carte.reference)")
    }

    private func compteur(_ rang: Int, sur total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(Self.deuxChiffres(rang))
                .font(Police.serif(30, relativeTo: .title))
                .monospacedDigit()
                .foregroundStyle(Color.encre)
                .contentTransition(.numericText(value: Double(rang)))
            Text(" / \(Self.deuxChiffres(total))")
                .font(Police.serif(16, relativeTo: .callout))
                .monospacedDigit()
                .foregroundStyle(Color.encreDouce)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Décision \(rang) sur \(total)"))
    }

    @ViewBuilder
    private func geste(_ carte: Carte, enCours: Bool) -> some View {
        if carte.estQuestion {
            Button { ouvrir(carte) } label: {
                Label("Répondre", systemImage: "text.bubble")
                    .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                    .foregroundStyle(Color.boutonTexte)
                    .padding(.horizontal, Espace.m)
                    .frame(height: 44)
                    .background(Color.bouton, in: Capsule())
            }
            .buttonStyle(ActionPressee())
            .padding(.bottom, 4)
            .accessibilityIdentifier("repondre-apercu-\(carte.reference)")
        } else {
            // Tout « Oui » se fait en glissant (règle du 28.09.2026) : aucun bouton « Oui ».
            GlisserPourEnvoyer(libelle: carte.libelleGlisser, envoi: carte.partChezUnTiers,
                               identifiant: "glisser-\(carte.reference)", enCours: enCours,
                               actif: modele.actionsPossibles) {
                Task { _ = await modele.agir(.oui, sur: carte, geste: .glissement) }
            }
        }
    }

    private var tuileVide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("À décider")
                .etiquetteMaison()
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("titre-a-decider")
            Text("Rien à décider. Tout roule.")
                .font(Police.serif(23, relativeTo: .title3))
                .foregroundStyle(Color.encre)
            Text("L’assistant vous préviendra dès qu’une proposition attendra votre accord.")
                .styleTexte(13, relativeTo: .footnote)
                .foregroundStyle(Color.encreDouce)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileMaison(rayon: 26)
    }

    static func deuxChiffres(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}
