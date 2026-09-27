import EndryKit
import SwiftUI

/// Pile de décisions : une carte à la fois, les suivantes en retrait derrière elle.
///
/// - Balayage à droite : « Oui » pour une décision sans envoi à un tiers.
///   Une carte qui envoie quelque chose (e-mail, facture, offre) ne part jamais à droite :
///   seul le curseur « Glisser pour envoyer » l'envoie.
/// - Balayage à gauche : « Non », toujours confirmé.
/// - « Plus tard » : la carte passe sous la pile.
struct PileDecisions: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations
    var modele: ModeleDecisions

    /// Références passées sous la pile, dans l'ordre.
    @State private var reportees: [String] = []
    @State private var glissement: CGSize = .zero
    @State private var demandesNon: [String: Int] = [:]
    @State private var retourHaptique = 0

    private static let seuilBalayage: CGFloat = 110

    private var ordonnees: [Carte] {
        let cartes = modele.cartes
        let devant = cartes.filter { !reportees.contains($0.reference) }
        let derriere = reportees.compactMap { reference in cartes.first { $0.reference == reference } }
        return devant + derriere
    }

    var body: some View {
        let pile = ordonnees
        VStack(spacing: Espace.m) {
            if let tete = pile.first {
                carteDeTete(tete, derriere: min(pile.count - 1, 2))
                    .id(tete.reference)
                    .transition(reduireAnimations ? .opacity : .asymmetric(
                        insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.9))
                    ))
                navigation(pile: pile, tete: tete)
            }
        }
        .animation(.endry(reduire: reduireAnimations), value: pile.map(\.reference))
        .sensoryFeedback(.selection, trigger: retourHaptique)
        .onChange(of: app.referenceCiblee, initial: true) { _, reference in
            amenerDevant(reference)
        }
    }

    // MARK: - Carte de tête

    private func carteDeTete(_ carte: Carte, derriere: Int) -> some View {
        let largeur = glissement.width
        let direction: Int = largeur > 40 ? 1 : largeur < -40 ? -1 : 0
        return CarteDecisionView(
            carte: carte,
            actionsPossibles: modele.actionsPossibles,
            enCours: modele.enCours.contains(carte.reference),
            enAvant: app.referenceCiblee == carte.reference,
            demandeNon: demandesNon[carte.reference, default: 0],
            agir: { action, consignes in await modele.agir(action, sur: carte, consignes: consignes) },
            ouvrirPiece: { piece in
                Task { await app.documents.ouvrir(piece.url, nom: piece.nom, api: app.session.api) }
            }
        )
        // Cartes suivantes : deux feuillets en retrait sous la carte de tête.
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                ForEach((0..<derriere).reversed(), id: \.self) { rang in
                    RoundedRectangle(cornerRadius: Espace.rayon, style: .continuous)
                        .fill(Color.surface)
                        .overlay(RoundedRectangle(cornerRadius: Espace.rayon, style: .continuous)
                            .strokeBorder(Color.bordureOr, lineWidth: Espace.filet))
                        .scaleEffect(x: 1 - 0.05 * CGFloat(rang + 1), y: 1, anchor: .bottom)
                        .offset(y: 9 * CGFloat(rang + 1))
                        .opacity(1 - 0.3 * Double(rang + 1))
                }
            }
            .accessibilityHidden(true)
        }
        // Indication du geste : or à droite (« Oui »), rouille à gauche (« Non »).
        .overlay(alignment: direction > 0 ? .topLeading : .topTrailing) {
            if direction != 0 {
                Text(direction > 0 ? "Oui" : "Non")
                    .styleTexte(13, relativeTo: .footnote, graisse: .semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(direction > 0 ? Color.bronze : Color.rouille)
                    .padding(.horizontal, Espace.s)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(direction > 0 ? Color.bronze : Color.rouille, lineWidth: 1))
                    .rotationEffect(.degrees(direction > 0 ? -8 : 8))
                    .padding(Espace.l)
                    .opacity(min(abs(largeur) / Self.seuilBalayage, 1))
                    .accessibilityHidden(true)
            }
        }
        .offset(x: largeur, y: reduireAnimations ? 0 : abs(largeur) * 0.04)
        .rotationEffect(.degrees(reduireAnimations ? 0 : Double(largeur / 26)), anchor: .bottom)
        .simultaneousGesture(balayage(carte), including: balayageActif(carte) ? .all : .subviews)
        .accessibilityAction(named: Text("Plus tard")) { reporter(carte) }
    }

    private func balayageActif(_ carte: Carte) -> Bool {
        !carte.estQuestion && modele.actionsPossibles && !modele.enCours.contains(carte.reference)
    }

    private func balayage(_ carte: Carte) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { valeur in
                // Seuls les gestes franchement horizontaux déplacent la carte (le défilement reste libre).
                guard abs(valeur.translation.width) > abs(valeur.translation.height) * 1.4 else { return }
                // Une carte avec envoi ne part jamais à droite : seul le curseur doré envoie.
                let largeur = carte.exigeGlisser ? min(valeur.translation.width, 0) : valeur.translation.width
                glissement = CGSize(width: largeur, height: 0)
            }
            .onEnded { valeur in
                let largeur = glissement.width
                let predite = valeur.predictedEndTranslation.width
                if !carte.exigeGlisser, largeur > Self.seuilBalayage || (largeur > 50 && predite > Self.seuilBalayage * 2) {
                    partir(vers: 1)
                    Task {
                        // Réussi : la carte quitte la pile ; refusé : elle revient au centre.
                        if await modele.agir(.oui, sur: carte) { glissement = .zero } else { revenir() }
                    }
                } else if largeur < -Self.seuilBalayage || (largeur < -50 && predite < -Self.seuilBalayage * 2) {
                    revenir()
                    demandesNon[carte.reference, default: 0] += 1
                } else {
                    revenir()
                }
            }
    }

    private func partir(vers sens: CGFloat) {
        retourHaptique += 1
        withAnimation(.endry(reduire: reduireAnimations)) {
            glissement = CGSize(width: sens * 600, height: 0)
        }
    }

    private func revenir() {
        withAnimation(reduireAnimations ? .fonduDoux : .spring(response: 0.42, dampingFraction: 0.7)) {
            glissement = .zero
        }
    }

    // MARK: - Navigation

    private func navigation(pile: [Carte], tete: Carte) -> some View {
        HStack(spacing: Espace.s) {
            HStack(spacing: 5) {
                ForEach(Array(pile.prefix(8).enumerated()), id: \.element.id) { index, carte in
                    Capsule()
                        .fill(index == 0 ? AnyShapeStyle(.degradeOr) : AnyShapeStyle(Color.filet))
                        .frame(width: index == 0 ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Décision 1 sur \(pile.count)"))

            Spacer(minLength: Espace.xs)

            if pile.count > 1 {
                Button {
                    reporter(tete)
                } label: {
                    Label("Plus tard", systemImage: "arrow.uturn.down")
                        .styleTexte(15, relativeTo: .subheadline, graisse: .medium)
                        .foregroundStyle(Color.bronze)
                        .padding(.horizontal, Espace.s)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Passe à la décision suivante ; celle-ci revient en fin de pile."))
                .accessibilityIdentifier("decision-suivante")
            }
        }
        .padding(.horizontal, Espace.xxs)
    }

    private func reporter(_ carte: Carte) {
        retourHaptique += 1
        withAnimation(.endry(reduire: reduireAnimations)) {
            reportees.removeAll { $0 == carte.reference }
            reportees.append(carte.reference)
            glissement = .zero
        }
    }

    /// Notification ou lien : la carte visée passe devant.
    private func amenerDevant(_ reference: String?) {
        guard let reference, let index = modele.cartes.firstIndex(where: { $0.reference == reference }) else { return }
        reportees = modele.cartes[..<index].map(\.reference)
    }
}
