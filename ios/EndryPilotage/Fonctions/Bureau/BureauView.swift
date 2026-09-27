import EndryKit
import SwiftUI

extension EtatAgent {
    var couleur: Color {
        switch self {
        case .libre: .sauge
        case .occupe: .bronze
        case .pause: .ambre
        case .erreur: .rouille
        }
    }
}

/// Point d'état d'un agent : il pulse quand l'agent travaille.
struct PointEtat: View {
    var etat: EtatAgent?
    var taille: CGFloat = 8

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: taille))
            .foregroundStyle(etat?.couleur ?? Color.encrePale)
            .symbolEffect(.pulse, isActive: etat == .occupe)
            .accessibilityHidden(true)
    }
}

// MARK: - Entreprise › Le bureau

/// « Le bureau » : les agents de Claude sur le PC, ce que chacun fait, et le journal de la journée.
struct SectionBureau: View {
    var modele: ModeleAgents

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: "Le bureau", detail: modele.libelle)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Espace.s), GridItem(.flexible(), spacing: Espace.s)], spacing: Espace.s) {
                ForEach(modele.agents) { agent in
                    NavigationLink(value: agent) {
                        TuileAgent(agent: agent, enDirect: modele.enDirect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("agent-\(agent.id)")
                }
            }
            if !modele.journal.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Journal du bureau").styleSurtitre()
                        .padding(.bottom, Espace.xs)
                    ForEach(Array(modele.journal.prefix(5).enumerated()), id: \.element.id) { index, entree in
                        LigneJournal(entree: entree, agent: entree.agent.flatMap { modele.agent($0) })
                        if index < min(modele.journal.count, 5) - 1 {
                            Rectangle().fill(Color.filet).frame(height: Espace.filet).padding(.leading, 40)
                        }
                    }
                }
                .padding(Espace.m)
                .surfaceCarte(rayon: 22)
            } else if !modele.enDirect, modele.charge {
                Text("Chaque agent répond à vos questions par Claude. L’activité en direct s’affichera dès la mise à jour v1.2 du PC.")
                    .styleTexte(13, relativeTo: .footnote)
                    .foregroundStyle(Color.encrePale)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationDestination(for: AgentPC.self) { agent in
            FicheAgentView(modele: modele, agentId: agent.id)
        }
        .task {
            // Rafraîchi tant que la section est visible (le flux SSE du PC complète en direct).
            while !Task.isCancelled {
                await modele.charger()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}

struct TuileAgent: View {
    var agent: AgentPC
    var enDirect: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            HStack {
                Image(systemName: agent.symbole)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.or)
                    .frame(width: 38, height: 38)
                    .background(Color.espresso, in: Circle())
                    .overlay(Circle().stroke(Color.or.opacity(agent.etat == .occupe && enDirect ? 0.8 : 0.25), lineWidth: 1))
                Spacer()
                if enDirect { PointEtat(etat: agent.etat) }
            }
            Text(agent.nom)
                .styleTitre(19, relativeTo: .headline)
                .foregroundStyle(Color.encre)
                .lineLimit(1)
            Text(sousTitre)
                .styleTexte(12, relativeTo: .caption)
                .foregroundStyle(Color.encreDouce)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .padding(Espace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCarte(rayon: 20)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Ouvre la fiche de l’agent"))
    }

    private var sousTitre: String {
        guard enDirect else { return agent.role ?? "Relié par Claude" }
        switch agent.etat {
        case .occupe: return agent.tache ?? "Au travail"
        case .libre: return agent.resumeJour ?? "Disponible"
        case .pause: return "En pause"
        case .erreur: return "Bloqué : attend une intervention"
        }
    }
}

struct LigneJournal: View {
    var entree: EntreeJournal
    var agent: AgentPC?

    var body: some View {
        HStack(alignment: .top, spacing: Espace.s) {
            Image(systemName: entree.type.icone)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(entree.type == .erreur ? Color.rouille : Color.bronze)
                .frame(width: 28, height: 28)
                .background(Color.or.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(entree.titre)
                    .styleTexte(14, relativeTo: .subheadline, graisse: .semibold)
                    .foregroundStyle(Color.encre)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = entree.detail {
                    Text(detail)
                        .styleTexte(13, relativeTo: .footnote)
                        .foregroundStyle(Color.encreDouce)
                        .lineLimit(3)
                }
                Text([agent?.nom, entree.date.map { DateEndry.ilYa($0) }, entree.decisionReference.map { "décision \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .styleTexte(11, relativeTo: .caption2, graisse: .medium)
                    .foregroundStyle(Color.encrePale)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Espace.xs)
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
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, 130)
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
                Text("Agent de Claude").styleSurtitre()
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
        VStack(alignment: .leading, spacing: Espace.s) {
            HStack(spacing: 6) {
                PointEtat(etat: agent.etat)
                Text(agent.etat.libelle).styleTexte(13, relativeTo: .footnote, graisse: .semibold).foregroundStyle(agent.etat.couleur)
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
                            Text("\(agent.nom) cherche sur le PC…").styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encrePale)
                        }
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
                TextField("", text: $question, prompt: Text("Poser une question à l’agent \(agent.nom)…"))
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
                        case .transmise: retour = Toast("Confié à l’agent \(agent.nom).")
                        case .gardee: retour = Toast("Pas de réseau : la demande partira toute seule.", style: .info)
                        case .refusee(let raison): retour = Toast(raison, style: .erreur)
                        }
                        travail = ""
                        confierOuvert = false
                    }
                } label: {
                    Text("Confier à l’agent \(agent?.nom ?? "")")
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
                            .foregroundStyle(agent.etat == .occupe ? Color.espresso : Color.or)
                            .frame(width: 28, height: 28)
                            .background(agent.etat == .occupe && modele.enDirect ? AnyShapeStyle(.degradeOr) : AnyShapeStyle(Color.espresso), in: Circle())
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
            return "\(actif.nom) : \(actif.tache ?? "")"
        }
        if let derniere = modele.journal.first { return derniere.titre }
        return "Secrétariat, comptabilité, chantiers, offres, achats"
    }
}
