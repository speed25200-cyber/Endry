import EndryKit
import SwiftUI
import UIKit

/// « Conversation » : l'endroit réservé pour parler au bureau, par écrit ou en dictée, comme une session
/// Claude ouverte sur le PC. Les questions partent tout de suite (le bureau s'en occupe) ; les demandes partent en
/// saisie et se suivent ici jusqu'au résultat. Rien ne part chez un tiers sans le geste du patron à l'écran.
struct ConversationView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @Bindable var modele: ModeleConversation
    @State private var texte = ""
    @State private var nature: MessageConversation.Nature = .question
    /// Le patron a choisi lui-même Question / Demande : on ne devine plus.
    @State private var natureChoisie = false
    @State private var dictee = Dictee()
    /// Texte présent avant la dictée : la dictée s'y ajoute.
    @State private var avantDictee = ""
    /// Le message en cours vient (au moins en partie) de la dictée.
    @State private var dicte = false
    @State private var confirmerEffacement = false
    @FocusState private var clavier: Bool

    private static let suggestions = [
        "Qu’est-ce qui est arrivé par e-mail aujourd’hui ?",
        "Où en est la préparation de la commande de matériel ?",
        "Quelles offres attendent une réponse du client ?",
        "Résume-moi la semaine des chantiers.",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { defilement in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Espace.l) {
                        if modele.messages.isEmpty {
                            accueil
                        } else {
                            let debuts = debutsDeFil
                            ForEach(modele.messages) { message in
                                if debuts.contains(message.id) {
                                    SeparateurConversation(date: message.le)
                                }
                                MessageView(message: message, question: question(de: message), relancer: {
                                    Task { await modele.relancer(String(message.id.dropFirst(2))) }
                                }, suite: message.id == derniereReponse ? { suite in
                                    // Envoyée telle quelle, sans toucher au brouillon du champ.
                                    Task { await modele.envoyer(suite, nature: .question) }
                                } : nil)
                                .id(message.id)
                            }
                        }
                        Color.clear.frame(height: 1).id("fin")
                    }
                    .largeurLisible()
                    .padding(.horizontal, Espace.bord)
                    .padding(.top, Espace.s)
                    .padding(.bottom, Espace.m)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: modele.messages.count) {
                    withAnimation(.endry) { defilement.scrollTo("fin", anchor: .bottom) }
                }
                .onChange(of: modele.messages.last?.etat) {
                    withAnimation(.endry) { defilement.scrollTo("fin", anchor: .bottom) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { composeur }
            }
            .background(FondAmbiant())
            .navigationTitle("Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { menuFil }
                ToolbarItem(placement: .principal) { enTete }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { fermer() }
                        .accessibilityIdentifier("fermer-conversation")
                }
            }
            .confirmationDialog("Effacer toute la conversation ?", isPresented: $confirmerEffacement, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) { modele.effacer() }
            } message: {
                Text("Le fil est effacé de l’iPhone. Ce que le bureau a déjà fait reste dans « Fait récemment ».")
            }
        }
        .task { await modele.verifierEnAttente() }
        // Petit signe au toucher quand la réponse du bureau arrive.
        .sensoryFeedback(.impact(weight: .light), trigger: modele.derniereArrivee?.id)
        .onDisappear { dictee.arreter() }
        .onChange(of: dictee.transcription) { _, dit in
            guard dictee.ecoute, !dit.isEmpty else { return }
            texte = avantDictee.isEmpty ? dit : avantDictee + " " + dit
            dicte = true
        }
        .onChange(of: texte) { _, nouveau in
            guard !natureChoisie else { return }
            nature = ModeleConversation.natureProbable(nouveau)
        }
    }

    /// Dernière réponse reçue du fil en cours : elle porte les relances rapides.
    private var derniereReponse: String? {
        guard let derniere = modele.messages.last, derniere.role == .assistant, derniere.etat == .recu,
              derniere.conversation == modele.identifiant else { return nil }
        return derniere.id
    }

    /// Messages qui ouvrent un nouveau fil (séparateur au-dessus).
    private var debutsDeFil: Set<String> {
        var debuts: Set<String> = []
        var precedent: String?
        for m in modele.messages {
            if let precedent, precedent != m.conversation { debuts.insert(m.id) }
            precedent = m.conversation
        }
        return debuts
    }

    private func question(de message: MessageConversation) -> MessageConversation? {
        guard message.role != .patron else { return nil }
        return modele.messages.first { MessageConversation.idReponse($0.id) == message.id }
    }

    // MARK: En-tête

    private var enTete: some View {
        VStack(spacing: 1) {
            Text("Conversation").styleTexte(16, graisse: .semibold).foregroundStyle(Color.encre)
            Menu {
                Button {
                    modele.choisirAgent(id: nil, nom: nil)
                } label: {
                    Label("L’assistant choisit le domaine", systemImage: modele.agentId == nil ? "checkmark" : "sparkles")
                }
                ForEach(app.agents?.agents ?? []) { agent in
                    Button {
                        modele.choisirAgent(id: agent.id, nom: agent.nom)
                    } label: {
                        Label(agent.nom, systemImage: modele.agentId == agent.id ? "checkmark" : (agent.connu?.icone ?? "person.crop.circle"))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle().fill(couleurEtat).frame(width: 6, height: 6)
                    Text(modele.agentNom.map { "Assistant · \($0)" } ?? (app.agents?.etat?.libelleCourt ?? "Assistant du bureau"))
                        .styleTexte(12, relativeTo: .caption, graisse: .medium)
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Color.encreDouce)
            }
            .accessibilityIdentifier("choix-agent")
        }
    }

    private var couleurEtat: Color {
        guard let etat = app.agents?.etat else { return Color.encrePale.opacity(0.5) }
        if etat.enPause || !etat.enService() { return Color.ambre }
        return Color.sauge
    }

    private var menuFil: some View {
        Menu {
            Button {
                modele.nouvelleConversation()
            } label: {
                Label("Nouvelle conversation", systemImage: "square.and.pencil")
            }
            Button(role: .destructive) {
                confirmerEffacement = true
            } label: {
                Label("Effacer la conversation", systemImage: "trash")
            }
            .disabled(modele.messages.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text("Options de la conversation"))
    }

    // MARK: Accueil

    private var accueil: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Color.bronze)
                .padding(.top, Espace.xl)
            Text("Parlez au bureau").styleTitre(30, relativeTo: .title).foregroundStyle(Color.encre)
            Text("Écrivez ou dictez : l’assistant du PC répond ici, tout de suite, comme une session ouverte. Il garde le fil de la conversation.")
                .styleTexte(15).foregroundStyle(Color.encreDouce)
                .fixedSize(horizontal: false, vertical: true)
            Label("Le bureau s’en occupe tout de suite : il répond, prépare, corrige, traite les e-mails… Vous suivez le travail ici. Tout envoi reste une décision à glisser.",
                  systemImage: "lock.shield")
                .styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encrePale)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Espace.xs) {
                ForEach(Array(Self.suggestions.enumerated()), id: \.offset) { index, suggestion in
                    Button {
                        Task { await envoyer(suggestion, nature: .question) }
                    } label: {
                        HStack(spacing: Espace.s) {
                            Text(suggestion).styleTexte(15).foregroundStyle(Color.encre)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.bronze)
                        }
                        .padding(.horizontal, Espace.m)
                        .padding(.vertical, Espace.s)
                        .surfaceCarte(rayon: Espace.rayonPetit)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("suggestion-conversation-\(index)")
                }
            }
            .padding(.top, Espace.xs)
        }
    }

    // MARK: Composeur

    private var vide: Bool { texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var composeur: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            if case .refuse(let raison) = dictee.etat {
                Text(raison).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.rouille)
            } else if case .indisponible(let raison) = dictee.etat {
                Text(raison).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.rouille)
            }
            VStack(alignment: .leading, spacing: Espace.xs) {
                TextField("", text: $texte, prompt: Text(dictee.ecoute ? "J’écoute…" : "Écrire au bureau…").foregroundStyle(Color.encrePale),
                          axis: .vertical)
                    .styleTexte(16)
                    .foregroundStyle(Color.encre)
                    .tint(Color.bronze)
                    .lineLimit(1...6)
                    .focused($clavier)
                    .accessibilityIdentifier("champ-conversation")
                HStack(spacing: Espace.xs) {
                    choixNature
                    Spacer(minLength: 0)
                    boutonDictee
                    boutonEnvoyer
                }
            }
            .padding(.horizontal, Espace.m)
            .padding(.top, Espace.s)
            .padding(.bottom, Espace.xs)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(clavier || dictee.ecoute ? Color.bronze.opacity(0.5) : Color.filet, lineWidth: 1))
            .shadow(color: Color.ombre, radius: 16, y: 6)
            .animation(.endryVif, value: clavier)
        }
        .largeurLisible()
        .padding(.horizontal, Espace.bord)
        .padding(.top, Espace.xs)
        .padding(.bottom, Espace.xs)
        .background(alignment: .bottom) {
            LinearGradient(colors: [Color.fond.opacity(0), Color.fond], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    /// Question ou Demande (le bureau prépare) : deviné d'après la tournure, modifiable.
    private var choixNature: some View {
        Button {
            natureChoisie = true
            nature = nature == .question ? .demande : .question
        } label: {
            HStack(spacing: 5) {
                Image(systemName: nature == .question ? "questionmark.bubble" : "hammer")
                    .font(.system(size: 12, weight: .semibold))
                Text(nature == .question ? "Question" : "Demande")
                    .styleTexte(13, relativeTo: .footnote, graisse: .semibold)
            }
            .foregroundStyle(nature == .question ? Color.encreDouce : Color.bronze)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(nature == .question ? Color.surfaceCreuse : Color.or.opacity(0.25), in: Capsule())
            .contentTransition(.opacity)
        }
        .buttonStyle(.plain)
        .animation(.endryVif, value: nature)
        .accessibilityLabel(Text(nature == .question ? "Question : le bureau s’en occupe et répond" : "Demande : le bureau prépare"))
        .accessibilityHint(Text("Touchez pour changer"))
        .accessibilityIdentifier("mode-conversation")
    }

    private var boutonDictee: some View {
        Button {
            if dictee.ecoute {
                dictee.arreter()
            } else {
                avantDictee = texte.trimmingCharacters(in: .whitespacesAndNewlines)
                clavier = false
                Task { await dictee.demarrer() }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.or.opacity(dictee.ecoute ? 0.35 : 0))
                    .scaleEffect(1 + CGFloat(dictee.niveau) * 0.5)
                    .animation(.endryVif, value: dictee.niveau)
                Image(systemName: dictee.ecoute ? "stop.fill" : "mic")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(dictee.ecoute ? Color.bronze : Color.encreDouce)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: dictee.ecoute)
        .accessibilityLabel(Text(dictee.ecoute ? "Arrêter la dictée" : "Dicter"))
        .accessibilityIdentifier("dicter-conversation")
    }

    private var boutonEnvoyer: some View {
        Button {
            let envoi = texte
            Task { await envoyer(envoi, nature: nature) }
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.espresso)
                .frame(width: 34, height: 34)
                .background(.degradeOr, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(vide)
        .opacity(vide ? 0.35 : 1)
        .scaleEffect(vide ? 0.9 : 1)
        .animation(.endryVif, value: vide)
        // Clavier de l'iPad : ⌘↩ envoie.
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel(Text(nature == .question ? "Envoyer la question" : "Transmettre la demande"))
        .accessibilityIdentifier("envoyer-conversation")
    }

    private func envoyer(_ contenu: String, nature: MessageConversation.Nature) async {
        let propre = contenu.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return }
        dictee.arreter()
        let source: MessageConversation.Source = dicte ? .dictee : .ecrit
        texte = ""
        avantDictee = ""
        dicte = false
        natureChoisie = false
        self.nature = .question
        await modele.envoyer(propre, nature: nature, source: source)
    }
}

// MARK: - Messages

/// Un message du fil : le patron à droite, l'assistant en pleine largeur, comme une conversation Claude.
private struct MessageView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    var message: MessageConversation
    /// Pour une réponse ou une note : le message du patron auquel elle répond.
    var question: MessageConversation?
    var relancer: () -> Void
    /// Relances rapides (dernière réponse seulement).
    var suite: ((String) -> Void)? = nil

    private static let relances = ["Plus de détails", "Résume en une phrase", "Et ensuite ?"]

    var body: some View {
        switch message.role {
        case .patron: bulle
        case .assistant: reponse
        case .note: note
        }
    }

    private var bulle: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.texte)
                    .styleTexte(16)
                    .foregroundStyle(Color.encre)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.surfaceCreuse, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                HStack(spacing: 4) {
                    if message.nature == .demande { Image(systemName: "hammer") }
                    if message.source != .ecrit { Image(systemName: message.source == .voix ? "waveform" : "mic") }
                    Text(legende)
                }
                .styleTexte(11, relativeTo: .caption2)
                .foregroundStyle(Color.encrePale)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("message-patron")
    }

    private var legende: String {
        var morceaux: [String] = []
        if message.nature == .demande { morceaux.append("Demande") }
        if let agent = message.agent { morceaux.append(agent) }
        morceaux.append(DateEndry.heure(message.le))
        return morceaux.joined(separator: " · ")
    }

    private var reponse: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            HStack(spacing: 6) {
                Image(systemName: message.agent.flatMap { AgentBureau(nom: $0)?.icone } ?? "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text(message.agent.map { "Assistant · \($0)" } ?? "Assistant du bureau")
                    .styleTexte(12, relativeTo: .caption, graisse: .semibold)
                if message.etat == .recu {
                    Text("· " + DateEndry.heure(message.le)).styleTexte(12, relativeTo: .caption)
                        .foregroundStyle(Color.encrePale)
                }
            }
            .foregroundStyle(Color.bronze)
            switch message.etat {
            case .attente:
                Reflexion(depuis: question?.le ?? message.le, message: message.message)
            case .differe:
                Label(message.message ?? BureauClaude.reponseAVenir, systemImage: "clock")
                    .styleTexte(14).foregroundStyle(Color.encreDouce)
                    .fixedSize(horizontal: false, vertical: true)
            case .erreur:
                VStack(alignment: .leading, spacing: Espace.xs) {
                    Label(message.texte, systemImage: "exclamationmark.triangle")
                        .styleTexte(14).foregroundStyle(Color.rouille)
                        .fixedSize(horizontal: false, vertical: true)
                    // Un compte rendu du bureau (« pas abouti ») ne se renvoie pas d'ici.
                    if !message.id.hasPrefix("B:") {
                        Button("Réessayer", action: relancer)
                            .styleTexte(14, graisse: .semibold)
                            .tint(Color.bronze)
                    }
                }
            case .recu, .envoye:
                TexteRiche(texte: message.texte)
                    .accessibilityIdentifier("reponse-conversation")
                actions
                if let reference = message.decisionReference {
                    Button {
                        fermer()
                        app.ouvrir(reference: reference)
                    } label: {
                        let question = reference.uppercased().hasPrefix("Q-")
                        let libelle: String = question ? "Répondre à la question \(reference)" : "Voir la décision \(reference) à valider"
                        Label(libelle, systemImage: question ? "text.bubble" : "checkmark.seal")
                            .styleTexte(14, graisse: .semibold)
                    }
                    .buttonStyle(BoutonSecondaire())
                    .padding(.top, Espace.xxs)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if message.etat == .recu {
                Button {
                    UIPasteboard.general.string = message.texte
                } label: {
                    Label("Copier", systemImage: "doc.on.doc")
                }
            }
        }
    }

    /// Écouter, copier, partager ; relances rapides sous la dernière réponse.
    @ViewBuilder
    private var actions: some View {
        let lisible = ResumeOral.lisible(message.texte)
        HStack(spacing: Espace.m) {
            Button {
                app.lecteur.basculer(lisible)
            } label: {
                Image(systemName: app.lecteur.enLecture ? "stop.circle" : "speaker.wave.2")
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(Text(app.lecteur.enLecture ? "Arrêter la lecture" : "Écouter la réponse"))
            Button {
                UIPasteboard.general.string = lisible
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .accessibilityLabel(Text("Copier la réponse"))
            ShareLink(item: lisible) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel(Text("Partager la réponse"))
            Spacer(minLength: 0)
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color.encrePale)
        .buttonStyle(.plain)
        .padding(.top, 2)
        if let suite {
            ScrollView(.horizontal) {
                HStack(spacing: Espace.xs) {
                    ForEach(Self.relances, id: \.self) { relance in
                        Button { suite(relance) } label: {
                            Text(relance)
                                .styleTexte(13, relativeTo: .footnote, graisse: .medium)
                                .foregroundStyle(Color.bronze)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Color.or.opacity(0.14), in: Capsule())
                                .overlay(Capsule().stroke(Color.bronze.opacity(0.25), lineWidth: Espace.filet))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.top, Espace.xxs)
            .accessibilityIdentifier("relances-conversation")
        }
    }

    /// Demande transmise : l'avancement vient du suivi (« Fait récemment »), jusqu'au résultat.
    private var note: some View {
        let action = question.flatMap { q in
            app.suiviActions?.actions.first { a in
                a.etapes.first?.detail == q.texteEnvoye || a.etapes.first?.detail == q.texte
            }
        }
        return VStack(alignment: .leading, spacing: Espace.xs) {
            if let action {
                Button {
                    fermer()
                    app.ouvrirSuivi(action.id)
                } label: {
                    HStack(alignment: .top, spacing: Espace.s) {
                        PastilleEtatSuivi(etat: action.etat, taille: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.etat.libelle).styleTexte(14, graisse: .semibold).foregroundStyle(Color.encre)
                            Text(action.ligneResultat).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.encrePale)
                    }
                    .padding(Espace.s)
                    .surfaceCarte(rayon: Espace.rayonPetit)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("suivi-demande")
            } else {
                Label(message.texte, systemImage: message.etat == .erreur ? "exclamationmark.triangle" : "tray.and.arrow.up")
                    .styleTexte(13, relativeTo: .footnote)
                    .foregroundStyle(message.etat == .erreur ? Color.rouille : Color.encreDouce)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// « L'assistant réfléchit… » : trois points qui respirent et le temps écoulé.
private struct Reflexion: View {
    var depuis: Date
    var message: String?
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        HStack(spacing: Espace.s) {
            if reduireAnimations || Configuration.testsUI {
                points(0)
            } else {
                TimelineView(.periodic(from: .now, by: 0.35)) { contexte in
                    points(Int(contexte.date.timeIntervalSinceReferenceDate / 0.35) % 3)
                }
            }
            if Configuration.testsUI {
                // Tests d'interface : rien qui se redessine en continu (l'app doit pouvoir être « au repos »).
                libelle(0)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { contexte in
                    libelle(max(0, Int(contexte.date.timeIntervalSince(depuis))))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reflexion-conversation")
    }

    private func libelle(_ secondes: Int) -> some View {
        Text(message ?? (secondes < 4 ? "L’assistant réfléchit…" : "L’assistant réfléchit… \(secondes) s"))
            .styleTexte(14)
            .foregroundStyle(Color.encreDouce)
            .monospacedDigit()
    }

    private func points(_ actif: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.bronze.opacity(i == actif ? 0.9 : 0.3))
                    .frame(width: 6, height: 6)
                    .scaleEffect(i == actif ? 1.15 : 1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: actif)
    }
}

/// Fil précédent / nouveau fil (après 30 min de silence ou « Nouvelle conversation »).
private struct SeparateurConversation: View {
    var date: Date

    var body: some View {
        HStack(spacing: Espace.s) {
            Rectangle().fill(Color.filet).frame(height: 1)
            Text("Nouvelle conversation · \(DateEndry.heure(date))")
                .styleTexte(11, relativeTo: .caption2, graisse: .medium)
                .foregroundStyle(Color.encrePale)
                .fixedSize()
            Rectangle().fill(Color.filet).frame(height: 1)
        }
        .padding(.vertical, Espace.xs)
        .accessibilityHidden(true)
    }
}

/// Réponse du bureau, mise en forme : titres, listes, gras et liens (Markdown du PC), texte sélectionnable.
struct TexteRiche: View {
    var texte: String
    var taille: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            ForEach(Array(BlocTexte.decouper(texte).enumerated()), id: \.offset) { _, bloc in
                switch bloc {
                case .titre(let t):
                    Text(Self.enLigne(t)).styleTexte(taille + 1, graisse: .semibold).foregroundStyle(Color.encre)
                        .padding(.top, Espace.xxs)
                case .paragraphe(let t):
                    Text(Self.enLigne(t)).styleTexte(taille).foregroundStyle(Color.encre).lineSpacing(3)
                case .puce(let t):
                    ligne(marque: "•", t)
                case .numero(let n, let t):
                    ligne(marque: "\(n).", t)
                case .code(let t):
                    Text(t)
                        .font(.system(size: taille - 2, design: .monospaced))
                        .foregroundStyle(Color.encre)
                        .padding(Espace.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surfaceCreuse, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .tint(Color.bronze)
    }

    private func ligne(marque: String, _ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Espace.xs) {
            Text(marque).styleTexte(taille, graisse: .semibold).foregroundStyle(Color.bronze)
                .frame(minWidth: 14, alignment: .leading)
            Text(Self.enLigne(t)).styleTexte(taille).foregroundStyle(Color.encre).lineSpacing(3)
        }
    }

    static func enLigne(_ t: String) -> AttributedString {
        (try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t)
    }
}
