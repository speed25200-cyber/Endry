import CoreImage.CIFilterBuiltins
import EndryKit
import SwiftUI

/// Mode équipe : ce que voit un ouvrier connecté avec son lien d'équipe. Ses chantiers du jour, un pointage en
/// un geste, photos, bon de livraison, remarques dictées, et l'envoi de sa journée. Aucun montant, aucune décision.
struct EspaceOuvrier: View {
    @Environment(ModeleApp.self) private var app
    var modele: ModeleEquipe
    @State private var photos: [FormulaireMultipart.Fichier] = []
    @State private var envoiPhotos = false
    @State private var journeePresentee = false
    @State private var dictee = Dictee()
    @State private var confirmationDeconnexion = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.l) {
                    entete
                    if let enCours = modele.enCours { carteEnCours(enCours) }
                    switch modele.etat {
                    case .initial, .chargement where modele.journee == nil:
                        Squelette(hauteur: 180, rayon: Espace.rayon)
                    case .erreur(let e) where modele.journee == nil:
                        VueErreur(erreur: e) { Task { await modele.charger() } }
                    default:
                        if let message = modele.journee?.message {
                            Label(message, systemImage: "info.circle").styleTexte(14).foregroundStyle(Color.encreDouce)
                        }
                        if modele.chantiers.isEmpty {
                            EtatVide(titre: "Aucun chantier", message: "Rien de prévu pour vous aujourd’hui. Le bureau vous préviendra.",
                                     icone: "calendar")
                        }
                        ForEach(modele.chantiers) { chantier in carteChantier(chantier) }
                    }
                    outils
                    Button {
                        modele.arreter()
                        LiveActivitePointage.synchroniser(modele)
                        journeePresentee = true
                    } label: {
                        Label(modele.envoyee ? "Corriger et renvoyer ma journée" : "Envoyer ma journée", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(BoutonPrincipal())
                    .disabled(modele.feuille.pointages.isEmpty)
                    .accessibilityIdentifier("envoyer-journee")
                    Button("Se déconnecter", role: .destructive) { confirmationDeconnexion = true }
                        .styleTexte(14, graisse: .medium)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, Espace.xxl)
            }
            .scrollIndicators(.hidden)
            .refreshable { await modele.charger() }
            .background(FondAmbiant())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await modele.charger() }
        .sheet(isPresented: $journeePresentee) { JourneeOuvrierView(modele: modele) }
        .fullScreenCover(item: Binding(get: { app.outilTerrain }, set: { app.outilTerrain = $0 })) { demande in
            BonLivraisonView(chantier: nil)
                .environment(app)
                .id(demande.id)
        }
        .confirmationDialog("Se déconnecter de cet iPhone ?", isPresented: $confirmationDeconnexion, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) { Task { await app.deconnecterCetAppareil() } }
        }
        .onChange(of: dictee.ecoute) { _, ecoute in
            guard !ecoute, !dictee.transcription.isEmpty else { return }
            let texte = dictee.transcription
            Task {
                let chantier = modele.enCours.map { "Chantier \($0.chantier) : " } ?? ""
                let r = await app.saisie?.transmettre(demande: "[Pour l’agent Chantiers] Remarque de \(modele.feuille.ouvrier). \(chantier)\(texte)")
                app.toast = Toast(r == .transmise ? "Remarque transmise au bureau." : "Gardée : partira au retour du réseau.")
            }
        }
        .toast(Binding(get: { app.toast }, set: { app.toast = $0 }))
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: Espace.xxs) {
            Text(DateEndry.longue(Date()).capitalizedPremiere).styleSurtitre()
            Text("Bonjour, \(modele.feuille.ouvrier)")
                .styleTitre(32, relativeTo: .largeTitle)
                .foregroundStyle(Color.encre)
            Text("\(app.session.entreprise) · équipe").styleTexte(14).foregroundStyle(Color.encreDouce)
        }
        .padding(.top, Espace.l)
    }

    private func carteEnCours(_ p: Pointage) -> some View {
        HStack(spacing: Espace.m) {
            VStack(alignment: .leading, spacing: 4) {
                Label("En cours", systemImage: "timer").styleTexte(12, relativeTo: .caption, graisse: .semibold).foregroundStyle(Color.or)
                Text(p.chantier).styleTexte(16, graisse: .semibold).foregroundStyle(Color.orClair).lineLimit(2)
                Text(p.debut, style: .timer)
                    .font(Police.chiffres(28, relativeTo: .title))
                    .foregroundStyle(Color.or)
                    .monospacedDigit()
            }
            Spacer()
            Button {
                withAnimation(.endry) { modele.arreter() }
                LiveActivitePointage.synchroniser(modele)
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.espressoProfond)
                    .frame(width: 56, height: 56)
                    .background(.degradeOr, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Arrêter le pointage"))
            .accessibilityIdentifier("arreter-pointage")
        }
        .padding(Espace.l)
        .background(MatiereEspresso(rayon: Espace.rayon))
    }

    private func carteChantier(_ c: ChantierEquipe) -> some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            HStack(alignment: .firstTextBaseline) {
                if let debut = c.debut { Text(debut).styleTexte(13, graisse: .semibold).foregroundStyle(Color.bronze) }
                Text(c.titre).styleTexte(17, graisse: .semibold).foregroundStyle(Color.encre)
            }
            if let client = c.client { Text(client).styleTexte(14).foregroundStyle(Color.encreDouce) }
            if let consignes = c.consignes {
                Label(consignes, systemImage: "exclamationmark.bubble")
                    .styleTexte(14)
                    .foregroundStyle(Color.encre)
                    .padding(Espace.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.or.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack(spacing: Espace.s) {
                if let adresse = c.adresse ?? c.lieu,
                   let url = URL(string: "maps://?daddr=\(adresse.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                    Link(destination: url) { Label("Itinéraire", systemImage: "car.fill") }
                        .styleTexte(13, graisse: .semibold).foregroundStyle(Color.bronze)
                }
                if let tel = c.telephone, let url = URL(string: "tel:\(tel.filter { $0.isNumber || $0 == "+" })") {
                    Link(destination: url) { Label(c.contact ?? "Appeler", systemImage: "phone.fill") }
                        .styleTexte(13, graisse: .semibold).foregroundStyle(Color.bronze)
                }
                Spacer()
                let actif = modele.enCours?.chantierId == c.id
                Button {
                    withAnimation(.endry) { actif ? modele.arreter() : modele.commencer(c) }
                    LiveActivitePointage.synchroniser(modele)
                } label: {
                    Text(actif ? "Arrêter" : "Commencer ici")
                        .styleTexte(14, graisse: .semibold)
                        .foregroundStyle(actif ? Color.orClair : Color.espressoProfond)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(actif ? AnyShapeStyle(Color.espresso) : AnyShapeStyle(.degradeOr), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("commencer-\(c.id)")
            }
            let heures = modele.feuille.heuresParChantier().first { $0.chantierId == c.id }?.heures ?? 0
            if heures > 0 {
                Text("Aujourd’hui : \(FormatSuisse.heures(heures))").styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
            }
        }
        .padding(Espace.m)
        .surfaceCarte(rayon: 20)
        .sensoryFeedback(.selection, trigger: modele.enCours?.chantierId)
    }

    private var outils: some View {
        VStack(alignment: .leading, spacing: Espace.s) {
            EnTeteSection(titre: "Sur le chantier")
            HStack(spacing: Espace.s) {
                BoutonMicroCompact(ecoute: dictee.ecoute, niveau: dictee.niveau) { Task { await dictee.basculer() } }
                VStack(alignment: .leading, spacing: 2) {
                    Text(dictee.ecoute ? (dictee.transcription.isEmpty ? "J’écoute…" : dictee.transcription) : "Dicter une remarque au bureau")
                        .styleTexte(14, graisse: .medium).lineLimit(3)
                    Text("Matériel manquant, problème, question.").styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
                }
            }
            .padding(Espace.m)
            .surfaceCarte(rayon: 20)
            SectionTerrain(titre: "Photos du chantier", icone: "camera") {
                PhotosTerrain(photos: $photos, prefixe: "chantier")
                if !photos.isEmpty {
                    Button {
                        Task { await envoyerPhotos() }
                    } label: {
                        Label(envoiPhotos ? "Envoi…" : "Envoyer \(photos.count) photo\(photos.count > 1 ? "s" : "")", systemImage: "paperplane")
                    }
                    .buttonStyle(BoutonSecondaire())
                    .disabled(envoiPhotos)
                }
            }
            Button {
                app.ouvrirOutil(.bonLivraison)
            } label: {
                Label("Scanner un bon de livraison", systemImage: "shippingbox.fill")
            }
            .buttonStyle(BoutonSecondaire())
        }
    }

    private func envoyerPhotos() async {
        guard let saisie = app.saisie else { return }
        envoiPhotos = true
        let chantier = modele.enCours?.chantier ?? modele.chantiers.first?.titre ?? ""
        let pieces = photos.map { PieceSaisie(nom: $0.nomFichier, typeMIME: $0.typeMIME, donnees: $0.donnees, origine: .photo) }
        saisie.recommencer()
        saisie.texte = "[Pour l’agent Chantiers] Photos de \(modele.feuille.ouvrier)\(chantier.isEmpty ? "" : ", chantier \(chantier)")."
        for p in pieces { saisie.ajouter(p) }
        await saisie.envoyer()
        envoiPhotos = false
        if case .erreur(let m) = saisie.etat { app.toast = Toast(m, style: .erreur) } else {
            app.toast = Toast(saisie.etat == .enAttente ? "Photos gardées : elles partiront au retour du réseau." : "Photos transmises.")
            photos = []
        }
        saisie.recommencer()
    }
}

/// Récapitulatif de la journée : heures par chantier (corrigeables), remarques, envoi.
struct JourneeOuvrierView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    var modele: ModeleEquipe
    @State private var envoi = false
    @State private var resultat: ModeleSaisie.ResultatTerrain?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.m) {
                    if let resultat {
                        ResultatEnvoiTerrain(resultat: resultat) { fermer() }
                    } else {
                        Text("Total \(FormatSuisse.heures(modele.feuille.total()))")
                            .styleTitre(34, relativeTo: .largeTitle).foregroundStyle(Color.encre)
                        SectionTerrain(titre: "Heures", icone: "clock") {
                            ForEach(Array(modele.feuille.heuresParChantier().enumerated()), id: \.offset) { _, ligne in
                                HStack {
                                    Text(ligne.chantier).styleTexte(15).lineLimit(2)
                                    Spacer()
                                    Text(FormatSuisse.heures(ligne.heures)).styleTexte(15, graisse: .semibold).monospacedDigit()
                                    Stepper("", onIncrement: { modele.corriger(chantierId: ligne.chantierId, heures: ligne.heures + 0.25) },
                                            onDecrement: { modele.corriger(chantierId: ligne.chantierId, heures: max(0, ligne.heures - 0.25)) })
                                        .labelsHidden()
                                }
                            }
                            Text("Arrondi au quart d’heure. Corrigez si vous avez oublié de pointer.")
                                .styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
                        }
                        SectionTerrain(titre: "Remarques", icone: "text.bubble") {
                            TextField("Matériel manquant, avancement…", text: Binding(get: { modele.remarques }, set: { modele.remarques = $0 }),
                                      axis: .vertical)
                                .styleTexte(15).lineLimit(2...6)
                        }
                        Button {
                            Task {
                                envoi = true
                                let r = await app.transmettre(modele.feuille.envoi())
                                envoi = false
                                if case .refusee = r {} else { modele.marquerEnvoyee() }
                                withAnimation(.endry) { resultat = r }
                            }
                        } label: {
                            HStack(spacing: Espace.xs) {
                                if envoi { ProgressView().tint(Color.fond) } else { Image(systemName: "paperplane.fill") }
                                Text(envoi ? "Envoi…" : "Envoyer au bureau")
                            }
                        }
                        .buttonStyle(BoutonPrincipal())
                        .disabled(envoi)
                        .accessibilityIdentifier("envoyer-journee-confirmer")
                    }
                }
                .padding(Espace.bord)
            }
            .background(FondAmbiant())
            .navigationTitle("Ma journée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { fermer() } } }
        }
    }
}

// MARK: - Côté patron : inviter un ouvrier

struct CarteEquipe: View {
    @State private var invitation = false

    var body: some View {
        Button { invitation = true } label: {
            HStack(spacing: Espace.m) {
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.bronze)
                    .frame(width: 44, height: 44)
                    .background(Color.or.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inviter un ouvrier").styleTexte(16, graisse: .semibold).foregroundStyle(Color.encre)
                    Text("Ses chantiers du jour, ses heures, ses photos. Jamais l’argent.")
                        .styleTexte(13, relativeTo: .footnote).foregroundStyle(Color.encreDouce)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Color.encrePale)
            }
            .padding(Espace.m)
            .surfaceCarte(rayon: 20)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inviter-ouvrier")
        .sheet(isPresented: $invitation) { InvitationOuvrierView() }
    }
}

struct InvitationOuvrierView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer
    @State private var nom = ""
    @State private var envoi = false
    @State private var invitation: InvitationEquipe?
    @State private var erreur: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.m) {
                    if let invitation, let lien = invitation.lien {
                        Text("Lien pour \(nom)").styleTitre(26, relativeTo: .title).foregroundStyle(Color.encre)
                        if let qr = Self.qr(lien) {
                            Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                                .frame(maxWidth: 240)
                                .padding(Espace.m)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel(Text("QR code du lien d’équipe"))
                        }
                        Text("L’ouvrier scanne ce code avec l’appareil photo de son iPhone, ou ouvre le lien reçu.")
                            .styleTexte(14).foregroundStyle(Color.encreDouce)
                        ShareLink(item: lien, message: Text("Votre accès Endry (équipe). À ouvrir sur votre iPhone.")) {
                            Label("Envoyer le lien", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(BoutonPrincipal())
                        if let m = invitation.message { Text(m).styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale) }
                    } else {
                        Text("Un lien à usage unique, propre à cet ouvrier. Il verra ses chantiers du jour et enverra ses heures et ses photos ; jamais l’argent, les décisions ni les agents. Révocable dans Appareils.")
                            .styleTexte(14).foregroundStyle(Color.encreDouce)
                        TextField("Prénom de l’ouvrier", text: $nom)
                            .textContentType(.givenName)
                            .styleTexte(17, graisse: .medium)
                            .padding(Espace.s)
                            .surfaceCarte(rayon: 14)
                        if let erreur { Label(erreur, systemImage: "exclamationmark.triangle").foregroundStyle(Color.rouille) }
                        Button {
                            Task { await creer() }
                        } label: {
                            HStack(spacing: Espace.xs) {
                                if envoi { ProgressView().tint(Color.fond) }
                                Text(envoi ? "Création…" : "Créer le lien")
                            }
                        }
                        .buttonStyle(BoutonPrincipal())
                        .disabled(envoi || nom.trimmingCharacters(in: .whitespaces).count < 2)
                    }
                }
                .padding(Espace.bord)
            }
            .background(FondAmbiant())
            .navigationTitle("Équipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { fermer() } } }
        }
    }

    private func creer() async {
        guard let api = app.session.api else { return }
        envoi = true
        erreur = nil
        do throws(ErreurAPI) {
            invitation = try await api.inviterOuvrier(nom: nom.trimmingCharacters(in: .whitespaces))
        } catch .serveur(let statut, _) where statut == 404 || statut == 405 {
            erreur = "Le PC ne crée pas encore de liens d’équipe (contrat v1.3 à appliquer)."
        } catch {
            erreur = error.message
        }
        envoi = false
    }

    static func qr(_ texte: String) -> UIImage? {
        let filtre = CIFilter.qrCodeGenerator()
        filtre.message = Data(texte.utf8)
        filtre.correctionLevel = "M"
        guard let image = filtre.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
