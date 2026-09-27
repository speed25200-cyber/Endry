import EndryKit
import SwiftUI

/// Assistant vocal plein écran (toucher long du micro central).
///
/// Sphère d'or liquide au centre, transcription en direct (mots provisoires plus pâles),
/// cartes contextuelles qui surgissent. Une décision proposée par la voix n'est jamais validée
/// par la voix : elle apparaît avec son geste (bouton « Oui » ou curseur « Glisser pour envoyer »).
struct VueAssistantVocal: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations
    @State private var assistant: AssistantVocal?

    var body: some View {
        ZStack {
            FondAmbiant()
            VStack(spacing: Espace.l) {
                barreHaute
                Spacer(minLength: 0)
                sphere
                etat
                transcription
                Spacer(minLength: 0)
                cartes
            }
            .padding(.horizontal, Espace.bord)
            .padding(.bottom, Espace.m)
        }
        .environment(\.colorScheme, .dark)
        .task {
            let nouvel = app.nouvelAssistant()
            assistant = nouvel
            await nouvel.demarrer()
        }
        .onDisappear { assistant?.arreter() }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: assistant?.phase)
        .toast(Binding(get: { app.decisions?.toast }, set: { nouveau in if let modele = app.decisions { modele.toast = nouveau } }), decalageBas: Espace.l)
    }

    // MARK: - Morceaux

    private var barreHaute: some View {
        HStack {
            Text(assistant?.nomMoteur ?? "")
                .styleTexte(13, relativeTo: .footnote, graisse: .medium)
                .foregroundStyle(Color.encrePale)
                .accessibilityLabel(Text("Moteur vocal : \(assistant?.nomMoteur ?? "préparation")"))
            Spacer()
            Button {
                assistant?.arreter()
                fermer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.encre)
                    .frame(width: 44, height: 44)
                    .verre(Circle())
            }
            .accessibilityLabel(Text("Fermer l’assistant vocal"))
            .accessibilityIdentifier("fermer-assistant")
        }
        .padding(.top, Espace.xs)
    }

    private var sphere: some View {
        SphereOr(micro: assistant?.niveauMicro ?? 0,
                 voix: assistant?.niveauVoix ?? 0,
                 reflexion: assistant?.phase == .reflexion)
            .frame(maxWidth: 300, maxHeight: 300)
            .contentShape(Circle())
            .onTapGesture {
                // Après une erreur, toucher la sphère relance la conversation.
                if case .erreur = assistant?.phase {
                    Task { await assistant?.demarrer() }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(libellePhase))
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("sphere-assistant")
    }

    private var etat: some View {
        Text(libellePhase)
            .styleTexte(13, relativeTo: .footnote, graisse: .semibold)
            .textCase(.uppercase)
            .tracking(1.4)
            .foregroundStyle(Color.bronze)
            .contentTransition(.opacity)
            .animation(.endry(reduire: reduireAnimations), value: libellePhase)
            .accessibilityHidden(true)
    }

    private var libellePhase: String {
        switch assistant?.phase ?? .preparation {
        case .preparation: "Un instant…"
        case .ecoute: "Je vous écoute"
        case .reflexion: "Je réfléchis"
        case .parole: "Endry répond"
        case .erreur(let message): message
        }
    }

    /// Transcription en surimpression : ce que dit le patron (provisoire plus pâle), puis la réponse.
    private var transcription: some View {
        VStack(spacing: Espace.s) {
            if let assistant, !(assistant.definitif.isEmpty && assistant.provisoire.isEmpty) {
                Text("\(Text(assistant.definitif).foregroundStyle(Color.encre)) \(Text(assistant.provisoire).foregroundStyle(Color.encre.opacity(0.42)))")
                    .styleTitre(22, relativeTo: .title3, graisse: .medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .transition(.opacity)
                    .accessibilityIdentifier("transcription-patron")
            }
            if let reponse = assistant?.reponse, !reponse.isEmpty {
                Text(reponse)
                    .styleTexte(17, relativeTo: .body)
                    .foregroundStyle(Color.orClair.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityIdentifier("reponse-assistant")
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.endry(reduire: reduireAnimations), value: assistant?.reponse)
    }

    private var cartes: some View {
        VStack(spacing: Espace.s) {
            ForEach(assistant?.cartes ?? [], id: \.self) { effet in
                CarteContexte(effet: effet) { assistant?.retirer(effet) }
                    .transition(reduireAnimations ? .opacity : .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(.endry(reduire: reduireAnimations), value: assistant?.cartes ?? [])
    }
}

/// Carte qui surgit pendant la conversation.
struct CarteContexte: View {
    @Environment(ModeleApp.self) private var app
    var effet: ExecuteurOutils.Effet
    var retirer: () -> Void

    var body: some View {
        switch effet {
        case .afficherDecision(let reference):
            if let modele = app.decisions, let carte = modele.cartes.first(where: { $0.reference == reference }) {
                ScrollView {
                    CarteDecisionView(
                        carte: carte,
                        actionsPossibles: modele.actionsPossibles,
                        enCours: modele.enCours.contains(carte.reference),
                        enAvant: false,
                        agir: { action, consignes in
                            let ok = await modele.agir(action, sur: carte, consignes: consignes)
                            if ok { retirer() }
                            return ok
                        },
                        ouvrirPiece: { piece in
                            Task { await app.documents.ouvrir(piece.url, nom: piece.nom, api: app.session.api) }
                        }
                    )
                }
                .frame(maxHeight: 420)
                .scrollBounceBehavior(.basedOnSize)
            } else {
                resume(icone: "checkmark.seal", titre: "Décision \(reference)", detail: "Déjà traitée ou pas encore chargée.")
            }
        case .afficherChantier(let id):
            if let dossier = app.chantiers?.tous.first(where: { $0.id == id }) {
                resume(icone: "hammer.fill", titre: dossier.titre,
                       detail: [dossier.client, dossier.etapeLibelle, Planning.libelleDates(dossier)].compactMap { $0 }.joined(separator: " · "))
            } else {
                resume(icone: "hammer.fill", titre: "Chantier \(id)", detail: "Ouvrez l’espace Chantiers pour le détail.")
            }
        case .afficherFacture(let numero):
            if let facture = app.decisions?.accueil?.encaisser.factures.first(where: { $0.numero == numero }) {
                resume(icone: "doc.text.fill", titre: "\(facture.numero) · \(facture.client)",
                       detail: "\(FormatSuisse.chf(facture.montant)) · Suivi seulement : aucune relance sans votre demande")
            } else {
                resume(icone: "doc.text.fill", titre: "Facture \(numero)", detail: "Suivi seulement : aucune relance sans votre demande")
            }
        case .aucun:
            EmptyView()
        }
    }

    private func resume(icone: String, titre: String, detail: String) -> some View {
        HStack(spacing: Espace.s) {
            Image(systemName: icone)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.bronze)
                .frame(width: 36, height: 36)
                .background(Color.or.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).styleTexte(15, relativeTo: .subheadline, graisse: .semibold).foregroundStyle(Color.encre)
                    .lineLimit(2)
                Text(detail).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(action: retirer) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.encrePale)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(Text("Masquer"))
        }
        .padding(Espace.m)
        .surfaceCarte(rayon: Espace.rayonPetit)
        .accessibilityElement(children: .combine)
    }
}

/// Sphère d'or liquide (shader Metal) : respire au repos, ondule avec la voix du patron,
/// pulse avec celle de l'assistant, tourne lentement quand il réfléchit.
struct SphereOr: View {
    var micro: Float
    var voix: Float
    var reflexion: Bool
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { contexte in
            let t = Float(contexte.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600))
            Rectangle()
                .fill(Color.white)
                .colorEffect(ShaderLibrary.sphereOr(
                    .boundingRect,
                    .float(t),
                    .float(micro),
                    .float(voix),
                    .float(reflexion ? 1 : 0),
                    .float(reduireAnimations ? 0.25 : 1)
                ))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
