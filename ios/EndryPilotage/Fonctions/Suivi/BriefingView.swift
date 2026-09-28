import EndryKit
import SwiftUI

/// Carte « Briefing » sur Aujourd'hui : un toucher pour l'écouter, un autre pour le détail.
struct CarteBriefing: View {
    @Environment(ModeleApp.self) private var app

    var body: some View {
        let briefing = BriefingMatin.composer(app: app)
        HStack(spacing: Espace.s) {
            Button {
                app.lecteur.basculer(briefing.texteParle)
            } label: {
                Image(systemName: app.lecteur.enLecture ? "stop.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.espressoProfond)
                    .frame(width: 44, height: 44)
                    .background(.degradeOr, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(app.lecteur.enLecture ? "Arrêter le briefing" : "Écouter le briefing"))
            .accessibilityIdentifier("ecouter-briefing")

            Button {
                app.briefingPresente = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Briefing du jour")
                            .styleTexte(14, relativeTo: .subheadline, graisse: .semibold)
                            .foregroundStyle(Color.encre)
                        Text(briefing.points.prefix(2).map { "\($0.titre) \($0.detail)" }.joined(separator: " · "))
                            .styleTexte(12, relativeTo: .caption)
                            .foregroundStyle(Color.encreDouce)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.bronze)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("carte-briefing")
        }
        .padding(Espace.m)
        .surfaceCarte(rayon: 22)
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
