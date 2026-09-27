import EndryKit
import SwiftUI

// MARK: - Photographies de la maison

/// Photos de réalisations Endry SA (celles du site), attribuées de façon stable aux écrans et aux chantiers.
enum PhotosMarque {
    static let accueil = "PhotoRobinetterie"
    static let toutes = ["PhotoChauffageSol", "PhotoReseaux", "PhotoSalleDeBain", "PhotoHydraulique", "PhotoSanitaire", "PhotoRobinetterie"]

    /// Même chantier, même photo, à chaque ouverture.
    static func pour(id: String) -> String {
        let somme = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return toutes[somme % toutes.count]
    }

    /// Photo d'ambiance selon le genre de la décision.
    static func pour(genre: String) -> String {
        let g = genre.lowercased()
        if g.contains("facture") || g.contains("paiement") { return "PhotoHydraulique" }
        if g.contains("offre") { return "PhotoSanitaire" }
        if g.contains("question") { return "PhotoReseaux" }
        if g.contains("planning") || g.contains("rendez") { return "PhotoChauffageSol" }
        return "PhotoSalleDeBain"
    }
}

/// Photo qui zoome très lentement (Ken Burns) ; figée si « Réduire les animations ».
struct PhotoVivante: View {
    var nom: String
    var ancre: UnitPoint = .center
    @State private var zoom = false
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        GeometryReader { geo in
            Image(nom)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(zoom ? 1.16 : 1.05, anchor: ancre)
                .clipped()
        }
        .onAppear {
            guard !reduireAnimations, !Configuration.testsUI else { return }
            withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) { zoom = true }
        }
        .accessibilityHidden(true)
    }
}

/// Voile brun sur une photo : le texte crème reste lisible en haut et en bas.
struct VoilePhoto: View {
    var haut: Double = 0.62
    var bas: Double = 1

    var body: some View {
        LinearGradient(stops: [
            .init(color: Color.espresso.opacity(haut), location: 0),
            .init(color: Color.espresso.opacity(0.08), location: 0.32),
            .init(color: Color.espresso.opacity(0.3), location: 0.62),
            .init(color: Color.espresso.opacity(bas), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .accessibilityHidden(true)
    }
}

/// Feuille brune arrondie posée sur une photo (écran Aujourd'hui, fiches).
struct FeuilleMaison<Contenu: View>: View {
    @ViewBuilder var contenu: Contenu

    var body: some View {
        contenu
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                    .fill(Color.fond)
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                            .stroke(Color.or.opacity(0.22), lineWidth: Espace.filet)
                            .frame(height: 64)
                            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                    }
                    .shadow(color: .black.opacity(0.35), radius: 30, y: -10)
            }
    }
}

// MARK: - Carte papier d'une décision (carrousel)

/// Carte crème du carrousel : l'essentiel et le geste principal. Toucher le texte ouvre la fiche complète.
struct CarteApercuDecision: View {
    var carte: Carte
    var actionsPossibles: Bool
    var enCours: Bool
    var ouvrir: () -> Void
    var agir: @MainActor (ActionDecision) async -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            Button(action: ouvrir) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ligneGenre)
                            .styleTexte(12, relativeTo: .caption, graisse: .semibold)
                            .foregroundStyle(carte.exigeGlisser ? Color.bronzePapier : Color(hex: 0x4F6B4A))
                            .lineLimit(1)
                        Spacer(minLength: Espace.xs)
                        Text(carte.reference)
                            .font(Police.reference(11))
                            .foregroundStyle(Color.encrePapierDouce)
                    }
                    Text(carte.titre)
                        .styleTitre(24, relativeTo: .title3)
                        .foregroundStyle(Color.encrePapier)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let resume {
                        Text(resume)
                            .styleTexte(13, relativeTo: .footnote)
                            .foregroundStyle(Color.encrePapierDouce)
                            .lineLimit(2)
                    }
                    HStack(spacing: 4) {
                        Text("Voir le détail")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .styleTexte(12, relativeTo: .caption, graisse: .semibold)
                    .foregroundStyle(Color.bronzePapier)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Ouvre la fiche complète de la décision"))
            .accessibilityIdentifier("apercu-\(carte.reference)")

            Spacer(minLength: Espace.xs)

            geste
                .disabled(!actionsPossibles || enCours)
        }
        .padding(Espace.m)
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
        .background(Color.papier, in: RoundedRectangle(cornerRadius: Espace.rayon, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
        .opacity(enCours ? 0.75 : 1)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("carte-\(carte.reference)")
    }

    private var ligneGenre: String {
        if carte.estQuestion { return "\(carte.genre) · à répondre" }
        return carte.exigeGlisser ? "\(carte.genre) · part chez un tiers" : "\(carte.genre) · sans envoi"
    }

    private var resume: String? {
        let morceaux = [carte.destinataires.first, carte.objet].compactMap { $0 }
        if !morceaux.isEmpty { return morceaux.joined(separator: " · ") }
        return carte.motif.isEmpty ? nil : carte.motif
    }

    @ViewBuilder
    private var geste: some View {
        if carte.estQuestion {
            Button(action: ouvrir) {
                Label("Répondre", systemImage: "text.bubble")
            }
            .buttonStyle(BoutonPapier(principal: true))
            .accessibilityIdentifier("repondre-apercu-\(carte.reference)")
        } else if carte.exigeGlisser {
            GlisserPourEnvoyer(libelle: "Glisser pour envoyer", enCours: enCours, actif: actionsPossibles, surPapier: true) {
                Task { _ = await agir(.oui) }
            }
        } else {
            HStack(spacing: Espace.xs) {
                Button {
                    Task { _ = await agir(.oui) }
                } label: {
                    HStack(spacing: 6) {
                        if enCours { ProgressView().tint(Color.or) }
                        Text("Oui")
                    }
                }
                .buttonStyle(BoutonPapier(principal: true))
                .accessibilityIdentifier("oui-\(carte.reference)")
                Button("Détails", action: ouvrir)
                    .buttonStyle(BoutonPapier(principal: false))
            }
        }
    }
}

/// Boutons posés sur le papier crème : brun du logo (principal) ou contour fin.
struct BoutonPapier: ButtonStyle {
    var principal: Bool

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .styleTexte(15, relativeTo: .body, graisse: .semibold)
            .foregroundStyle(principal ? Color.or : Color.encrePapier)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                Capsule().fill(principal ? Color.espresso : Color.papierCreuse)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.endryVif, value: configuration.isPressed)
    }
}

// MARK: - Points de pagination

struct PointsPagination: View {
    var nombre: Int
    var actif: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<min(nombre, 8), id: \.self) { index in
                Capsule()
                    .fill(Color.or.opacity(index == actif ? 1 : 0.35))
                    .frame(width: index == actif ? 18 : 6, height: 6)
            }
        }
        .animation(.endry, value: actif)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Décision \(actif + 1) sur \(nombre)"))
    }
}
