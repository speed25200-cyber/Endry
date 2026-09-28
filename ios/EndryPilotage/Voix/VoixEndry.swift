import AVFoundation
import EndryKit
import SwiftUI

/// Voix d'Endry : choisie parmi les voix françaises installées sur l'iPhone.
/// Les voix « Premium » et « Améliorée » sont bien plus naturelles que les voix compactes installées par défaut,
/// mais iOS les fait télécharger à la main (Réglages › Accessibilité › Contenu énoncé › Voix › Français).
enum VoixEndry {
    static let cle = "voix-endry"

    struct Option: Identifiable, Hashable {
        var id: String
        var nom: String
        var detail: String
        var qualite: Int
    }

    static func options() -> [Option] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("fr") }
            .map { v in
                let (libelle, q): (String, Int) = switch v.quality {
                case .premium: ("Premium", 2)
                case .enhanced: ("Améliorée", 1)
                default: ("Compacte", 0)
                }
                let pays = Locale(identifier: "fr_CH").localizedString(forRegionCode: String(v.language.suffix(2))) ?? v.language
                return Option(id: v.identifier, nom: v.name, detail: "\(libelle) · \(pays)", qualite: q)
            }
            .sorted { ($0.qualite, $0.nom) > ($1.qualite, $1.nom) }
    }

    /// Vrai si seules des voix compactes sont installées : la voix d'Endry sonnera robotique.
    static var seulementCompactes: Bool { options().allSatisfy { $0.qualite == 0 } }
}

/// Réglages › Voix d'Endry : choix, essai, et comment installer une voix naturelle.
struct ReglageVoixEndry: View {
    @AppStorage(VoixEndry.cle) private var choisie = ""
    @AppStorage(ReglageVoix.cleEnvoiDirect) private var envoiDirect = true
    @AppStorage(ReglageVoix.cleDebit) private var debit = 1.02
    @AppStorage(ReglageVoix.cleLectureComplete) private var lectureComplete = false
    @AppStorage(ReglageVoix.clePatience) private var patience = 1.0
    @AppStorage(ReglageVoix.cleConversationContinue) private var conversationContinue = true
    @AppStorage(ReglageVoix.cleReponseAuToucher) private var reponseAuToucher = false
    @State private var options: [VoixEndry.Option] = []
    @State private var synthese = AVSpeechSynthesizer()

    var body: some View {
        Section {
            Picker(selection: $choisie) {
                Text("Automatique (la meilleure installée)").tag("")
                ForEach(options) { option in
                    Text("\(option.nom) — \(option.detail)").tag(option.id)
                }
            } label: {
                Label("Voix d’Endry", systemImage: "waveform")
            }
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("choix-voix")
            Picker(selection: $debit) {
                ForEach(ReglageVoix.debits, id: \.valeur) { d in
                    Text(d.libelle).tag(d.valeur)
                }
            } label: {
                Label("Débit", systemImage: "speedometer")
            }
            .onChange(of: debit) { essayer() }
            .accessibilityIdentifier("debit-voix")
            Button {
                essayer()
            } label: {
                Label("Écouter", systemImage: "play.circle")
            }
            Toggle(isOn: $conversationContinue) {
                Label("Conversation continue", systemImage: "waveform.and.mic")
            }
            .accessibilityIdentifier("conversation-continue")
            Picker(selection: $patience) {
                ForEach(FinDePhrase.patiences, id: \.valeur) { p in
                    Text(p.libelle).tag(p.valeur)
                }
            } label: {
                Label("Temps avant la réponse", systemImage: "hourglass")
            }
            .disabled(reponseAuToucher)
            .accessibilityIdentifier("patience-voix")
            Toggle(isOn: $reponseAuToucher) {
                Label("Répondre seulement quand je touche la sphère", systemImage: "hand.tap")
            }
            .accessibilityIdentifier("reponse-au-toucher")
            Toggle(isOn: $lectureComplete) {
                Label("Lire les longues réponses en entier", systemImage: "text.alignleft")
            }
            .accessibilityIdentifier("lecture-complete")
            Toggle(isOn: $envoiDirect) {
                Label("Envoi direct au bureau", systemImage: "paperplane")
            }
            .accessibilityIdentifier("envoi-direct")
        } header: {
            Text("Voix d’Endry")
        } footer: {
            Text(VoixEndry.seulementCompactes
                 ? "Seules des voix compactes (robotiques) sont installées. Pour une voix naturelle : Réglages › Accessibilité › Contenu énoncé › Voix › Français, puis téléchargez une voix « Premium » ou « Améliorée ». Elle apparaîtra ici."
                 : "Les voix « Premium » et « Améliorée » sont les plus naturelles. D’autres se téléchargent dans Réglages › Accessibilité › Contenu énoncé › Voix › Français.")
                + Text("\n\nEnvoi direct : ce que vous dites part aussitôt au bureau, comme dans une conversation (un instant pour annuler). Les Oui et les envois aux clients gardent toujours leur geste à l’écran.")
                + Text("\n\nConversation continue : le micro reste ouvert pendant qu’Endry parle ; parlez pour le couper, comme avec quelqu’un. Si vous reprenez la parole juste après sa réponse, il comprend que vous continuiez votre phrase.")
                + Text("\n\nEndry vous coupe la parole ? Choisissez « Long », ou « Répondre seulement quand je touche la sphère » : vous parlez avec toutes les pauses que vous voulez, puis vous touchez la sphère. Dans tous les cas, toucher la sphère pendant que vous parlez fait répondre Endry tout de suite.")
                + Text("\n\nLongues réponses : Endry en dit le début, le détail reste à l’écran et dans la conversation. Pendant la conversation, dites « répète », « plus lentement », « plus vite », « ouvre la conversation », « on change de sujet » ou « merci, c’est tout ».")
        }
        .onAppear { options = VoixEndry.options() }
    }

    private func essayer() {
        if synthese.isSpeaking { synthese.stopSpeaking(at: .immediate) }
        let enonce = AVSpeechUtterance(string: "Bonjour, je suis Endry. Trois décisions vous attendent aujourd’hui.")
        enonce.voice = MoteurLocal.meilleureVoix()
        enonce.rate = min(AVSpeechUtteranceDefaultSpeechRate * Float(debit), AVSpeechUtteranceMaximumSpeechRate)
        enonce.pitchMultiplier = 0.98
        synthese.speak(enonce)
    }
}
