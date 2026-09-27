import AVFoundation
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
            Button {
                essayer()
            } label: {
                Label("Écouter", systemImage: "play.circle")
            }
        } header: {
            Text("Voix d’Endry")
        } footer: {
            Text(VoixEndry.seulementCompactes
                 ? "Seules des voix compactes (robotiques) sont installées. Pour une voix naturelle : Réglages › Accessibilité › Contenu énoncé › Voix › Français, puis téléchargez une voix « Premium » ou « Améliorée ». Elle apparaîtra ici."
                 : "Les voix « Premium » et « Améliorée » sont les plus naturelles. D’autres se téléchargent dans Réglages › Accessibilité › Contenu énoncé › Voix › Français.")
        }
        .onAppear { options = VoixEndry.options() }
    }

    private func essayer() {
        if synthese.isSpeaking { synthese.stopSpeaking(at: .immediate) }
        let enonce = AVSpeechUtterance(string: "Bonjour, je suis Endry. Trois décisions vous attendent aujourd’hui.")
        enonce.voice = MoteurLocal.meilleureVoix()
        enonce.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        enonce.pitchMultiplier = 0.98
        synthese.speak(enonce)
    }
}
