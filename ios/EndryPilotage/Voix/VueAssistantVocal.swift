import EndryKit
import SwiftUI

/// Assistant vocal plein écran (toucher long du micro central, bouton « Parler à Endry », raccourci Siri).
///
/// L'app s'assombrit, une sphère de verre fumé éclot au centre : de l'or liquide y coule, plus vite quand
/// Endry parle, un halo suit la voix, une lueur dorée court sur le bord de l'écran (façon Siri).
/// La réponse s'allume mot à mot pendant qu'elle est dite. Suggestions et champ pour écrire plutôt que parler.
/// Toucher la sphère pendant qu'Endry parle l'interrompt. Une décision proposée par la voix n'est jamais validée
/// par la voix : elle apparaît avec son geste (bouton « Oui » ou curseur « Glisser pour envoyer »).
struct VueAssistantVocal: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations
    @State private var assistant: AssistantVocal?
    @State private var question = ""
    @State private var apparu = false
    @FocusState private var clavier: Bool

    /// Questions du quotidien, à toucher plutôt qu'à dire.
    private static let suggestions = [
        "Qu’est-ce qui m’attend aujourd’hui ?",
        "Qui me doit de l’argent ?",
        "Quels chantiers cette semaine ?",
        "Qu’est-ce que je dois décider ?",
    ]

    var body: some View {
        ZStack {
            fond
            LueurBord(assistant: assistant)
                .opacity(apparu ? 1 : 0)
            VStack(spacing: 0) {
                barreHaute
                    .opacity(apparu ? 1 : 0)
                Spacer(minLength: Espace.s)
                sphere
                EtatAssistant(phase: assistant?.phase ?? .preparation)
                    .padding(.top, Espace.xs)
                    .opacity(apparu ? 1 : 0)
                TranscriptionAssistant(assistant: assistant)
                    .padding(.top, Espace.l)
                    .opacity(apparu ? 1 : 0)
                Spacer(minLength: Espace.s)
                cartes
                if assistant?.cartes.isEmpty ?? true, assistant?.reponse.isEmpty ?? true, !clavier {
                    suggestions
                        .padding(.bottom, Espace.s)
                        .transition(.opacity.combined(with: .offset(y: 12)))
                }
                champQuestion
                    .opacity(apparu ? 1 : 0)
                    .offset(y: apparu ? 0 : 30)
            }
            .padding(.horizontal, Espace.bord)
            .padding(.bottom, Espace.s)
        }
        .environment(\.colorScheme, .dark)
        .presentationBackground(.clear)
        .animation(.endry(reduire: reduireAnimations), value: assistant?.cartes ?? [])
        .task {
            withAnimation(reduireAnimations ? .fonduDoux : .spring(response: 0.7, dampingFraction: 0.82)) { apparu = true }
            let nouvel = app.nouvelAssistant()
            assistant = nouvel
            await nouvel.demarrer()
        }
        .onDisappear { assistant?.arreter() }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: assistant?.phase)
        .toast(Binding(get: { app.decisions?.toast }, set: { nouveau in if let modele = app.decisions { modele.toast = nouveau } }), decalageBas: Espace.l)
    }

    /// L'app reste devinée derrière un voile espresso profond : l'assistant se pose au-dessus, sans rupture.
    private var fond: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color(hex: 0x0E0A06).opacity(0.9)
            RadialGradient(colors: [Color(hex: 0x9F722A).opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.36),
                           startRadius: 10, endRadius: 360)
        }
        .opacity(apparu ? 1 : 0)
        .ignoresSafeArea()
        .onTapGesture { clavier = false }
    }

    private func fermer() {
        clavier = false
        withAnimation(.easeIn(duration: 0.24)) { apparu = false }
        Task {
            try? await Task.sleep(for: .milliseconds(240))
            assistant?.arreter()
            app.fermerAssistant()
        }
    }

    // MARK: - Morceaux

    private var barreHaute: some View {
        HStack {
            if let nom = assistant?.nomMoteur, !nom.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: nom.contains("Apple Intelligence") ? "sparkles" : "waveform")
                        .font(.system(size: 12, weight: .semibold))
                    Text(nom)
                        .styleTexte(12, relativeTo: .caption, graisse: .medium)
                }
                .foregroundStyle(Color.orClair.opacity(0.75))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Color.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().stroke(Color.or.opacity(0.18), lineWidth: Espace.filet))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Moteur vocal : \(nom)"))
                .transition(.opacity)
            }
            Spacer()
            Button(action: fermer) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.orClair)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(Color.or.opacity(0.2), lineWidth: Espace.filet))
            }
            .accessibilityLabel(Text("Fermer l’assistant vocal"))
            .accessibilityIdentifier("fermer-assistant")
        }
        .padding(.top, Espace.xs)
        .animation(.endry, value: assistant?.nomMoteur)
    }

    private var sphere: some View {
        OrbeEndry(assistant: assistant)
            .frame(maxWidth: 330, maxHeight: 330)
            .scaleEffect(apparu ? 1 : 0.35)
            .blur(radius: apparu ? 0 : 24)
            .opacity(apparu ? 1 : 0)
            .contentShape(Circle().scale(0.6))
            .onTapGesture {
                switch assistant?.phase ?? .preparation {
                case .erreur:
                    // Après une erreur, toucher la sphère relance la conversation.
                    Task { await assistant?.demarrer() }
                case .parole:
                    // Endry se tait et rend la parole.
                    assistant?.interrompre()
                default:
                    clavier = false
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(EtatAssistant.libelle(assistant?.phase ?? .preparation)))
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityAction(named: Text("Interrompre")) { assistant?.interrompre() }
            .accessibilityIdentifier("sphere-assistant")
    }

    private var suggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Espace.xs) {
                ForEach(Array(Self.suggestions.enumerated()), id: \.offset) { index, texte in
                    Button {
                        Task { await assistant?.poser(texte) }
                    } label: {
                        Text(texte)
                            .styleTexte(14, relativeTo: .subheadline, graisse: .medium)
                            .foregroundStyle(Color.orClair.opacity(0.9))
                            .padding(.horizontal, Espace.m)
                            .frame(minHeight: 40)
                            .background(Color.white.opacity(0.06), in: Capsule())
                            .overlay(Capsule().stroke(Color.or.opacity(0.22), lineWidth: Espace.filet))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("suggestion-\(index)")
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .disabled(!(assistant?.pret ?? false))
    }

    /// Écrire plutôt que parler : même conversation, mêmes outils, mêmes règles.
    private var champQuestion: some View {
        let vide = question.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: Espace.xs) {
            TextField("", text: $question, prompt: Text("Écrire à Endry…").foregroundStyle(Color.orClair.opacity(0.4)))
                .styleTexte(16, relativeTo: .body)
                .foregroundStyle(Color.orClair)
                .tint(Color.or)
                .focused($clavier)
                .submitLabel(.send)
                .onSubmit(envoyerQuestion)
                .padding(.leading, Espace.m)
                .padding(.vertical, 13)
                .accessibilityIdentifier("champ-assistant")
            Button(action: envoyerQuestion) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.espresso)
                    .frame(width: 36, height: 36)
                    .background(Color.or, in: Circle())
            }
            .disabled(vide)
            .opacity(vide ? 0.35 : 1)
            .scaleEffect(vide ? 0.9 : 1)
            .animation(.endryVif, value: vide)
            .padding(.trailing, 6)
            .accessibilityLabel(Text("Envoyer la question"))
            .accessibilityIdentifier("envoyer-question")
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.or.opacity(clavier ? 0.45 : 0.18), lineWidth: Espace.filet))
        .animation(.endryVif, value: clavier)
    }

    private func envoyerQuestion() {
        let texte = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty else { return }
        question = ""
        clavier = false
        Task { await assistant?.poser(texte) }
    }

    private var cartes: some View {
        VStack(spacing: Espace.s) {
            ForEach(assistant?.cartes ?? [], id: \.self) { effet in
                CarteContexte(effet: effet) { assistant?.retirer(effet) }
                    .transition(reduireAnimations ? .opacity : .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)))
            }
        }
        .padding(.bottom, Espace.s)
    }
}

// MARK: - État, transcription

/// Libellé de la phase, en capitales Cinzel, qui se fond d'un état à l'autre.
private struct EtatAssistant: View {
    var phase: PhaseVoix
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    static func libelle(_ phase: PhaseVoix) -> String {
        switch phase {
        case .preparation: "Un instant"
        case .ecoute: "À l’écoute"
        case .reflexion: "Réflexion"
        case .parole: "Endry répond"
        case .erreur(let message): message
        }
    }

    var body: some View {
        let texte = Self.libelle(phase)
        Group {
            if case .erreur = phase {
                Text(texte)
                    .styleTexte(14, relativeTo: .footnote, graisse: .medium)
                    .foregroundStyle(Color.orClair.opacity(0.8))
                    .multilineTextAlignment(.center)
            } else {
                Text(texte)
                    .font(Police.etiquette(12, relativeTo: .footnote))
                    .textCase(.uppercase)
                    .tracking(3)
                    .foregroundStyle(Color.or.opacity(0.85))
            }
        }
        .id(texte)
        .transition(.opacity.combined(with: .offset(y: 4)))
        .animation(.endry(reduire: reduireAnimations), value: texte)
        .accessibilityHidden(true)
    }
}

/// Ce que dit le patron (discret, en italique), puis la réponse en grand, qui s'allume mot à mot à mesure qu'elle est dite.
/// Vue séparée : seule elle se redessine à chaque mot.
private struct TranscriptionAssistant: View {
    var assistant: AssistantVocal?
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        VStack(spacing: Espace.s) {
            if let assistant, !(assistant.definitif.isEmpty && assistant.provisoire.isEmpty) {
                Text("\(Text(assistant.definitif).foregroundStyle(Color.orClair.opacity(0.62))) \(Text(assistant.provisoire).foregroundStyle(Color.orClair.opacity(0.3)))")
                    .styleTitre(20, relativeTo: .title3, graisse: .italique)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .transition(.opacity)
                    .accessibilityIdentifier("transcription-patron")
            }
            if let assistant, !assistant.reponse.isEmpty {
                let (dit, reste) = Self.decouper(assistant.reponse, lu: assistant.reponseLue)
                Text("\(Text(dit).foregroundStyle(Color(hex: 0xFBEBD0)))\(Text(reste).foregroundStyle(Color.orClair.opacity(0.28)))")
                    .styleTitre(26, relativeTo: .title2, graisse: .medium)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .minimumScaleFactor(0.75)
                    .lineLimit(7)
                    .transition(.opacity.combined(with: .offset(y: 10)))
                    .animation(.easeOut(duration: 0.18), value: assistant.reponseLue)
                    .accessibilityLabel(Text(assistant.reponse))
                    .accessibilityIdentifier("reponse-assistant")
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.endry(reduire: reduireAnimations), value: assistant?.reponse)
    }

    /// Partie déjà dite / partie à venir (décalage UTF-16 donné par la synthèse vocale).
    static func decouper(_ texte: String, lu: Int?) -> (String, String) {
        guard let lu else { return (texte, "") }
        let utf = texte.utf16
        let borne = min(max(lu, 0), utf.count)
        let index = utf.index(utf.startIndex, offsetBy: borne)
        guard let dit = String(utf[..<index]), let reste = String(utf[index...]) else { return (texte, "") }
        return (dit, reste)
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

// MARK: - Sphère et lueur (shaders Metal)

/// Niveaux lissés image par image, et phase d'écoulement accumulée (la vitesse change sans à-coup).
@MainActor
final class LisseurOrbe {
    struct Valeurs {
        var horloge: Float
        var flux: Float
        var micro: Float
        var voix: Float
        var reflexion: Float
        var lueur: Float
    }

    private var derniere: Date?
    private var flux: Float = 0
    private var micro: Float = 0
    private var voix: Float = 0
    private var reflexion: Float = 0
    private var lueur: Float = 0

    func avancer(_ date: Date, assistant: AssistantVocal?, lent: Bool) -> Valeurs {
        let dt = Float(min(max(date.timeIntervalSince(derniere ?? date), 0), 0.1))
        derniere = date
        let phase = assistant?.phase ?? .preparation
        let cibleMicro = phase == .ecoute ? (assistant?.niveauMicro ?? 0) : 0
        let cibleVoix = phase == .parole ? (assistant?.niveauVoix ?? 0) : 0
        let cibleReflexion: Float = phase == .reflexion ? 1 : 0
        let horloge = Float(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600))
        let cibleLueur: Float = switch phase {
        case .ecoute: 0.22 + 0.55 * cibleMicro
        case .parole: 0.32 + 0.6 * cibleVoix
        case .reflexion: 0.5 + 0.12 * sin(horloge * 3)
        case .preparation: 0.12
        case .erreur: 0
        }
        // Attaque vive, relâche douce : la matière réagit sans trembler.
        func lisser(_ v: inout Float, _ cible: Float, monte: Float, descend: Float) {
            let k = 1 - exp(-dt * (cible > v ? monte : descend))
            v += (cible - v) * k
        }
        lisser(&micro, min(cibleMicro * 1.6, 1), monte: 18, descend: 6)
        lisser(&voix, min(cibleVoix * 1.3, 1), monte: 16, descend: 5)
        lisser(&reflexion, cibleReflexion, monte: 3, descend: 2)
        lisser(&lueur, cibleLueur, monte: 8, descend: 3)
        let vitesse: Float = (0.10 + 0.55 * voix + 0.45 * reflexion + 0.25 * micro) * (lent ? 0.3 : 1)
        flux += dt * vitesse
        if flux > 1_000 { flux -= 1_000 }
        return Valeurs(horloge: horloge, flux: flux, micro: micro, voix: voix, reflexion: reflexion, lueur: lueur)
    }
}

/// Sphère de verre fumé, parfaitement ronde, où coule de l'or liquide (bruit fractal déformé, shader Metal) :
/// l'or s'emballe quand Endry parle, le bord frémit avec la voix du patron, un anneau tourne pendant la réflexion.
/// Rendue à la fréquence de l'écran (120 Hz sur ProMotion) ; seule cette vue se redessine.
struct OrbeEndry: View {
    var assistant: AssistantVocal?
    @State private var lisseur = LisseurOrbe()
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        TimelineView(.animation) { contexte in
            let v = lisseur.avancer(contexte.date, assistant: assistant, lent: reduireAnimations)
            Rectangle()
                .fill(Color.white)
                .colorEffect(ShaderLibrary.orbeEndry(
                    .boundingRect,
                    .float(v.horloge),
                    .float(v.flux),
                    .float(v.micro),
                    .float(v.voix),
                    .float(v.reflexion),
                    .float(reduireAnimations ? 0.3 : 1)
                ))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Lueur dorée qui court sur le bord de l'écran, comme Siri : douce à l'écoute, vive quand Endry parle.
struct LueurBord: View {
    var assistant: AssistantVocal?
    @State private var lisseur = LisseurOrbe()
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        TimelineView(.animation) { contexte in
            let v = lisseur.avancer(contexte.date, assistant: assistant, lent: reduireAnimations)
            Rectangle()
                .fill(Color.white)
                .colorEffect(ShaderLibrary.lueurBord(
                    .boundingRect,
                    .float(reduireAnimations ? 0 : v.horloge),
                    .float(v.lueur),
                    .float(Self.rayonEcran)
                ))
                .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Rayon des coins de l'écran (iPhone à Face ID : ~47 à 62 pt).
    static let rayonEcran: Float = 54
}
