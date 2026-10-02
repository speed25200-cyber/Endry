import EndryKit
import SwiftUI

extension EtatAgent {
    var couleur: Color {
        switch self {
        case .libre: .encrePale
        case .occupe: .sauge
        case .pause: .ambre
        case .erreur: .rouille
        case .horsHoraires: .encrePale
        }
    }
}

/// Point d'état d'un agent : il respire quand l'agent travaille (horloge locale, rien ne scintille autour).
struct PointEtat: View {
    var etat: EtatAgent?
    var taille: CGFloat = 8

    var body: some View {
        PointVeille(couleur: etat?.couleur ?? Color.encrePale, actif: etat == .occupe, diametre: taille)
            .opacity(etat == .occupe ? 1 : 0.55)
    }
}

// MARK: - Le bureau (maquette E)

/// « Le bureau » : combien d'agents travaillent, pause / reprise, tuiles des agents (état, tâche, charge du jour),
/// journal du jour sur un rail, et « Demander au bureau… ».
struct SectionBureau: View {
    @Environment(ModeleApp.self) private var app
    var modele: ModeleAgents
    @State private var confirmationPause = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            enTete
            if let service = modele.service {
                Label(service, systemImage: service.hasPrefix("Hors") ? "moon.zzz" : "clock")
                    .font(Police.mono(11.5))
                    .foregroundStyle(service.hasPrefix("Hors") ? Color.ambre : Color.encreDouce)
                    .padding(.top, Espace.xs)
                    .accessibilityIdentifier("service-assistant")
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(modele.agents) { agent in
                    NavigationLink(value: agent) {
                        TuileAgent(agent: agent, etat: modele.etatAffiche(agent), repasse: modele.etat?.repasse(), enDirect: modele.enDirect)
                    }
                    .buttonStyle(ActionPressee())
                    .accessibilityIdentifier("agent-\(agent.id)")
                }
            }
            .padding(.top, Espace.l)

            if !modele.journal.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Journal").etiquetteMaison()
                    Spacer()
                    Text("Aujourd’hui").font(Police.mono(11.5)).foregroundStyle(Color.encreDouce)
                }
                .padding(.top, Espace.xl)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(modele.journal.prefix(6).enumerated()), id: \.element.id) { index, entree in
                        LigneJournal(entree: entree, agent: entree.agent.flatMap { modele.agent($0) },
                                     derniere: index == min(modele.journal.count, 6) - 1)
                    }
                }
                .padding(.top, Espace.s)
            } else if !modele.enDirect, modele.charge {
                Text("L’assistant du PC répond par domaine. L’activité en direct s’affichera dès que le PC la publiera.")
                    .styleTexte(13, relativeTo: .footnote)
                    .foregroundStyle(Color.encreDouce)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Espace.m)
            }

            if app.conversation != nil {
                Button { app.ouvrirConversation() } label: {
                    HStack(spacing: Espace.s) {
                        Text(app.conversation?.reflechit == true ? "L’assistant réfléchit…" : "Demander au bureau…")
                            .styleTexte(17, relativeTo: .body)
                            .foregroundStyle(Color.encreDouce)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.boutonTexte)
                            .frame(width: 44, height: 44)
                            .background(Color.bouton, in: Circle())
                    }
                    .padding(.leading, 20)
                    .padding(.trailing, 6)
                    .frame(height: 56)
                    .verreMaison(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(ActionPressee())
                .padding(.top, Espace.l)
                .accessibilityLabel(Text("Demander au bureau"))
                .accessibilityIdentifier("ouvrir-conversation-bureau")
            }
        }
        .navigationDestination(for: AgentPC.self) { agent in
            FicheAgentView(modele: modele, agentId: agent.id)
        }
        .confirmationDialog("Mettre l’assistant en pause ?", isPresented: $confirmationPause, titleVisibility: .visible) {
            Button("Mettre en pause") { Task { _ = await app.pilotage?.basculer() } }
        } message: {
            Text("Il cesse de préparer des propositions jusqu’à la reprise.")
        }
        // Chargé à l'affichage ; ensuite, ce sont les événements du PC (SSE) qui le tiennent à jour.
        .task { await modele.charger() }
    }

    private var actifs: Int { modele.agents.filter { modele.etatAffiche($0) == .occupe }.count }

    private var enTete: some View {
        HStack(alignment: .center, spacing: Espace.s) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Le bureau").etiquetteMaison()
                Text(modele.enDirect ? (actifs == 0 ? "Au repos" : actifs == 1 ? "1 agent actif" : "\(actifs) agents actifs") : "Le bureau")
                    .font(Police.serif(40, relativeTo: .largeTitle))
                    .foregroundStyle(Color.encre)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: Double(actifs)))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Espace.xs)
            if let pilotage = app.pilotage, pilotage.disponible {
                Toggle(isOn: Binding(get: { !pilotage.enPause }, set: { actif in
                    if actif { Task { _ = await pilotage.basculer() } } else { confirmationPause = true }
                })) {
                    Text(pilotage.enPause ? "Pause" : "Actif")
                        .styleTexte(14, relativeTo: .subheadline)
                        .foregroundStyle(Color.encre)
                }
                .toggleStyle(.switch)
                .tint(Color.sauge)
                .fixedSize()
                .disabled(pilotage.enCours)
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .frame(height: 44)
                .verreMaison(Capsule())
                .accessibilityIdentifier("pause-reprise")
            }
        }
        .padding(.top, Espace.m)
    }
}

/// Tuile d'un agent : nom, point d'état, ce qu'il fait, et en mono son état et sa charge du jour.
struct TuileAgent: View {
    var agent: AgentPC
    /// État affiché (hors horaires plutôt que « Disponible » en dehors des heures de passage).
    var etat: EtatAgent
    var repasse: String?
    var enDirect: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(agent.nom)
                    .styleTexte(15, relativeTo: .subheadline)
                    .foregroundStyle(Color.encre)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if enDirect { PointEtat(etat: etat, taille: 7) }
            }
            Text(sousTitre)
                .styleTexte(13, relativeTo: .footnote)
                .foregroundStyle(Color.encreDouce)
                .lineLimit(3, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .padding(.top, 12)
            Spacer(minLength: 10)
            HStack(alignment: .firstTextBaseline) {
                Text(libelleEtat)
                Spacer(minLength: 4)
                Text(taches)
            }
            .font(Police.mono(11.5))
            .foregroundStyle(Color.encreDouce)
            .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .tuileMaison(rayon: 24)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Ouvre la fiche de l’agent"))
    }

    private var sousTitre: String {
        guard enDirect else { return agent.role ?? "Domaine de l’assistant" }
        switch etat {
        case .occupe: return agent.tache ?? "Au travail"
        case .libre: return agent.resumeJour ?? "Rien en cours"
        case .pause: return "En pause"
        case .erreur: return "Bloqué : attend une intervention"
        case .horsHoraires: return repasse.map { "Repasse \($0)" } ?? "Hors horaires"
        }
    }

    private var libelleEtat: String {
        guard enDirect else { return "domaine" }
        switch etat {
        case .occupe: return "travaille"
        case .libre: return "au repos"
        case .pause: return "en pause"
        case .erreur: return "bloqué"
        case .horsHoraires: return "hors horaires"
        }
    }

    private var taches: String {
        let n = agent.traiteesJour + agent.file
        return n == 1 ? "1 tâche" : "\(n) tâches"
    }
}

/// Entrée du journal sur un rail : anneau (vert « fait », crème « question », rouille « erreur »), titre, agent, heure.
struct LigneJournal: View {
    var entree: EntreeJournal
    var agent: AgentPC?
    var derniere = false

    private var couleur: Color {
        switch entree.type {
        case .question: .signal
        case .erreur: .rouille
        default: .sauge
        }
    }

    private var statut: String {
        switch entree.type {
        case .question: "question"
        case .erreur: "erreur"
        case .emailRecu: "reçu"
        case .info: "info"
        default: "fait"
        }
    }

    /// `09:24`
    static func heure(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(couleur, lineWidth: 1.2)
                    .frame(width: 15, height: 15)
                    .overlay(Circle().fill(couleur).frame(width: 6, height: 6))
                    .padding(.top, 3)
                if !derniere {
                    Rectangle().fill(Color.filetFort).frame(width: 1).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 15)
            VStack(alignment: .leading, spacing: 3) {
                Text(entree.titre)
                    .styleTexte(15, relativeTo: .subheadline)
                    .foregroundStyle(Color.encre)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text([agent?.nom, statut].compactMap { $0 }.joined(separator: " · "))
                    .styleTexte(13, relativeTo: .footnote)
                    .foregroundStyle(Color.encreDouce)
            }
            .padding(.bottom, derniere ? 0 : 18)
            Spacer(minLength: Espace.xs)
            if let date = entree.date {
                Text(Self.heure(date))
                    .font(Police.mono(11.5))
                    .foregroundStyle(Color.encreDouce)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Fiche d'un agent

/// Tout sur un agent : ce qu'il fait, sa journée, son journal ; lui poser une question ou lui confier un travail.
struct FicheAgentView: View {
    @Environment(ModeleApp.self) private var app
    var modele: ModeleAgents
    var agentId: String
    @State private var question = ""
    @State private var travail = ""
    @State private var confierOuvert = false
    @State private var retour: Toast?
    @FocusState private var champActif: Bool

    private var agent: AgentPC? { modele.agent(agentId) }

    var body: some View {
        ScrollView {
            if let agent {
                VStack(alignment: .leading, spacing: Espace.l) {
                    entete(agent)
                    if modele.enDirect { maintenant(agent) }
                    conversation(agent)
                    actions(agent)
                    let entrees = modele.journal(de: agent)
                    if !entrees.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Journal").styleSurtitre().padding(.bottom, Espace.xs)
                            ForEach(entrees) { entree in
                                LigneJournal(entree: entree, agent: nil)
                            }
                        }
                        .padding(Espace.m)
                        .surfaceCarte(rayon: 22)
                    }
                }
                .largeurLisible()
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, 130)
                .verrouillerLargeur()
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(FondAmbiant())
        .navigationTitle(agent?.nom ?? "Agent")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let agent { await modele.chargerJournal(de: agent) }
        }
        .sheet(isPresented: $confierOuvert) { feuilleConfier }
        .toast($retour)
    }

    private func entete(_ agent: AgentPC) -> some View {
        HStack(spacing: Espace.m) {
            Image(systemName: agent.symbole)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.or)
                .frame(width: 64, height: 64)
                .background(Color.espresso, in: Circle())
                .overlay(Circle().stroke(Color.or.opacity(0.5), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text("L’assistant, côté").styleSurtitre()
                Text(agent.nom).styleTitre(30, relativeTo: .largeTitle).foregroundStyle(Color.encre)
                if let role = agent.role {
                    Text(role).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
                }
            }
        }
        .padding(.top, Espace.m)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fiche-agent")
    }

    private func maintenant(_ agent: AgentPC) -> some View {
        let etat = modele.etatAffiche(agent)
        return VStack(alignment: .leading, spacing: Espace.s) {
            HStack(spacing: 6) {
                PointEtat(etat: etat)
                Text(etat == .horsHoraires ? (modele.etat?.repasse().map { "Hors horaires · repasse \($0)" } ?? "Hors horaires") : etat.libelle)
                    .styleTexte(13, relativeTo: .footnote, graisse: .semibold).foregroundStyle(etat.couleur)
                Spacer()
                if agent.file > 0 { Pastille(texte: "\(agent.file) en attente", couleur: .ambre, icone: "tray.full.fill") }
            }
            if let tache = agent.tache {
                Text(tache).styleTitre(20, relativeTo: .title3, graisse: .medium).foregroundStyle(Color.encre)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let jour = agent.resumeJour {
                Text("Aujourd’hui : \(jour)").styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
            }
        }
        .padding(Espace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte(rayon: 22)
    }

    private func conversation(_ agent: AgentPC) -> some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            Text("Lui demander").styleSurtitre()
            ForEach(modele.echanges[agent.id] ?? []) { echange in
                VStack(alignment: .leading, spacing: 6) {
                    Text(echange.question)
                        .styleTexte(14, relativeTo: .subheadline, graisse: .semibold)
                        .foregroundStyle(Color.encre)
                    switch echange.etat {
                    case .enCours:
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(BureauClaude.enTraitement).styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encrePale)
                        }
                    case .enAttente:
                        Label(echange.reponse ?? BureauClaude.reponseAVenir, systemImage: "clock")
                            .styleTexte(13, relativeTo: .footnote)
                            .foregroundStyle(Color.encreDouce)
                            .fixedSize(horizontal: false, vertical: true)
                    case .repondu, .erreur:
                        Text(echange.reponse ?? "")
                            .styleTexte(15, relativeTo: .body)
                            .foregroundStyle(echange.etat == .erreur ? Color.encrePale : Color.encre)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("reponse-agent")
                        if !echange.sources.isEmpty {
                            Text("Sources : " + echange.sources.map(\.libelle).joined(separator: " · "))
                                .styleTexte(11, relativeTo: .caption2).foregroundStyle(Color.encrePale)
                        }
                        if let reference = echange.decisionReference {
                            Button("Voir la décision \(reference)") {
                                app.onglet = .aujourdhui
                                app.referenceCiblee = reference
                            }
                            .styleTexte(13, relativeTo: .footnote, graisse: .semibold)
                            .foregroundStyle(Color.bronze)
                        }
                    }
                }
                .padding(Espace.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceCreuse, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            HStack(spacing: Espace.xs) {
                TextField("", text: $question, prompt: Text("Une question pour l’assistant, côté \(agent.nom)…"))
                    .styleTexte(16)
                    .focused($champActif)
                    .submitLabel(.send)
                    .onSubmit { envoyer(agent) }
                    .padding(.leading, Espace.m)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("question-agent")
                Button { envoyer(agent) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.espresso)
                        .frame(width: 36, height: 36)
                        .background(Color.or, in: Circle())
                }
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.trailing, 6)
                .accessibilityLabel(Text("Envoyer la question"))
                .accessibilityIdentifier("envoyer-question-agent")
            }
            .surfaceCarte(rayon: 24)
        }
        .animation(.endry, value: modele.echanges[agent.id] ?? [])
    }

    private func actions(_ agent: AgentPC) -> some View {
        HStack(spacing: Espace.s) {
            Button {
                confierOuvert = true
            } label: {
                Label("Confier un travail", systemImage: "tray.and.arrow.up.fill")
            }
            .buttonStyle(BoutonSecondaire(couleur: .bronze))
            Button {
                app.ouvrirAssistant()
            } label: {
                Label("Parler", systemImage: "waveform")
            }
            .buttonStyle(BoutonSecondaire(couleur: .bronze))
        }
    }

    private var feuilleConfier: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Espace.m) {
                Text("L’agent prépare ; rien ne part chez un tiers sans votre geste.")
                    .styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
                TextField("Ex. : prépare une réponse à la régie Dubois", text: $travail, axis: .vertical)
                    .styleTexte(17)
                    .lineLimit(3...8)
                    .padding(Espace.m)
                    .surfaceCarte(rayon: 18)
                Button {
                    guard let agent else { return }
                    let demande = travail
                    Task {
                        let resultat = await modele.confier(demande, a: agent)
                        switch resultat {
                        case .transmise: retour = Toast("Confié à l’assistant, côté \(agent.nom).")
                        case .gardee: retour = Toast("Pas de réseau : la demande partira toute seule.", style: .info)
                        case .refusee(let raison): retour = Toast(raison, style: .erreur)
                        }
                        travail = ""
                        confierOuvert = false
                    }
                } label: {
                    Text("Confier (côté \(agent?.nom ?? ""))")
                }
                .buttonStyle(BoutonPrincipal())
                .disabled(travail.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
            .padding(Espace.bord)
            .background(Color.fond)
            .navigationTitle("Confier un travail")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func envoyer(_ agent: AgentPC) {
        let texte = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty else { return }
        question = ""
        champActif = false
        Task { await modele.demander(texte, a: agent) }
    }
}

// MARK: - Aujourd'hui

/// Le bureau en une ligne : les agents (ceux qui travaillent brillent) et ce qui se passe en ce moment.
struct BandeauBureau: View {
    var modele: ModeleAgents
    var ouvrir: () -> Void

    var body: some View {
        Button(action: ouvrir) {
            HStack(spacing: Espace.s) {
                HStack(spacing: -8) {
                    ForEach(modele.agents.prefix(5)) { agent in
                        Image(systemName: agent.symbole)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(modele.etatAffiche(agent) == .occupe ? Color.espresso : Color.or)
                            .frame(width: 28, height: 28)
                            .background(modele.etatAffiche(agent) == .occupe && modele.enDirect ? AnyShapeStyle(.degradeOr) : AnyShapeStyle(Color.espresso), in: Circle())
                            .overlay(Circle().stroke(Color.fond, lineWidth: 2))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(modele.libelle)
                        .styleTexte(14, relativeTo: .subheadline, graisse: .semibold)
                        .foregroundStyle(Color.encre)
                    Text(detail)
                        .styleTexte(12, relativeTo: .caption)
                        .foregroundStyle(Color.encreDouce)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.bronze)
            }
            .padding(Espace.m)
            .surfaceCarte(rayon: 22)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Ouvre Le bureau dans Entreprise"))
        .accessibilityIdentifier("bandeau-bureau")
    }

    private var detail: String {
        if let actif = modele.agents.first(where: { $0.etat == .occupe && $0.tache != nil }), modele.enDirect {
            return "Côté \(actif.nom) : \(actif.tache ?? "")"
        }
        if let service = modele.service, service.hasPrefix("Hors") { return service }
        if let derniere = modele.journal.first { return derniere.titre }
        return "Secrétariat, comptabilité, chantiers, offres, achats"
    }
}
