import EndryKit
import SwiftUI

// MARK: - Photographies de la maison

/// Photos d'ambiance (voir `ios/CREDITS.md`), attribuées de façon stable aux écrans et aux chantiers.
/// `PhotoRobinetterie` et `PhotoSalleDeBain` sont des **ambiances illustratives** : tant que la direction n'a pas
/// confirmé leur origine, elles ne sont pas présentées comme des réalisations d'Endry SA et portent la mention
/// « Ambiance illustrative » quand elles s'affichent en grand.
enum PhotosMarque {
    static let accueil = "PhotoRobinetterie"
    static let toutes = ["PhotoChauffageSol", "PhotoReseaux", "PhotoSalleDeBain", "PhotoHydraulique", "PhotoSanitaire", "PhotoRobinetterie"]
    /// Images d'ambiance dont l'origine n'est pas confirmée : jamais présentées comme des réalisations.
    static let illustratives: Set<String> = ["PhotoRobinetterie", "PhotoSalleDeBain"]
    static let mentionIllustrative = "Ambiance illustrative"

    static func estIllustrative(_ nom: String) -> Bool { illustratives.contains(nom) }

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

/// Photo qui avance très lentement vers le spectateur (Ken Burns, une seule fois : aucune horloge ne tourne
/// ensuite) ; figée si « Réduire les animations ».
struct PhotoVivante: View {
    var nom: String
    var ancre: UnitPoint = .center
    /// Affiche « Ambiance illustrative » sur les images concernées (l'accueil l'écrit dans son en-tête).
    var mention = true
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
                .overlay(alignment: .bottomTrailing) {
                    // En bas à droite : le haut porte souvent un bouton (fermer, retour).
                    if mention && PhotosMarque.estIllustrative(nom) {
                        MentionIllustrative().padding(Espace.s)
                    }
                }
        }
        .onAppear {
            guard !reduireAnimations, !Configuration.testsUI else { return }
            withAnimation(.easeOut(duration: 16)) { zoom = true }
        }
        .accessibilityHidden(true)
    }
}

/// « Ambiance illustrative » : discret, lisible sur la photo.
struct MentionIllustrative: View {
    var body: some View {
        Text(PhotosMarque.mentionIllustrative)
            .font(.caption2)
            .foregroundStyle(Color.white.opacity(0.8))
            .shadow(color: .black.opacity(0.6), radius: 2)
            .accessibilityIdentifier("mention-illustrative")
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
                    .fill(Color.fond.shadow(.drop(color: .black.opacity(0.35), radius: 30, y: -10)))
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                            .stroke(Color.or.opacity(0.22), lineWidth: Espace.filet)
                            .frame(height: 64)
                            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                    }
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
    var agir: @MainActor (ActionDecision, GesteValidation?) async -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            Button(action: ouvrir) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ligneGenre)
                            .styleTexte(12, relativeTo: .caption, graisse: .semibold)
                            .foregroundStyle(carte.partChezUnTiers ? Color.bronzePapier : Color(hex: 0x4F6B4A))
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
        .background {
            RoundedRectangle(cornerRadius: Espace.rayon, style: .continuous)
                .fill(Color.papier.shadow(.drop(color: .black.opacity(0.28), radius: 18, y: 10)))
        }
        .opacity(enCours ? 0.75 : 1)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("carte-\(carte.reference)")
    }

    private var ligneGenre: String {
        if carte.estQuestion { return "\(carte.genre) · à répondre" }
        return carte.partChezUnTiers ? "\(carte.genre) · part chez un tiers" : "\(carte.genre) · sans envoi"
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
        } else {
            // Tout « Oui » se fait en glissant (règle du 28.09.2026) : aucun bouton « Oui ».
            GlisserPourEnvoyer(libelle: carte.libelleGlisser, envoi: carte.partChezUnTiers,
                               identifiant: "glisser-\(carte.reference)", enCours: enCours, actif: actionsPossibles,
                               surPapier: true) {
                Task { _ = await agir(.oui, .glissement) }
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
