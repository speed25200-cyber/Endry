import EndryKit
import SwiftUI

/// Fiche complète d'une décision (maquette E) : genre, référence et rang en verre, titre en Cormorant
/// (la fin en italique), destinataire / objet / pièces, contrôle, message intégral, chantier lié ;
/// en bas, le panneau de verre : glisser pour dire « Oui », « Non » (confirmé) et « Corriger ».
struct FicheDecision: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    var carte: Carte
    var modele: ModeleDecisions

    @State private var confirmationNon = false
    @State private var feuille: ConsignesSheet.Mode?

    private var enCours: Bool { modele.enCours.contains(carte.reference) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    barreHaut
                    Text(provenance)
                        .etiquetteMaison(10.5, couleur: .signal)
                        .padding(.top, Espace.l)
                        .accessibilityIdentifier("fiche-decision")
                    titre
                        .padding(.top, 10)
                    if !lignes.isEmpty || !carte.pieces.isEmpty {
                        details.padding(.top, Espace.l)
                    }
                    if let controle = carte.controle {
                        controleVue(controle).padding(.top, Espace.xl)
                    }
                    if !carte.motif.isEmpty {
                        rubrique("Motif", carte.motif).padding(.top, Espace.xl)
                    }
                    if let texte = carte.texte, !texte.isEmpty {
                        rubrique("Message", texte, selection: true).padding(.top, Espace.xl)
                    }
                    if let dossier = chantierLie {
                        chantier(dossier).padding(.top, Espace.xl)
                    }
                    Text("Rien ne part chez un tiers sans votre geste.")
                        .styleTexte(12, relativeTo: .caption)
                        .foregroundStyle(Color.encreDouce)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Espace.xl)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 240)
                .largeurLisible(Adaptatif.lecture)
            }
            .scrollIndicators(.hidden)

            panneauGestes
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .background(FondMaison(photo: nil))
        .opacity(enCours ? 0.85 : 1)
        .toast(Binding(get: { modele.toast }, set: { modele.toast = $0 }), decalageBas: 200)
        .sensoryFeedback(.warning, trigger: confirmationNon) { _, nouveau in nouveau }
        .confirmationDialog("Écarter cette proposition ?", isPresented: $confirmationNon, titleVisibility: .visible) {
            Button("Écarter", role: .destructive) {
                Task { await agir(.non) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(carte.partChezUnTiers ? "Rien ne sera envoyé." : "L’assistant ne fera rien pour cette carte.")
        }
        .sheet(item: $feuille) { mode in
            ConsignesSheet(mode: mode, carte: carte) { texte in
                await agir(mode == .corriger ? .corriger : .repondre, consignes: texte)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(Color.fond)
    }

    @discardableResult
    private func agir(_ action: ActionDecision, consignes: String? = nil, geste: GesteValidation? = nil) async -> Bool {
        let ok = await modele.agir(action, sur: carte, consignes: consignes, geste: geste)
        if ok { fermer() }
        return ok
    }

    // MARK: - En-tête

    private var barreHaut: some View {
        HStack {
            Button { fermer() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.encre)
                    .frame(width: 40, height: 40)
                    .verreMaison(Circle(), interactif: true)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(ActionPressee())
            .accessibilityLabel(Text("Fermer la fiche"))
            .accessibilityIdentifier("fermer-fiche")
            Spacer(minLength: Espace.xs)
            Text(([carte.genre.uppercased(), carte.reference] + (rang.map { [$0] } ?? [])).joined(separator: " · "))
                .font(Police.mono(11.5))
                .foregroundStyle(Color.encre)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .verreMaison(Capsule())
        }
        .padding(.top, Espace.s)
    }

    private var rang: String? {
        guard let index = modele.cartes.firstIndex(where: { $0.reference == carte.reference }) else { return nil }
        return "\(index + 1) / \(modele.cartes.count)"
    }

    private var provenance: String {
        let quand = carte.dateCreation.map { " · \(DateEndry.ilYa($0))" } ?? ""
        return "Proposé par l’assistant" + quand
    }

    private var titre: some View {
        TitreAdaptatif(texte: carte.titre, grand: 38)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Détails

    private var lignes: [(String, String)] {
        var l: [(String, String)] = []
        if !carte.destinataires.isEmpty { l.append(("À", carte.destinataires.joined(separator: ", "))) }
        if let objet = carte.objet { l.append(("Objet", objet)) }
        return l
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lignes.enumerated()), id: \.offset) { index, ligne in
                if index > 0 { Rectangle().fill(Color.filet).frame(height: Espace.filet) }
                ligneDetail(ligne.0, ligne.1)
            }
            ForEach(Array(carte.pieces.enumerated()), id: \.element.id) { index, piece in
                if index > 0 || !lignes.isEmpty { Rectangle().fill(Color.filet).frame(height: Espace.filet) }
                Button {
                    Task { await app.documents.ouvrir(piece.url, nom: piece.nom, api: app.session.api) }
                } label: {
                    HStack(spacing: 0) {
                        ligneDetail("Pièce", piece.nom)
                        Image(systemName: piece.estPDF ? "doc.richtext" : "paperclip")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.encreDouce)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Ouvre l’aperçu du document"))
            }
        }
        .padding(.horizontal, 16)
        .tuileMaison(rayon: 26)
    }

    private func ligneDetail(_ libelle: String, _ valeur: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Espace.s) {
            Text(libelle)
                .styleTexte(13, relativeTo: .footnote)
                .foregroundStyle(Color.encreDouce)
                .frame(width: 64, alignment: .leading)
            Text(valeur)
                .styleTexte(15, relativeTo: .subheadline)
                .foregroundStyle(Color.encre)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private func controleVue(_ controle: Controle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contrôle").etiquetteMaison()
            if controle.pointsAVerifier.isEmpty {
                pastille(controle.resume, ok: controle.ok)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(controle.pointsAVerifier, id: \.self) { point in
                        VStack(alignment: .leading, spacing: 4) {
                            pastille(point.controle, ok: false)
                            if !point.detail.isEmpty {
                                Text(point.detail)
                                    .styleTexte(14, relativeTo: .subheadline)
                                    .foregroundStyle(Color.encreDouce)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Contrôle qualité : \(controle.resume)"))
    }

    private func pastille(_ texte: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark" : "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ok ? Color.sauge : Color.ambre)
            Text(texte)
                .styleTexte(14, relativeTo: .subheadline)
                .foregroundStyle(Color.encre)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .verreMaison(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func rubrique(_ titre: String, _ texte: String, selection: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titre).etiquetteMaison()
            Text(texte)
                .styleTexte(17, relativeTo: .body)
                .foregroundStyle(Color.encre)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var chantierLie: Dossier? {
        guard let id = carte.chantierId else { return nil }
        return app.chantiers?.tous.first { $0.id == id }
    }

    private func chantier(_ dossier: Dossier) -> some View {
        Button {
            fermer()
            app.ouvrirChantier(dossier.id)
        } label: {
            HStack(spacing: Espace.s) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chantier lié").etiquetteMaison()
                    Text(dossier.titre)
                        .styleTexte(15, relativeTo: .subheadline)
                        .foregroundStyle(Color.encre)
                        .lineLimit(2)
                    Text([dossier.client, dossier.etapeLibelle].joined(separator: " · "))
                        .font(Police.mono(11.5))
                        .foregroundStyle(Color.encreDouce)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Color.encreDouce)
            }
            .padding(14)
            .tuileMaison(rayon: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActionPressee())
    }

    // MARK: - Gestes

    @ViewBuilder
    private var panneauGestes: some View {
        VStack(spacing: 0) {
            if carte.estQuestion {
                Button { feuille = .repondre } label: {
                    Label("Répondre", systemImage: "text.bubble")
                        .styleTexte(15, relativeTo: .subheadline)
                        .foregroundStyle(Color.boutonTexte)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.bouton, in: Capsule())
                }
                .buttonStyle(ActionPressee())
                .padding(14)
                .accessibilityIdentifier("repondre-\(carte.reference)")
            } else {
                // Tout « Oui » se fait en glissant (règle du 28.09.2026) : aucun bouton « Oui ».
                GlisserPourEnvoyer(libelle: carte.libelleGlisser, envoi: carte.partChezUnTiers,
                                   identifiant: "glisser-\(carte.reference)", enCours: enCours,
                                   actif: modele.actionsPossibles) {
                    Task { await agir(.oui, geste: .glissement) }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                Rectangle().fill(Color.filet).frame(height: Espace.filet).padding(.horizontal, 14)
                HStack(spacing: 0) {
                    Button { confirmationNon = true } label: {
                        Text("Non")
                            .styleTexte(16, relativeTo: .body, graisse: .medium)
                            .foregroundStyle(Color.rouille)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("non-\(carte.reference)")
                    Rectangle().fill(Color.filet).frame(width: Espace.filet, height: 46)
                    // « Corriger » sur toute validation ; `modifiable` ne fait que pré-remplir le texte à retoucher.
                    Button { feuille = .corriger } label: {
                        Text("Corriger")
                            .styleTexte(16, relativeTo: .body, graisse: .medium)
                            .foregroundStyle(Color.encre)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("corriger-\(carte.reference)")
                }
                .buttonStyle(.plain)
                .disabled(!modele.actionsPossibles || enCours)
            }
        }
        .verreMaison(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.ombre, radius: 24, y: 12)
        .frame(maxWidth: 560)
    }
}
