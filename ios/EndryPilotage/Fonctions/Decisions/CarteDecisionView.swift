import EndryKit
import SwiftUI

/// Une décision : contenu complet, contrôle qualité, pièces jointes, actions Oui / Corriger / Non.
struct CarteDecisionView: View {
    var carte: Carte
    var actionsPossibles: Bool
    var enCours: Bool
    var enAvant: Bool
    /// Incrémenté quand le patron balaie la carte vers la gauche : ouvre la confirmation « Non ».
    var demandeNon = 0
    /// Présentée en fiche plein écran : pas de cadre de carte, texte complet déplié, grand titre.
    var enFiche = false
    /// `GesteValidation` : seul le glissement à l'écran peut dire « Oui ».
    var agir: @MainActor (ActionDecision, String?, GesteValidation?) async -> Bool
    var ouvrirPiece: (Piece) -> Void

    @State private var texteDeplie = false
    @State private var confirmationNon = false
    @State private var feuille: ConsignesSheet.Mode?
    @State private var surbrillance = false

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            enTete

            Text(carte.titre)
                .styleTitre(enFiche ? 30 : 22, relativeTo: enFiche ? .title : .title3)
                .foregroundStyle(Color.encre)
                .fixedSize(horizontal: false, vertical: true)

            if !carte.destinataires.isEmpty || carte.objet != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if !carte.destinataires.isEmpty {
                        ligneInfo("À", carte.destinataires.joined(separator: ", "), icone: "person.crop.circle")
                    }
                    if let objet = carte.objet {
                        ligneInfo("Objet", objet, icone: "text.quote")
                    }
                }
            }

            if !carte.motif.isEmpty {
                Text(carte.motif)
                    .styleTexte(15, relativeTo: .subheadline)
                    .foregroundStyle(Color.encreDouce)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let controle = carte.controle {
                BadgeControle(controle: controle)
            }

            if let texte = carte.texte, !texte.isEmpty {
                texteComplet(texte)
            }

            if !carte.pieces.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Espace.xs) {
                        ForEach(carte.pieces) { piece in
                            Button { ouvrirPiece(piece) } label: {
                                Label(piece.nom, systemImage: piece.estPDF ? "doc.richtext" : "paperclip")
                                    .styleTexte(13, relativeTo: .footnote, graisse: .medium)
                                    .foregroundStyle(Color.encre)
                                    .padding(.horizontal, Espace.s)
                                    .padding(.vertical, Espace.xs)
                                    .background(Color.surfaceCreuse, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("Ouvre l’aperçu du document"))
                        }
                    }
                }
                .scrollClipDisabled()
            }

            actions
                .padding(.top, Espace.xxs)
        }
        .padding(enFiche ? 0 : Espace.l)
        .modifier(CadreCarte(actif: !enFiche))
        .onAppear { if enFiche { texteDeplie = true } }
        .overlay {
            RoundedRectangle(cornerRadius: Espace.rayon, style: .continuous)
                .strokeBorder(Color.or, lineWidth: surbrillance ? 2 : 0)
                .animation(.easeInOut(duration: 0.6), value: surbrillance)
        }
        .opacity(enCours ? 0.7 : 1)
        .sensoryFeedback(.warning, trigger: confirmationNon) { _, nouveau in nouveau }
        .confirmationDialog("Écarter cette proposition ?", isPresented: $confirmationNon, titleVisibility: .visible) {
            Button("Écarter", role: .destructive) {
                Task { _ = await agir(.non, nil, nil) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(carte.partChezUnTiers ? "Rien ne sera envoyé." : "L’assistant ne fera rien pour cette carte.")
        }
        .sheet(item: $feuille) { mode in
            ConsignesSheet(mode: mode, carte: carte) { texte in
                await agir(mode == .corriger ? .corriger : .repondre, texte, nil)
            }
        }
        .onChange(of: demandeNon) { _, _ in
            guard !carte.estQuestion else { return }
            confirmationNon = true
        }
        .onChange(of: enAvant, initial: true) { _, actif in
            guard actif else { return }
            surbrillance = true
            Task {
                try? await Task.sleep(for: .seconds(2.4))
                surbrillance = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("carte-\(carte.reference)")
    }

    // MARK: - Morceaux

    private var enTete: some View {
        HStack(spacing: Espace.xs) {
            GenreView(genre: carte.genre)
            Spacer()
            if let date = carte.dateCreation {
                Text(DateEndry.ilYa(date))
                    .styleTexte(12, relativeTo: .caption)
                    .foregroundStyle(Color.encrePale)
            }
            ReferenceView(texte: carte.reference)
        }
    }

    private func ligneInfo(_ libelle: String, _ valeur: String, icone: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icone)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.encrePale)
            Text(libelle).styleTexte(13, relativeTo: .footnote, graisse: .semibold).foregroundStyle(Color.encrePale)
            Text(valeur).styleTexte(13, relativeTo: .footnote, graisse: .medium).foregroundStyle(Color.encre)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private func texteComplet(_ texte: String) -> some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            Button {
                withAnimation(.endry) { texteDeplie.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(texteDeplie ? "Masquer le texte" : "Lire le texte complet")
                        .styleTexte(14, relativeTo: .subheadline, graisse: .semibold)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(texteDeplie ? 180 : 0))
                }
                .foregroundStyle(Color.bronze)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("deplier-\(carte.reference)")

            if texteDeplie {
                HStack(alignment: .top, spacing: Espace.s) {
                    Rectangle().fill(.degradeOr).frame(width: 2)
                    Text(texte)
                        .styleTexte(15, relativeTo: .body)
                        .foregroundStyle(Color.encre)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Espace.xxs)
                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if carte.estQuestion {
            HStack(spacing: Espace.s) {
                // Une question attend une réponse écrite ou dictée : pas de « Non ».
                Button {
                    feuille = .repondre
                } label: {
                    Label("Répondre", systemImage: "text.bubble")
                }
                .buttonStyle(BoutonPrincipal())
                .accessibilityIdentifier("repondre-\(carte.reference)")
            }
            .disabled(!actionsPossibles || enCours)
        } else {
            VStack(spacing: Espace.s) {
                // Tout « Oui » se fait en glissant (règle du 28.09.2026) : aucun bouton « Oui ».
                GlisserPourEnvoyer(libelle: carte.libelleGlisser, envoi: carte.partChezUnTiers,
                                   identifiant: "glisser-\(carte.reference)", enCours: enCours, actif: actionsPossibles) {
                    Task { _ = await agir(.oui, nil, .glissement) }
                }
                HStack(spacing: Espace.s) {
                    // « Corriger » sur toute validation ; `modifiable` ne fait que pré-remplir le texte à retoucher.
                    Button {
                        feuille = .corriger
                    } label: {
                        Text("Corriger")
                    }
                    .buttonStyle(BoutonSecondaire())
                    .accessibilityIdentifier("corriger-\(carte.reference)")
                    boutonNon
                }
                .disabled(!actionsPossibles || enCours)
            }
        }
    }

    private var boutonNon: some View {
        Button {
            confirmationNon = true
        } label: {
            Text("Non")
        }
        .buttonStyle(BoutonSecondaire(couleur: .rouille))
        .accessibilityIdentifier("non-\(carte.reference)")
    }
}

/// Cadre de carte, retiré quand la décision est présentée en fiche.
private struct CadreCarte: ViewModifier {
    var actif: Bool

    func body(content: Content) -> some View {
        if actif {
            content.surfaceCarte()
        } else {
            content
        }
    }
}

extension ConsignesSheet.Mode: Identifiable {
    var id: String { titre }
}

#Preview("Cartes") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(Fixtures.cartes) { carte in
                CarteDecisionView(carte: carte, actionsPossibles: true, enCours: false, enAvant: false) { _, _, _ in true } ouvrirPiece: { _ in }
            }
        }
        .padding()
        .verrouillerLargeur()
    }
    .background(Color.fond)
}
