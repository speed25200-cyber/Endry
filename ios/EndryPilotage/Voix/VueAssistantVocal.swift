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
    /// Début de la phase en cours : le chronomètre de l'anneau repart à chaque phase.
    @State private var debutPhase = Date()
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
            // Une seule disposition, jamais deux superposées : quand une réponse ou une carte arrive, l'anneau rétrécit
            // simplement et le texte prend la place. Aucun fondu croisé, aucun mot animé un par un.
            VStack(spacing: 0) {
                barreHaute
                    .opacity(apparu ? 1 : 0)
                sphere
                    .frame(height: compact ? 128 : 300)
                    .frame(maxWidth: .infinity)
                    .padding(.top, compact ? Espace.xs : Espace.l)
                infos
                    .opacity(apparu ? 1 : 0)
                ZoneTexte(assistant: assistant)
                    .frame(maxHeight: .infinity)
                    .padding(.top, Espace.s)
                    .contentShape(Rectangle())
                    // Toucher le texte pendant qu'Endry parle l'interrompt (comme la sphère).
                    .onTapGesture {
                        if assistant?.phase == .parole { assistant?.interrompre() } else { clavier = false }
                    }
                cartes
                if assistant?.cartes.isEmpty ?? true, !(assistant?.reponseAffichee ?? false), !clavier {
                    suggestions
                        .padding(.bottom, Espace.s)
                        .transition(.opacity)
                }
                champQuestion
                    .opacity(apparu ? 1 : 0)
            }
            // iPad : une colonne centrée, la sphère et la lueur gardent tout l'écran.
            .largeurLisible(Adaptatif.assistant)
            .padding(.horizontal, Espace.bord)
            .padding(.bottom, Espace.s)
        }
        // Glisser vers le bas depuis le haut de l'écran : fermer (en plus du bouton).
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { geste in
                let vertical = geste.translation.height
                if geste.startLocation.y < 320, vertical > 90, abs(geste.translation.width) < vertical { fermer() }
            }
        )
        .environment(\.colorScheme, .dark)
        .presentationBackground(.clear)
        .animation(.endry(reduire: reduireAnimations), value: assistant?.cartes ?? [])
        .animation(.easeInOut(duration: 0.3), value: compact)
        .task {
            withAnimation(reduireAnimations ? .fonduDoux : .spring(response: 0.42, dampingFraction: 0.9)) { apparu = true }
            let nouvel = app.nouvelAssistant()
            assistant = nouvel
            // Laisse passer la première image de l'apparition ; le son démarre ensuite, hors du fil principal.
            await Task.yield()
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
        .onChange(of: assistant?.phase) { debutPhase = Date() }
        .toast(Binding(get: { app.decisions?.toast }, set: { nouveau in if let modele = app.decisions { modele.toast = nouveau } }), decalageBas: Espace.l)
    }

    /// Réponse longue ou carte à l'écran : disposition « lecture » (sphère réduite, texte à gauche, défilant).
    private var compact: Bool {
        guard let assistant else { return false }
        return !assistant.cartes.isEmpty || assistant.reponseLongue
    }

    /// Maison Endry : brun profond, un halo crème à peine posé autour de l'anneau.
    private var fond: some View {
        ZStack {
            Color.fond
            RadialGradient(colors: [Color.signal.opacity(0.08), .clear],
                           center: compact ? UnitPoint(x: 0.12, y: 0.1) : UnitPoint(x: 0.5, y: 0.36),
                           startRadius: 10, endRadius: compact ? 240 : 320)
        }
        .opacity(apparu ? 1 : 0)
        .ignoresSafeArea()
        .onTapGesture { clavier = false }
    }

    /// Le micro est rendu tout de suite (l'arrêt se fait hors du fil principal), puis un fondu court et l'écran part.
    /// Fermer : l'écran part à l'instant, sans attendre ni le son ni une animation ; le micro et la voix
    /// s'arrêtent ensuite, hors du fil principal. Rien ne peut retenir l'écran ouvert.
    private func fermer() {
        clavier = false
        app.fermerAssistant()
        assistant?.arreter()
    }

    // MARK: - Morceaux

    private var barreHaute: some View {
        HStack(spacing: Espace.xs) {
            HStack(spacing: 8) {
                PointVeille(couleur: .sauge, actif: assistant?.pret ?? false)
                Text(ReglageVoix.relaisBureau ? "Relais direct · bureau" : "Endry · assistant")
                    .font(Police.mono(12))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(Color.encre)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .verreMaison(Capsule())
            .accessibilityElement(children: .combine)
            Spacer()
            ConteneurVerre {
                HStack(spacing: Espace.xs) {
                    if app.conversation != nil {
                        BoutonRondVerre(libelle: "Ouvrir la conversation écrite", identifiant: "ouvrir-conversation") {
                            assistant?.arreter()
                            app.ouvrirConversation()
                        } contenu: {
                            Image(systemName: "text.bubble").font(.system(size: 15, weight: .regular))
                        }
                    }
                    // Fermer : grande zone de toucher, verre interactif (comme les autres boutons ronds de l'app).
                    BoutonRondVerre(libelle: "Fermer l’assistant vocal", identifiant: "fermer-assistant", action: fermer) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    }
                    .padding(6)
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded { fermer() })
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(.top, Espace.xs)
    }

    /// État et moteur, une ligne centrée sous l'anneau (aides selon le réglage).
    private var infos: some View {
        VStack(spacing: 4) {
            if let nom = assistant?.nomMoteur, !nom.isEmpty {
                Label(nom, systemImage: nom.contains("Apple Intelligence") ? "sparkles" : "waveform")
                    .font(Police.mono(11.5))
                    .foregroundStyle(Color.encreDouce.opacity(0.8))
                    .lineLimit(1)
                    .accessibilityLabel(Text("Moteur vocal : \(nom)"))
            }
            if assistant?.phase == .parole, assistant?.nomMoteur.contains("continue") == true {
                Text("Parlez pour l’interrompre")
                    .font(PoliceAssistant.texte(12, .medium, relativeTo: .caption))
                    .foregroundStyle(Color.encreDouce)
            }
            if assistant?.phase == .ecoute, ReglageVoix.reponseAuToucher {
                Text("Touchez l’anneau quand vous avez fini")
                    .font(PoliceAssistant.texte(12, .medium, relativeTo: .caption))
                    .foregroundStyle(Color.encreDouce)
                    .accessibilityIdentifier("aide-toucher-sphere")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var sphere: some View {
        AnneauVoix(assistant: assistant, debut: debutPhase)
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(apparu ? 1 : 0.6)
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
                            .font(PoliceAssistant.texte(14, .regular, relativeTo: .subheadline))
                            .foregroundStyle(Color.encre)
                            .padding(.horizontal, Espace.m)
                            .frame(minHeight: 40)
                            .verreMaison(Capsule())
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
            TextField("", text: $question, prompt: Text("Écrire à Endry…").foregroundStyle(Color.encreDouce))
                .font(PoliceAssistant.texte(16))
                .foregroundStyle(Color.encre)
                .tint(Color.signal)
                .focused($clavier)
                .submitLabel(.send)
                .onSubmit(envoyerQuestion)
                .padding(.leading, Espace.m)
                .padding(.vertical, 13)
                .accessibilityIdentifier("champ-assistant")
            Button(action: envoyerQuestion) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.boutonTexte)
                    .frame(width: 40, height: 40)
                    .background(Color.bouton, in: Circle())
            }
            .disabled(vide)
            .opacity(vide ? 0.35 : 1)
            .scaleEffect(vide ? 0.9 : 1)
            .animation(.endryVif, value: vide)
            .padding(.trailing, 6)
            .accessibilityLabel(Text("Envoyer la question"))
            .accessibilityIdentifier("envoyer-question")
        }
        .verreMaison(Capsule())
        .overlay(Capsule().strokeBorder(Color.signal.opacity(clavier ? 0.45 : 0), lineWidth: Espace.filet))
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

/// Le texte de l'échange, en deux blocs seulement (jamais un mot par vue) : ce que dit le patron, puis la réponse,
/// dont la partie déjà dite s'allume au fil de la voix. Défile quand la réponse est longue ; aucune animation de
/// mise en page : le texte ne peut ni se chevaucher ni déborder.
private struct ZoneTexte: View {
    var assistant: AssistantVocal?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espace.m) {
                if let assistant, !(assistant.definitif.isEmpty && assistant.provisoire.isEmpty) {
                    let enReponse = !assistant.reponse.isEmpty
                    let espace = assistant.definitif.isEmpty || assistant.provisoire.isEmpty ? "" : " "
                    Text("\(Text(assistant.definitif).foregroundStyle(Color.encre.opacity(enReponse ? 0.55 : 1)))\(Text(espace))\(Text(assistant.provisoire).foregroundStyle(Color.encre.opacity(enReponse ? 0.35 : 0.5)))")
                        .font(PoliceAssistant.texte(enReponse ? 15 : 24, enReponse ? .medium : .regular, relativeTo: .title3))
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(assistant.definitif) \(assistant.provisoire)"))
                        .accessibilityIdentifier("transcription-patron")
                }
                if let assistant, !assistant.reponse.isEmpty {
                    let (dit, reste) = Self.decouper(assistant.reponse, lu: assistant.reponseLue)
                    Text("\(Text(BlocTexte.sansBalises(dit)).foregroundStyle(Color.encre))\(Text(BlocTexte.sansBalises(reste)).foregroundStyle(Color.encre.opacity(0.4)))")
                        .font(PoliceAssistant.texte(20, .regular, relativeTo: .body))
                        .lineSpacing(5)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(Text(assistant.reponse))
                        .accessibilityIdentifier("reponse-assistant")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Espace.xs)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.top)
        // Le texte change sans animation de mise en page.
        .transaction { $0.animation = nil }
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
                        // La voix affiche la carte ; seul le glissement à l'écran dit « Oui ».
                        agir: { action, consignes, geste in
                            let ok = await modele.agir(action, sur: carte, consignes: consignes, geste: geste)
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
                              note: "Le bureau s’en occupe tout de suite ; tout envoi reste une décision à glisser.",
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
    /// Question partie ; message du PC s'il y en a un (hors horaires).
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
                        Text(BureauClaude.enTraitement)
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
