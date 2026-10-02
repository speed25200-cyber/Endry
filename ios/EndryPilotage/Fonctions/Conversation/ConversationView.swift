import EndryKit
import SwiftUI
import UIKit

/// « Conversation » avec le bureau, en plein écran (l'app derrière ne se dessine plus) : comme une session Claude
/// ouverte sur le PC. L'écran ne montre que le fil en cours ; « Nouvelle conversation » repart d'une page blanche
/// et les fils précédents restent dans l'historique. L'en-tête montre en direct ce que fait le bureau.
/// Rien ne part chez un tiers sans le geste du patron à l'écran.
struct ConversationView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @Bindable var modele: ModeleConversation
    @State private var historique = false
    @FocusState private var clavier: Bool

    private static let suggestions = [
        "Qu’est-ce qui est arrivé par e-mail aujourd’hui ?",
        "Où en est la préparation de la commande de matériel ?",
        "Quelles offres attendent une réponse du client ?",
        "Résume-moi la semaine des chantiers.",
    ]

    var body: some View {
        let fil = modele.filCourant
        // Index calculés une fois par rendu (et non une recherche par message) : le fil reste fluide.
        let questions = Dictionary(fil.filter { $0.role == .patron }.map { (MessageConversation.idReponse($0.id), $0) },
                                   uniquingKeysWith: { premier, _ in premier })
        let derniere = Self.derniereReponse(fil, identifiant: modele.identifiant)
        VStack(spacing: 0) {
            barreHaute
            ScrollViewReader { defilement in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if fil.isEmpty {
                            accueil
                        } else {
                            ForEach(fil) { message in
                                MessageView(message: message, question: questions[message.id],
                                            activite: activite(pour: message),
                                            relancer: { Task { await modele.relancer(String(message.id.dropFirst(2))) } },
                                            suite: message.id == derniere ? { suite in
                                                // Envoyée telle quelle, sans toucher au brouillon du champ.
                                                Task { await modele.envoyer(suite, nature: .question) }
                                            } : nil)
                                    .id(message.id)
                            }
                        }
                        Color.clear.frame(height: 1).id("fin")
                    }
                    .largeurLisible()
                    .padding(.horizontal, 18)
                    .padding(.top, Espace.m)
                    .padding(.bottom, Espace.m)
                    .verrouillerLargeur()
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: fil.count) {
                    withAnimation(.endry) { defilement.scrollTo("fin", anchor: .bottom) }
                }
                .onChange(of: fil.last?.etat) {
                    withAnimation(.endry) { defilement.scrollTo("fin", anchor: .bottom) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { ComposeurConversation(modele: modele, clavier: $clavier) }
            }
        }
        .background(FondMaison(photo: nil))
        .sheet(isPresented: $historique) {
            HistoriqueConversations(modele: modele)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            // Connexion au PC réchauffée dès l'ouverture : la première question part sans poignée de main.
            async let chaud: Void = modele.prechauffer()
            await modele.verifierEnAttente()
            await chaud
        }
        // Petit signe au toucher quand la réponse du bureau arrive.
        .sensoryFeedback(.impact(weight: .light), trigger: modele.derniereArrivee?.id)
    }

    /// Dernière réponse reçue du fil en cours : elle porte les relances rapides.
    static func derniereReponse(_ fil: [MessageConversation], identifiant: String) -> String? {
        guard let derniere = fil.last, derniere.role == .assistant, derniere.etat == .recu,
              derniere.conversation == identifiant else { return nil }
        return derniere.id
    }

    /// Ce que fait le bureau pendant qu'une réponse est attendue (agent concerné, ou celui qui travaille).
    private func activite(pour message: MessageConversation) -> String? {
        guard message.role == .assistant, message.etat == .attente, let agents = app.agents, agents.enDirect else { return nil }
        let occupes = agents.agents.filter { $0.etat == .occupe && $0.tache != nil }
        let agent = occupes.first { $0.nom == message.agent } ?? occupes.first
        guard let agent, let tache = agent.tache else { return nil }
        return "\(agent.nom) · \(tache.prefix(1).lowercased())\(tache.dropFirst())"
    }

    // MARK: En-tête

    private var barreHaute: some View {
        ZStack {
            VStack(spacing: 3) {
                Text("Le bureau")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.encre)
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
                    HStack(spacing: 6) {
                        PointVeille(couleur: couleurEtat, actif: enTravail)
                        Text(statut)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Color.encreDouce)
                    .frame(maxWidth: 230)
                }
                .accessibilityIdentifier("choix-agent")
            }
            HStack(spacing: 8) {
                BoutonRondVerre(libelle: "Fermer la conversation", identifiant: "fermer-conversation") {
                    fermer()
                } contenu: {
                    Image(systemName: "chevron.down").font(.system(size: 15, weight: .medium))
                }
                Spacer()
                BoutonRondVerre(libelle: "Conversations précédentes", identifiant: "fils-precedents") {
                    historique = true
                } contenu: {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 15, weight: .medium))
                }
                .opacity(modele.aDesFilsPrecedents ? 1 : 0.4)
                .disabled(!modele.aDesFilsPrecedents)
                BoutonRondVerre(libelle: "Nouvelle conversation", identifiant: "nouvelle-conversation") {
                    clavier = false
                    withAnimation(.endry) { modele.nouvelleConversation() }
                } contenu: {
                    Image(systemName: "square.and.pencil").font(.system(size: 15, weight: .medium))
                }
                .opacity(modele.filCourant.isEmpty ? 0.4 : 1)
                .disabled(modele.filCourant.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    /// En direct : l'agent qui travaille et sa tâche, sinon l'état du bureau.
    private var statut: String {
        if let nom = modele.agentNom { return "Assistant · \(nom)" }
        guard let agents = app.agents else { return "Assistant du bureau" }
        if agents.enDirect, let actif = agents.agents.first(where: { $0.etat == .occupe && $0.tache != nil }), let tache = actif.tache {
            return "\(actif.nom) · \(tache.prefix(1).lowercased())\(tache.dropFirst())"
        }
        return agents.etat?.libelleCourt ?? "Assistant du bureau"
    }

    private var enTravail: Bool {
        modele.reflechit || (app.agents?.agents.contains { $0.etat == .occupe } ?? false)
    }

    private var couleurEtat: Color {
        guard let etat = app.agents?.etat else { return Color.encrePale.opacity(0.5) }
        if etat.enPause || !etat.enService() { return Color.ambre }
        return Color.sauge
    }

    // MARK: Accueil (fil vide)

    private var accueil: some View {
        VStack(alignment: .leading, spacing: Espace.m) {
            Text("Nouvelle conversation").etiquetteMaison()
                .padding(.top, Espace.xl)
            Text("Parlez au bureau")
                .font(Police.serif(36, relativeTo: .largeTitle))
                .foregroundStyle(Color.encre)
            Text("Écrivez ou dictez : l’assistant du PC répond ici, comme une session ouverte. Tout envoi reste une décision à glisser.")
                .styleTexte(15)
                .foregroundStyle(Color.encreDouce)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(Self.suggestions.enumerated()), id: \.offset) { index, suggestion in
                    Button {
                        Task { await modele.envoyer(suggestion, nature: .question, source: .ecrit) }
                    } label: {
                        HStack(spacing: Espace.s) {
                            Text(suggestion).styleTexte(15).foregroundStyle(Color.encre)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.encreDouce)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .tuileMaison(rayon: 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ActionPressee())
                    .accessibilityIdentifier("suggestion-conversation-\(index)")
                }
            }
            .padding(.top, Espace.xs)
        }
    }
}

/// Champ d'écriture et de dictée : il garde son propre état, pour que la frappe et le niveau du micro
/// ne redessinent pas tout le fil à chaque lettre.
private struct ComposeurConversation: View {
    var modele: ModeleConversation
    var clavier: FocusState<Bool>.Binding
    @State private var texte = ""
    @State private var nature: MessageConversation.Nature = .question
    /// Le patron a choisi lui-même Question / Demande : on ne devine plus.
    @State private var natureChoisie = false
    @State private var dictee = Dictee()
    /// Texte présent avant la dictée : la dictée s'y ajoute.
    @State private var avantDictee = ""
    /// Le message en cours vient (au moins en partie) de la dictée.
    @State private var dicte = false

    var body: some View {
        composeur
            .onDisappear { dictee.arreter() }
            .onChange(of: dictee.transcription) { _, dit in
                guard dictee.ecoute, !dit.isEmpty else { return }
                texte = avantDictee.isEmpty ? dit : avantDictee + " " + dit
                dicte = true
            }
            .onChange(of: texte) { ancien, nouveau in
                // Première lettre : la connexion au PC est réchauffée pendant que le patron écrit.
                if ancien.isEmpty, !nouveau.isEmpty { Task { await modele.prechauffer() } }
                guard !natureChoisie else { return }
                let probable = ModeleConversation.natureProbable(nouveau)
                if probable != nature { nature = probable }
            }
    }

    private var vide: Bool { texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var composeur: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            if case .refuse(let raison) = dictee.etat {
                Text(raison).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.rouille)
            } else if case .indisponible(let raison) = dictee.etat {
                Text(raison).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.rouille)
            }
            VStack(alignment: .leading, spacing: 10) {
                TextField("", text: $texte, prompt: Text(dictee.ecoute ? "J’écoute…" : "Écrire au bureau…").foregroundStyle(Color.encreDouce),
                          axis: .vertical)
                    .styleTexte(17)
                    .foregroundStyle(Color.encre)
                    .tint(Color.signal)
                    .lineLimit(1...6)
                    .focused(clavier)
                    .accessibilityIdentifier("champ-conversation")
                HStack(spacing: Espace.xs) {
                    choixNature
                    Spacer(minLength: 0)
                    boutonDictee
                    boutonEnvoyer
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .verreMaison(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.signal.opacity(clavier.wrappedValue || dictee.ecoute ? 0.45 : 0), lineWidth: 1))
            .animation(.endryVif, value: clavier.wrappedValue)
        }
        .largeurLisible()
        .padding(.horizontal, 12)
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
                    .styleTexte(13, relativeTo: .footnote, graisse: .medium)
            }
            .foregroundStyle(nature == .question ? Color.encreDouce : Color.encre)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(nature == .question ? Color.clear : Color.lentille, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.filet, lineWidth: Espace.filet))
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
                clavier.wrappedValue = false
                Task { await dictee.demarrer() }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.signal.opacity(dictee.ecoute ? 0.25 : 0))
                    .scaleEffect(1 + CGFloat(dictee.niveau) * 0.5)
                    .animation(.endryVif, value: dictee.niveau)
                Image(systemName: dictee.ecoute ? "stop.fill" : "mic")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(dictee.ecoute ? Color.signal : Color.encreDouce)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 40, height: 40)
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.boutonTexte)
                .frame(width: 38, height: 38)
                .background(Color.bouton, in: Circle())
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

/// Conversations précédentes : rouvrir un fil (la suite repart dedans), ou tout effacer.
private struct HistoriqueConversations: View {
    @Environment(\.dismiss) private var fermer
    var modele: ModeleConversation
    @State private var confirmerEffacement = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(modele.filsPrecedents) { fil in
                        Button {
                            modele.reprendre(fil.id)
                            fermer()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(fil.titre)
                                    .styleTexte(16, relativeTo: .body)
                                    .foregroundStyle(Color.encre)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text("\(DateEndry.ilYa(fil.fin)) · \(fil.nombre) message\(fil.nombre > 1 ? "s" : "")")
                                    .font(Police.mono(11.5))
                                    .foregroundStyle(Color.encreDouce)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tuileMaison(rayon: 20)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(ActionPressee())
                        .accessibilityIdentifier("fil-\(fil.id)")
                    }
                    Button(role: .destructive) {
                        confirmerEffacement = true
                    } label: {
                        Label("Effacer tout l’historique", systemImage: "trash")
                            .styleTexte(15, relativeTo: .subheadline, graisse: .medium)
                            .foregroundStyle(Color.rouille)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .padding(.top, Espace.m)
                }
                .padding(.horizontal, Espace.bord)
                .padding(.vertical, Espace.m)
                .verrouillerLargeur()
            }
            .background(FondMaison(photo: nil))
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } }
            }
            .confirmationDialog("Effacer toutes les conversations ?", isPresented: $confirmerEffacement, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) {
                    modele.effacer()
                    fermer()
                }
            } message: {
                Text("Les fils sont effacés de l’iPhone. Ce que le bureau a déjà fait reste dans « Fait récemment ».")
            }
        }
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
    /// En direct, pendant l'attente : ce que fait le bureau (« Secrétariat · cherche dans les e-mails »).
    var activite: String? = nil
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.tuileHaut, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.filet, lineWidth: Espace.filet))
                HStack(spacing: 4) {
                    if message.nature == .demande { Image(systemName: "hammer") }
                    if message.source != .ecrit { Image(systemName: message.source == .voix ? "waveform" : "mic") }
                    Text(legende)
                }
                .styleTexte(11.5, relativeTo: .caption2)
                .foregroundStyle(Color.encreDouce)
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
                Text(message.agent ?? "Assistant du bureau")
                    .etiquetteMaison(11)
                if message.etat == .recu {
                    Text(DateEndry.heure(message.le))
                        .font(Police.mono(11))
                        .foregroundStyle(Color.encreDouce)
                }
            }
            .foregroundStyle(Color.etiquette)
            switch message.etat {
            case .attente:
                if message.texte.isEmpty {
                    Reflexion(depuis: question?.le ?? message.le, message: message.message, activite: activite)
                } else {
                    // La réponse s'écrit sur le PC (v1.8) : elle apparaît mot à mot, comme une session ouverte.
                    TexteRiche(texte: message.texte)
                        .accessibilityIdentifier("reponse-en-cours")
                    PointVeille(couleur: .signal, actif: true, diametre: 6)
                        .accessibilityLabel(Text("Le bureau écrit"))
                }
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
                                .styleTexte(13.5, relativeTo: .footnote, graisse: .medium)
                                .foregroundStyle(Color.encre)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(Color.lentille, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.filet, lineWidth: Espace.filet))
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
    /// Ce que fait le bureau en ce moment, en direct.
    var activite: String? = nil
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
        let base = message ?? activite ?? "L’assistant réfléchit…"
        return Text(secondes < 4 || message != nil ? base : "\(base) · \(secondes) s")
            .styleTexte(14)
            .foregroundStyle(Color.encreDouce)
            .monospacedDigit()
            .lineLimit(2)
            .contentTransition(.opacity)
    }

    private func points(_ actif: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.signal.opacity(i == actif ? 0.9 : 0.3))
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
            ForEach(Array(CacheTexteRiche.blocs(texte).enumerated()), id: \.offset) { _, bloc in
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
        CacheTexteRiche.enLigne(t)
    }
}

/// Mise en forme des réponses calculée une seule fois par texte : le fil ne relit plus le Markdown à chaque
/// rafraîchissement (cause des saccades quand le fil s'allongeait).
@MainActor
enum CacheTexteRiche {
    private static var blocsParTexte: [String: [BlocTexte]] = [:]
    private static var lignes: [String: AttributedString] = [:]

    static func blocs(_ texte: String) -> [BlocTexte] {
        if let deja = blocsParTexte[texte] { return deja }
        if blocsParTexte.count > 300 { blocsParTexte.removeAll() }
        let blocs = BlocTexte.decouper(texte)
        blocsParTexte[texte] = blocs
        return blocs
    }

    static func enLigne(_ t: String) -> AttributedString {
        if let deja = lignes[t] { return deja }
        if lignes.count > 1_500 { lignes.removeAll() }
        let ligne = (try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t)
        lignes[t] = ligne
        return ligne
    }
}
