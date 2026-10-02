import EndryKit
import SwiftUI

/// Carte « Briefing » sur Aujourd'hui : un toucher pour l'écouter, un autre pour le détail.
struct CarteBriefing: View {
    @Environment(ModeleApp.self) private var app
    /// Début de la lecture en cours : la barre avance au rythme estimé de la voix.
    @State private var debutLecture: Date?

    /// Maison Endry : pilule « Briefing du jour » — lecture à gauche, barre de progression, durée en mono.
    var body: some View {
        let briefing = BriefingMatin.composer(app: app)
        let duree = Self.dureeEstimee(briefing.texteParle)
        HStack(spacing: 12) {
            Button {
                debutLecture = app.lecteur.enLecture ? nil : Date()
                app.lecteur.basculer(briefing.texteParle)
            } label: {
                Image(systemName: app.lecteur.enLecture ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.boutonTexte)
                    .frame(width: 44, height: 44)
                    .background(Color.bouton, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(ActionPressee())
            .accessibilityLabel(Text(app.lecteur.enLecture ? "Arrêter le briefing" : "Écouter le briefing"))
            .accessibilityIdentifier("ecouter-briefing")

            Button {
                app.briefingPresente = true
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Briefing du jour")
                            .styleTexte(15, relativeTo: .subheadline)
                            .foregroundStyle(Color.encre)
                        if app.lecteur.enLecture, let debutLecture {
                            TimelineView(.periodic(from: debutLecture, by: 0.25)) { contexte in
                                BarreFine(part: contexte.date.timeIntervalSince(debutLecture) / duree)
                            }
                        } else {
                            BarreFine(part: 0)
                        }
                    }
                    Text(Self.minutesSecondes(duree))
                        .font(Police.mono(11.5))
                        .foregroundStyle(Color.encreDouce)
                        .padding(.trailing, 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("carte-briefing")
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 58)
        .tuileMaison(rayon: 29)
        .onChange(of: app.lecteur.enLecture) { _, lecture in
            if !lecture { debutLecture = nil }
        }
    }

    /// Environ 2,6 mots par seconde pour la voix française.
    static func dureeEstimee(_ texte: String) -> TimeInterval {
        max(Double(texte.split(whereSeparator: \.isWhitespace).count) / 2.6, 5)
    }

    static func minutesSecondes(_ duree: TimeInterval) -> String {
        let s = Int(duree.rounded())
        return "\(s / 60):" + (s % 60 < 10 ? "0" : "") + "\(s % 60)"
    }
}

/// Briefing détaillé : points du jour, lecture à voix haute, notification du matin.
struct BriefingView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @AppStorage(BriefingMatin.cleActif) private var actif = false
    @AppStorage(BriefingMatin.cleHeure) private var minutes = 7 * 60

    var body: some View {
        let briefing = BriefingMatin.composer(app: app)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.l) {
                    VStack(alignment: .leading, spacing: Espace.xs) {
                        Text("Briefing").styleSurtitre()
                        Text(briefing.ouverture)
                            .styleTitre(28, relativeTo: .largeTitle)
                            .foregroundStyle(Color.encre)
                    }
                    Button {
                        app.lecteur.basculer(briefing.texteParle)
                    } label: {
                        Label(app.lecteur.enLecture ? "Arrêter" : "Écouter le briefing",
                              systemImage: app.lecteur.enLecture ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(BoutonPrincipal())

                    VStack(spacing: 0) {
                        ForEach(Array(briefing.points.enumerated()), id: \.element.id) { i, point in
                            HStack(alignment: .top, spacing: Espace.m) {
                                Image(systemName: point.icone)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.bronze)
                                    .frame(width: 34, height: 34)
                                    .background(Color.or.opacity(0.16), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(point.titre).styleTexte(15, graisse: .semibold).foregroundStyle(Color.encre)
                                    Text(Self.sansTitre(point)).styleTexte(14).foregroundStyle(Color.encreDouce)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, Espace.s)
                            if i < briefing.points.count - 1 { Rectangle().fill(Color.filet).frame(height: 0.5) }
                        }
                    }
                    .padding(.horizontal, Espace.m)
                    .surfaceCarte(rayon: 22)

                    VStack(alignment: .leading, spacing: Espace.s) {
                        Toggle(isOn: $actif) {
                            Label("Chaque matin de semaine", systemImage: "sunrise.fill")
                                .styleTexte(16, graisse: .semibold)
                        }
                        .tint(Color.bronzeMoyen)
                        .accessibilityIdentifier("briefing-actif")
                        if actif {
                            DatePicker("Heure", selection: Binding(
                                get: { DateEndry.a(minutes / 60, minutes % 60, le: Date()) },
                                set: { d in
                                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                                    minutes = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                                }), displayedComponents: .hourAndMinute)
                            .styleTexte(15)
                        }
                        Text("Une notification à l’heure choisie, rafraîchie juste avant. Sur l’écran verrouillé, aucun montant n’apparaît. Dites aussi « Briefing Endry » à Siri, même en voiture.")
                            .styleTexte(12, relativeTo: .caption)
                            .foregroundStyle(Color.encrePale)
                    }
                    .padding(Espace.m)
                    .surfaceCarte(rayon: 20)
                }
                .largeurLisible()
                .padding(Espace.bord)
            }
            .background(FondAmbiant())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { fermer() } } }
        }
        .onChange(of: actif) { _, _ in reprogrammer() }
        .onChange(of: minutes) { _, _ in reprogrammer() }
        .onDisappear { app.lecteur.arreter() }
    }

    /// La phrase dite reprend parfois le titre (« À encaisser : … ») : à l'écran, on ne le répète pas.
    static func sansTitre(_ point: PointBriefing) -> String {
        guard point.phrase.hasPrefix(point.titre + " :") else { return point.phrase }
        let reste = point.phrase.dropFirst(point.titre.count + 2).trimmingCharacters(in: .whitespaces)
        return reste.prefix(1).uppercased() + reste.dropFirst()
    }

    private func reprogrammer() {
        let b = BriefingMatin.composer(app: app, masquerMontants: true)
        Task {
            if actif { _ = await DelegueApp.demanderAutorisation() }
            await BriefingMatin.programmer(b)
        }
    }
}

/// Réglages › Suivi et rappels : seuil des offres, briefing du matin, rappel d'arrivée sur chantier.
struct ReglagesSuiviRappels: View {
    @Environment(ModeleApp.self) private var app
    @AppStorage(ReglagesSuivi.cleSeuil) private var seuil = SuiviOffres.seuilParDefaut
    @AppStorage(BriefingMatin.cleActif) private var briefing = false
    @AppStorage(BriefingMatin.cleMontantsSiri) private var montantsSiri = false
    @AppStorage(ArriveeChantier.cleActif) private var arrivee = false

    var body: some View {
        Section {
            Stepper("Offres sans réponse : \(seuil) jours", value: $seuil, in: 7...60, step: 1)
            Toggle(isOn: $briefing) { Label("Briefing chaque matin", systemImage: "sunrise") }
                .tint(Color.vertControle)
                .onChange(of: briefing) { _, actif in
                    let b = BriefingMatin.composer(app: app, masquerMontants: true)
                    Task {
                        if actif { _ = await DelegueApp.demanderAutorisation() }
                        await BriefingMatin.programmer(b)
                    }
                }
            Toggle(isOn: $montantsSiri) { Label("Montants dans le briefing Siri", systemImage: "banknote") }
                .tint(Color.vertControle)
            Toggle(isOn: Binding(get: { arrivee }, set: { actif in
                Task {
                    if actif {
                        await ArriveeChantier.partage.activer()
                        await ArriveeChantier.partage.mettreAJour(app: app)
                    } else {
                        await ArriveeChantier.partage.desactiver()
                    }
                }
            })) { Label("Rappel en arrivant sur un chantier", systemImage: "location.circle") }
                .tint(Color.vertControle)
                .accessibilityIdentifier("rappel-arrivee")
        } header: {
            Text("Suivi et rappels")
        } footer: {
            Text("Le rappel d’arrivée utilise la position de l’iPhone, qui ne le quitte jamais ; choisissez « Toujours » quand iOS le demande. Les notifications n’affichent aucun montant. Siri ne dit les montants que si vous l’activez ici.")
        }
    }
}
