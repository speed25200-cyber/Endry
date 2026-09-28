import EndryKit
import UIKit
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
        "Que fait Claude sur le PC ?",
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
                if !compact { Spacer(minLength: Espace.s) }
                // Réponse longue ou carte à l'écran : la sphère se range en haut à gauche, le texte prend la place.
                let disposition = compact ? AnyLayout(HStackLayout(alignment: .center, spacing: Espace.m))
                                          : AnyLayout(VStackLayout(spacing: 0))
                disposition {
                    sphere
                    VStack(alignment: compact ? .leading : .center, spacing: 0) {
                        EtatAssistant(phase: assistant?.phase ?? .preparation)
                            .padding(.top, compact ? 0 : Espace.xs)
                        if let nom = assistant?.nomMoteur, !nom.isEmpty {
                            Label(nom, systemImage: nom.contains("Apple Intelligence") ? "sparkles" : "waveform")
                                .font(PoliceAssistant.texte(11, .medium, relativeTo: .caption2))
                                .foregroundStyle(Color.orClair.opacity(0.4))
                                .padding(.top, 6)
                                .accessibilityLabel(Text("Moteur vocal : \(nom)"))
                                .transition(.opacity)
                        }
                        if assistant?.phase == .parole, assistant?.nomMoteur.contains("continue") == true {
                            Text("Parlez pour l’interrompre")
                                .font(PoliceAssistant.texte(12, .medium, relativeTo: .caption))
                                .foregroundStyle(Color.orClair.opacity(0.6))
                                .padding(.top, 6)
                                .transition(.opacity)
                        }
                        if assistant?.phase == .ecoute, ReglageVoix.reponseAuToucher {
                            Text("Touchez la sphère quand vous avez fini")
                                .font(PoliceAssistant.texte(12, .medium, relativeTo: .caption))
                                .foregroundStyle(Color.orClair.opacity(0.6))
                                .padding(.top, 6)
                                .transition(.opacity)
                                .accessibilityIdentifier("aide-toucher-sphere")
                        }
                    }
                    .opacity(apparu ? 1 : 0)
                    if compact { Spacer(minLength: 0) }
                }
                .padding(.top, compact ? Espace.s : 0)
                if compact {
                    ReponseLisible(assistant: assistant)
                        .frame(maxHeight: .infinity)
                        .transition(.opacity)
                        // Toucher la réponse pendant qu'Endry parle l'interrompt (comme la sphère).
                        .onTapGesture {
                            if assistant?.phase == .parole { assistant?.interrompre() } else { clavier = false }
                        }
                } else {
                    TranscriptionAssistant(assistant: assistant)
                        .padding(.top, Espace.l)
                        .opacity(apparu ? 1 : 0)
                    Spacer(minLength: Espace.s)
                }
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
            // iPad : une colonne centrée, la sphère et la lueur gardent tout l'écran.
            .largeurLisible(Adaptatif.assistant)
            .padding(.horizontal, Espace.bord)
            .padding(.bottom, Espace.s)
        }
        .environment(\.colorScheme, .dark)
        .presentationBackground(.clear)
        .animation(.endry(reduire: reduireAnimations), value: assistant?.cartes ?? [])
        .animation(.spring(response: 0.55, dampingFraction: 0.86), value: compact)
        .task {
            withAnimation(reduireAnimations ? .fonduDoux : .spring(response: 0.7, dampingFraction: 0.82)) { apparu = true }
            let nouvel = app.nouvelAssistant()
            assistant = nouvel
            await nouvel.demarrer()
        }
        .onDisappear { assistant?.arreter() }
        // Commandes dites : « merci, c'est tout » ferme, « ouvre la conversation » passe à l'écrit.
        .onChange(of: assistant?.commande?.id) {
            switch assistant?.commande?.action {
            case .fermer?: fermer()
            case .ouvrirConversation?:
                assistant?.arreter()
                app.ouvrirConversation()
            default: break
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: assistant?.phase)
        .toast(Binding(get: { app.decisions?.toast }, set: { nouveau in if let modele = app.decisions { modele.toast = nouveau } }), decalageBas: Espace.l)
    }

    /// Réponse longue ou carte à l'écran : disposition « lecture » (sphère réduite, texte à gauche, défilant).
    private var compact: Bool {
        guard let assistant else { return false }
        return !assistant.cartes.isEmpty || assistant.reponse.count > 150
    }

    /// L'app reste devinée derrière un voile espresso profond : l'assistant se pose au-dessus, sans rupture.
    private var fond: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color(hex: 0x0E0A06).opacity(0.9)
            // Le halo suit la sphère : au centre, ou en haut à gauche quand la réponse prend la place.
            RadialGradient(colors: [Color(hex: 0x9F722A).opacity(0.22), .clear],
                           center: compact ? UnitPoint(x: 0.12, y: 0.1) : UnitPoint(x: 0.5, y: 0.36),
                           startRadius: 10, endRadius: compact ? 260 : 360)
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
            PastilleClaude(etat: assistant?.etatBureau) {
                Task { await assistant?.poser("Que fait Claude sur le PC en ce moment ?") }
            }
            .disabled(!(assistant?.pret ?? false))
            Spacer()
            if app.conversation != nil {
                Button {
                    assistant?.arreter()
                    app.ouvrirConversation()
                } label: {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.orClair)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(Color.or.opacity(0.2), lineWidth: Espace.filet))
                }
                .accessibilityLabel(Text("Ouvrir la conversation écrite"))
                .accessibilityIdentifier("ouvrir-conversation")
            }
            Button(action: fermer) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.orClair)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(Color.or.opacity(0.2), lineWidth: Espace.filet))
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text("Fermer l’assistant vocal"))
            .accessibilityIdentifier("fermer-assistant")
        }
        .padding(.top, Espace.xs)
    }

    private var sphere: some View {
        OrbeEndry(assistant: assistant)
            .frame(maxWidth: compact ? 64 : 330, maxHeight: compact ? 64 : 330)
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
                case .ecoute:
                    // « J'ai fini » : Endry répond sans attendre le silence.
                    clavier = false
                    assistant?.terminerPhrase()
                default:
                    clavier = false
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(EtatAssistant.libelle(assistant?.phase ?? .preparation)))
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityAction(named: Text("Interrompre")) { assistant?.interrompre() }
            .accessibilityAction(named: Text("J’ai fini, réponds")) { assistant?.terminerPhrase() }
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
                            .font(PoliceAssistant.texte(14, .medium, relativeTo: .subheadline))
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
                .font(PoliceAssistant.texte(16))
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
                CarteContexte(effet: effet, retirer: { assistant?.retirer(effet) },
                              confirmer: { texte in await assistant?.confirmer(effet, texte: texte) },
                              envoiAuto: assistant?.envoisAuto.contains(effet) ?? false,
                              garder: { assistant?.suspendreEnvoiAuto(effet) })
                    .transition(reduireAnimations ? .opacity : .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)))
            }
        }
        .padding(.bottom, Espace.s)
    }
}

// MARK: - Typographie de l'assistant

/// L'assistant parle en SF Pro : net, lisible de loin, taillé pour le texte qui s'écrit en direct.
enum PoliceAssistant {
    static func texte(_ taille: CGFloat, _ poids: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: taille), weight: poids, design: .default)
    }
}

// MARK: - État, transcription

/// Phase de la conversation, en petites capitales espacées, qui se fond d'un état à l'autre.
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
                    .font(PoliceAssistant.texte(14, .medium, relativeTo: .footnote))
                    .foregroundStyle(Color.orClair.opacity(0.8))
                    .multilineTextAlignment(.center)
            } else {
                Text(texte)
                    .font(PoliceAssistant.texte(12, .semibold, relativeTo: .footnote))
                    .textCase(.uppercase)
                    .tracking(2.4)
                    .foregroundStyle(Color.or.opacity(0.85))
            }
        }
        .id(texte)
        .transition(.opacity.combined(with: .offset(y: 4)))
        .animation(.endry(reduire: reduireAnimations), value: texte)
        .accessibilityHidden(true)
    }
}

/// Vos mots s'écrivent pendant que vous parlez, en grand ; quand Endry répond, ils se retirent en petit au-dessus
/// de la réponse, qui s'allume mot à mot au rythme de la voix. Vue séparée : seule elle se redessine.
private struct TranscriptionAssistant: View {
    var assistant: AssistantVocal?
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        let reponse = assistant?.reponse ?? ""
        let enReponse = !reponse.isEmpty
        VStack(spacing: Espace.m) {
            if let assistant, !(assistant.definitif.isEmpty && assistant.provisoire.isEmpty) {
                MotsEnDirect(definitif: assistant.definitif, provisoire: assistant.provisoire,
                             taille: enReponse ? 16 : 30, poids: enReponse ? .medium : .semibold,
                             opacite: enReponse ? 0.5 : 1)
                    .transition(.opacity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(assistant.definitif) \(assistant.provisoire)"))
                    .accessibilityIdentifier("transcription-patron")
            }
            if let assistant, enReponse {
                let (dit, reste) = Self.decouper(reponse, lu: assistant.reponseLue)
                Text("\(Text(dit).foregroundStyle(Color(hex: 0xFBEBD0)))\(Text(reste).foregroundStyle(Color.orClair.opacity(0.28)))")
                    .font(PoliceAssistant.texte(23, .medium, relativeTo: .title3))
                    .tracking(-0.3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .minimumScaleFactor(0.75)
                    .lineLimit(8)
                    .transition(.opacity.combined(with: .offset(y: 10)))
                    .animation(.easeOut(duration: 0.18), value: assistant.reponseLue)
                    .accessibilityLabel(Text(reponse))
                    .accessibilityIdentifier("reponse-assistant")
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.endry(reduire: reduireAnimations), value: enReponse)
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

/// Disposition « lecture » : votre question en petit, puis la réponse alignée à gauche, en texte courant,
/// qui défile doucement (fondu en haut et en bas) ; les mots déjà dits s'allument au rythme de la voix.
private struct ReponseLisible: View {
    var assistant: AssistantVocal?
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        let reponse = assistant?.reponse ?? ""
        ScrollView {
            VStack(alignment: .leading, spacing: Espace.m) {
                if let assistant, !(assistant.definitif.isEmpty && assistant.provisoire.isEmpty) {
                    Text([assistant.definitif, assistant.provisoire].filter { !$0.isEmpty }.joined(separator: " "))
                        .font(PoliceAssistant.texte(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Color.orClair.opacity(0.5))
                        .lineLimit(3)
                        .accessibilityIdentifier("transcription-patron")
                }
                if let assistant, !reponse.isEmpty {
                    let (dit, reste) = TranscriptionAssistant.decouper(reponse, lu: assistant.reponseLue)
                    Text("\(Text(BlocTexte.sansBalises(dit)).foregroundStyle(Color(hex: 0xFBEBD0)))\(Text(BlocTexte.sansBalises(reste)).foregroundStyle(Color.orClair.opacity(0.35)))")
                        .font(PoliceAssistant.texte(19, .regular, relativeTo: .body))
                        .lineSpacing(6)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.easeOut(duration: 0.18), value: assistant.reponseLue)
                        .accessibilityLabel(Text(reponse))
                        .accessibilityIdentifier("reponse-assistant")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Espace.m)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .mask(
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05),
                                   .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
        .animation(.endry(reduire: reduireAnimations), value: reponse.isEmpty)
    }
}

/// Réponse du bureau arrivée : discrète, elle mène au fil complet (écrit, mis en forme, à copier).
private struct LienConversation: View {
    @Environment(ModeleApp.self) private var app
    var agent: String?
    var retirer: () -> Void

    var body: some View {
        HStack(spacing: Espace.s) {
            Button {
                app.ouvrirConversation()
            } label: {
                HStack(spacing: Espace.s) {
                    Image(systemName: agent.flatMap { AgentBureau(nom: $0)?.icone } ?? "text.bubble")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.or)
                        .frame(width: 34, height: 34)
                        .background(Color.or.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(agent.map { "Réponse · \($0)" } ?? "Réponse de l’assistant du bureau")
                            .font(PoliceAssistant.texte(14, .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Color.orClair)
                        Text("Continuer dans la conversation")
                            .font(PoliceAssistant.texte(12, relativeTo: .caption))
                            .foregroundStyle(Color.orClair.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.or.opacity(0.8))
                }
            }
            .buttonStyle(.plain)
            Button(action: retirer) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.orClair.opacity(0.45))
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(Text("Masquer"))
        }
        .padding(.horizontal, Espace.m)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.or.opacity(0.2), lineWidth: Espace.filet))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("carte-claude")
    }
}

/// Chaque mot reconnu apparaît en fondu, en remontant légèrement et en se précisant (flou → net) ;
/// les mots encore provisoires restent plus pâles jusqu'à ce que la reconnaissance les confirme.
private struct MotsEnDirect: View {
    var definitif: String
    var provisoire: String
    var taille: CGFloat
    var poids: Font.Weight
    var opacite: Double
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        let confirmes = Self.mots(definitif)
        let enCours = Self.mots(provisoire)
        let tous = confirmes.map { ($0, true) } + enCours.map { ($0, false) }
        LigneCentree(espacement: taille * 0.28, interligne: taille * 0.18) {
            ForEach(Array(tous.enumerated()), id: \.offset) { index, element in
                Text(element.0)
                    .font(PoliceAssistant.texte(taille, poids, relativeTo: .title))
                    .tracking(-0.4)
                    .foregroundStyle(Color(hex: 0xFBEBD0).opacity((element.1 ? 1 : 0.55) * opacite))
                    .transition(reduireAnimations ? .opacity : .asymmetric(
                        insertion: .modifier(active: MotQuiApparait(etat: 0), identity: MotQuiApparait(etat: 1)),
                        removal: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: tous.count)
        .animation(.endry(reduire: reduireAnimations), value: taille)
    }

    static func mots(_ texte: String) -> [String] {
        texte.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

/// Apparition d'un mot : fondu, légère montée, flou qui se dissipe.
private struct MotQuiApparait: ViewModifier {
    var etat: Double

    func body(content: Content) -> some View {
        content
            .opacity(etat)
            .offset(y: (1 - etat) * 8)
            .blur(radius: (1 - etat) * 6)
    }
}

/// Mots posés ligne à ligne, chaque ligne centrée (comme un sous-titre).
private struct LigneCentree: Layout {
    var espacement: CGFloat
    var interligne: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? .infinity
        let lignes = decouper(subviews, largeur: largeur)
        let hauteur = lignes.reduce(0) { $0 + $1.hauteur } + interligne * CGFloat(max(lignes.count - 1, 0))
        let plusLarge = lignes.map(\.largeur).max() ?? 0
        return CGSize(width: proposal.width ?? plusLarge, height: hauteur)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for ligne in decouper(subviews, largeur: bounds.width) {
            var x = bounds.midX - ligne.largeur / 2
            for index in ligne.indices {
                let taille = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + ligne.hauteur - taille.height), proposal: .unspecified)
                x += taille.width + espacement
            }
            y += ligne.hauteur + interligne
        }
    }

    private struct Ligne {
        var indices: [Int] = []
        var largeur: CGFloat = 0
        var hauteur: CGFloat = 0
    }

    private func decouper(_ subviews: Subviews, largeur: CGFloat) -> [Ligne] {
        var lignes: [Ligne] = []
        var courante = Ligne()
        for (index, vue) in subviews.enumerated() {
            let taille = vue.sizeThatFits(.unspecified)
            let ajout = courante.indices.isEmpty ? taille.width : courante.largeur + espacement + taille.width
            if ajout > largeur, !courante.indices.isEmpty {
                lignes.append(courante)
                courante = Ligne()
            }
            courante.largeur = courante.indices.isEmpty ? taille.width : courante.largeur + espacement + taille.width
            courante.hauteur = max(courante.hauteur, taille.height)
            courante.indices.append(index)
        }
        if !courante.indices.isEmpty { lignes.append(courante) }
        // Garde les dernières lignes : ce que vous venez de dire reste toujours visible.
        return Array(lignes.suffix(4))
    }
}

/// Carte qui surgit pendant la conversation.
struct CarteContexte: View {
    @Environment(ModeleApp.self) private var app
    var effet: ExecuteurOutils.Effet
    var retirer: () -> Void
    /// « Envoyer » / « Transmettre » d'une question ou d'une demande préparée par la voix.
    var confirmer: (String) async -> Void = { _ in }
    /// Envoi direct en cours (réglage « Envoi direct au bureau »).
    var envoiAuto = false
    var garder: () -> Void = {}

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
        case .questionClaude(_, let question, let agent, let message):
            CarteClaude(question: question, reponse: nil, agent: agent, attente: message, retirer: retirer)
        case .questionAConfirmer(let question, let agent, _):
            CarteConfirmation(titre: agent.map { "Question pour l’assistant · \($0)" } ?? "Question pour l’assistant du bureau",
                              texte: question, bouton: "Envoyer",
                              note: "Lecture seule : l’assistant répond, il ne fait rien d’autre.",
                              envoiAuto: envoiAuto, confirmer: confirmer, annuler: retirer, garder: garder)
        case .saisieAConfirmer(let texte):
            CarteConfirmation(titre: "Demande pour le bureau", texte: texte, bouton: "Transmettre",
                              note: "L’assistant prépare ; rien ne part chez un tiers sans votre geste.",
                              envoiAuto: envoiAuto, confirmer: confirmer, annuler: retirer, garder: garder)
        case .reponseClaude(_, _, let agent):
            // La réponse est déjà à l'écran (et dite) : ici, seulement le lien vers le fil complet.
            LienConversation(agent: agent, retirer: retirer)
        case .ouvrirOutil(let nom, let chantierId):
            let outil: OutilTerrain = nom == "bon_livraison" ? .bonLivraison : nom == "releve" ? .releve : .regie
            Button {
                retirer()
                app.fermerAssistant()
                // L'assistant se ferme, puis l'outil s'ouvre en plein écran.
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    app.ouvrirOutil(outil, chantier: chantierId)
                }
            } label: {
                HStack(spacing: Espace.s) {
                    Image(systemName: outil.icone)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.espressoProfond)
                        .frame(width: 40, height: 40)
                        .background(.degradeOr, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ouvrir : \(outil.titre)").styleTexte(15, relativeTo: .subheadline, graisse: .semibold).foregroundStyle(Color.encre)
                        Text(app.chantierPropose(chantierId)?.titre ?? outil.sousTitre).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.bronze)
                }
                .padding(Espace.m)
                .surfaceCarte(rayon: Espace.rayonPetit)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("carte-ouvrir-outil")
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

// MARK: - Claude, sur le PC

/// Pastille « Claude travaille · 2 en cours » : ce que fait l'assistant du bureau, d'un coup d'œil.
/// La toucher demande le détail à voix haute.
private struct PastilleClaude: View {
    var etat: EtatBureau?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(couleur)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(couleur.opacity(0.4), lineWidth: 3).scaleEffect(1.8))
                Text(etat?.libelleCourt ?? "Claude · PC")
                    .font(PoliceAssistant.texte(12, .medium, relativeTo: .caption))
                    .foregroundStyle(Color.orClair.opacity(0.85))
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(Color.or.opacity(0.18), lineWidth: Espace.filet))
        }
        .buttonStyle(.plain)
        .animation(.endry, value: etat?.libelleCourt)
        .accessibilityLabel(Text(etat?.libelleCourt ?? "Claude, l’assistant du PC"))
        .accessibilityHint(Text("Demande à Endry ce que fait Claude en ce moment"))
        .accessibilityIdentifier("pastille-claude")
    }

    private var couleur: Color {
        guard let etat else { return Color.orClair.opacity(0.4) }
        if etat.enPause { return Color(hex: 0xC8764A) }
        return etat.enCours.isEmpty && (etat.etat?.file ?? 0) == 0 ? Color(hex: 0x8FB08A) : Color.or
    }
}

/// Question ou demande préparée par la voix : le patron la relit, la corrige s'il faut, puis confirme.
/// Rien ne part au PC avant ce geste.
struct CarteConfirmation: View {
    var titre: String
    var texte: String
    var bouton: String
    var note: String
    /// Envoi direct en cours : la carte part d'elle-même dans un instant.
    var envoiAuto = false
    var confirmer: (String) async -> Void
    var annuler: () -> Void
    /// Le patron modifie le texte : l'envoi direct s'arrête, il enverra lui-même.
    var garder: () -> Void = {}
    @State private var brouillon = ""
    @State private var enCours = false
    @State private var progression: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            Text(titre)
                .font(PoliceAssistant.texte(11, .semibold, relativeTo: .caption2))
                .textCase(.uppercase)
                .tracking(1.8)
                .foregroundStyle(Color.or)
            // Éditeur à hauteur fixe : pas de champ qui grandit pendant la mise en page de l'écran.
            TextEditor(text: $brouillon)
                .font(PoliceAssistant.texte(17, .medium))
                .foregroundStyle(Color(hex: 0xFBEBD0))
                .tint(Color.or)
                .scrollContentBackground(.hidden)
                .frame(height: 76)
                .padding(Espace.xs)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("texte-a-confirmer")
            if envoiAuto {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Envoi au bureau…")
                        .font(PoliceAssistant.texte(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(Color.or)
                    GeometryReader { geo in
                        Capsule().fill(Color.or).frame(width: geo.size.width * progression, height: 3)
                    }
                    .frame(height: 3)
                }
                .accessibilityIdentifier("envoi-auto")
                .onAppear {
                    progression = 0
                    withAnimation(.linear(duration: 1.4)) { progression = 1 }
                }
            } else {
                Text(note)
                    .font(PoliceAssistant.texte(12, relativeTo: .caption))
                    .foregroundStyle(Color.orClair.opacity(0.55))
            }
            HStack(spacing: Espace.s) {
                Button("Annuler", action: annuler)
                    .font(PoliceAssistant.texte(15, .medium))
                    .foregroundStyle(Color.orClair.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .accessibilityIdentifier("annuler-confirmation")
                Button {
                    enCours = true
                    Task {
                        await confirmer(brouillon)
                        enCours = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if enCours { ProgressView().tint(Color.espresso) }
                        Text(bouton)
                    }
                    .font(PoliceAssistant.texte(15, .semibold))
                    .foregroundStyle(Color.espresso)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.or, in: Capsule())
                }
                .disabled(enCours || brouillon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("confirmer-envoi")
            }
        }
        .padding(Espace.m)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.or.opacity(0.45), lineWidth: 1))
        .onAppear { if brouillon.isEmpty { brouillon = texte } }
        .onChange(of: brouillon) { ancien, nouveau in
            if envoiAuto, !ancien.isEmpty, nouveau != texte { garder() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("carte-confirmation")
    }
}

/// Carte « Assistant » : la question posée au PC (et dans quel domaine), puis sa réponse quand elle arrive.
struct CarteClaude: View {
    var question: String
    var reponse: String?
    var agent: String?
    /// Question partie, réponse au prochain passage de l'assistant (message du PC).
    var attente: String? = nil
    var retirer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            HStack(spacing: 6) {
                Image(systemName: icone)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolEffect(.pulse, isActive: reponse == nil && !Configuration.testsUI)
                Text(agent.map { "Assistant · \($0)" } ?? "Assistant du bureau")
                    .font(PoliceAssistant.texte(11, .semibold, relativeTo: .caption2))
                    .textCase(.uppercase)
                    .tracking(1.8)
                Spacer()
                Button(action: retirer) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .foregroundStyle(Color.orClair.opacity(0.5))
                .accessibilityLabel(Text("Masquer"))
            }
            .foregroundStyle(Color.or)
            Text(question)
                .font(PoliceAssistant.texte(14, .medium, relativeTo: .subheadline))
                .foregroundStyle(Color.orClair.opacity(0.55))
                .lineLimit(2)
            if let reponse {
                ScrollView {
                    Text(reponse)
                        .font(PoliceAssistant.texte(16, .regular))
                        .foregroundStyle(Color(hex: 0xFBEBD0))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 170)
                .scrollBounceBehavior(.basedOnSize)
                .transition(.opacity.combined(with: .offset(y: 6)))
            } else {
                if let attente {
                    Label(attente, systemImage: "clock")
                        .font(PoliceAssistant.texte(13, relativeTo: .footnote))
                        .foregroundStyle(Color.orClair.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: Espace.xs) {
                        ProgressView().controlSize(.small).tint(Color.or)
                        Text("Question transmise ; l’assistant la traite en lecture seule…")
                            .font(PoliceAssistant.texte(13, relativeTo: .footnote))
                            .foregroundStyle(Color.orClair.opacity(0.55))
                    }
                }
            }
        }
        .padding(Espace.m)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.or.opacity(0.22), lineWidth: Espace.filet))
        .animation(.endry, value: reponse)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("carte-claude")
    }

    private var icone: String {
        agent.flatMap { AgentBureau(nom: $0)?.icone } ?? "sparkles"
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
        if Configuration.testsUI {
            // Tests d'interface (simulateur sans GPU) : sphère fixe, sans shader ni lecture des niveaux audio.
            Circle()
                .fill(RadialGradient(colors: [Color.orClair, Color.or, Color(hex: 0x3A2A14)], center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 4, endRadius: 150))
                .scaleEffect(0.76)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            orbe
        }
    }

    private var orbe: some View {
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
        if Configuration.testsUI {
            // Tests d'interface : pas de lueur (shader plein écran trop lent sur le simulateur de la CI).
            Color.clear.allowsHitTesting(false).accessibilityHidden(true)
        } else {
            lueur
        }
    }

    private var lueur: some View {
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
