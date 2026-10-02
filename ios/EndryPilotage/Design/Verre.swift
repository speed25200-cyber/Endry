import EndryKit
import SwiftUI

extension View {
    /// Verre : Liquid Glass sur iOS 26, matériau `.ultraThinMaterial` avant.
    @ViewBuilder
    func verre<S: Shape>(_ forme: S, interactif: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(interactif ? Glass.regular.interactive() : Glass.regular, in: forme)
        } else {
            background(.ultraThinMaterial, in: forme)
                .overlay(forme.stroke(Color.bordureOr, lineWidth: Espace.filet))
        }
        #else
        background(.ultraThinMaterial, in: forme)
            .overlay(forme.stroke(Color.bordureOr, lineWidth: Espace.filet))
        #endif
    }
}

// MARK: - Onglets

enum Onglet: String, CaseIterable, Identifiable, Hashable {
    case aujourdhui, chantiers, saisie, finances, entreprise

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .aujourdhui: "Accueil"
        case .chantiers: "Chantiers"
        case .saisie: "Dicter"
        case .finances: "Finances"
        case .entreprise: "Bureau"
        }
    }

    var icone: String {
        switch self {
        case .aujourdhui: "square.grid.2x2"
        case .chantiers: "calendar"
        case .saisie: "mic"
        case .finances: "chart.line.uptrend.xyaxis"
        case .entreprise: "circle.circle"
        }
    }

    var iconeActive: String {
        switch self {
        case .aujourdhui: "square.grid.2x2.fill"
        case .chantiers: "calendar"
        case .saisie: "mic.fill"
        case .finances: "chart.line.uptrend.xyaxis"
        case .entreprise: "circle.circle.fill"
        }
    }
}

/// Barre Maison Endry : capsule de verre (64 pt), loupe qui glisse d'un onglet à l'autre, orbe au centre.
/// L'orbe est posé au-dessus du verre, jamais dedans : le verre ne se recalcule pas à chaque image de l'orbe.
/// Orbe : toucher = parler à Endry (relais vers le bureau) ; toucher long = dicter une saisie terrain.
struct BarreOnglets: View {
    @Binding var selection: Onglet
    var badgeDecisions: Int
    /// Toucher de l'orbe : assistant vocal plein écran.
    var ouvrirAssistant: () -> Void = {}
    @Namespace private var loupe
    @Environment(\.accessibilityReduceMotion) private var reduireAnimations

    var body: some View {
        HStack(spacing: 0) {
            bouton(.aujourdhui)
            bouton(.chantiers)
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            bouton(.finances)
            bouton(.entreprise)
        }
        .padding(.horizontal, 6)
        .frame(height: 64)
        .background { FondBarre() }
        .overlay {
            BoutonOrbe(actif: selection == .saisie, ouvrirAssistant: ouvrirAssistant) {
                withAnimation(.endry(reduire: reduireAnimations)) { selection = .saisie }
            }
        }
        .padding(.horizontal, Espace.m)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func bouton(_ onglet: Onglet) -> some View {
        let actif = selection == onglet
        return Button {
            withAnimation(reduireAnimations ? .fonduDoux : .spring(response: 0.36, dampingFraction: 0.8)) {
                selection = onglet
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: actif ? onglet.iconeActive : onglet.icone)
                    .font(.system(size: 18, weight: .light))
                    .frame(height: 20)
                Text(onglet.titre)
                    .font(.system(size: 9.5, weight: actif ? .medium : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(actif ? Color.encre : Color.encreDouce)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                // Loupe : une seule forme qui glisse d'onglet en onglet.
                if actif {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.lentille)
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(Color.filet, lineWidth: Espace.filet)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [Color.refletBord, .clear], startPoint: .topLeading, endPoint: .center),
                                              lineWidth: 1)
                                .opacity(0.5)
                        }
                        .matchedGeometryEffect(id: "loupe", in: loupe)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(Text(onglet == .aujourdhui && badgeDecisions > 0 ? "\(onglet.titre), \(badgeDecisions) décisions en attente" : onglet.titre))
        .accessibilityAddTraits(actif ? .isSelected : [])
        .accessibilityIdentifier("onglet-\(onglet.rawValue)")
    }
}

/// Fond de la barre : verre (Liquid Glass sur iOS 26), teinte crème, filet et ombre portée.
private struct FondBarre: View {
    var body: some View {
        Capsule()
            .fill(Color.verreTeinte)
            .background { Color.clear.verre(Capsule()) }
            .overlay { Capsule().strokeBorder(Color.filet, lineWidth: Espace.filet) }
            .overlay {
                Capsule()
                    .strokeBorder(LinearGradient(colors: [Color.refletBord, .clear], startPoint: .topLeading, endPoint: .center),
                                  lineWidth: 1)
                    .opacity(0.5)
            }
            .shadow(color: Color.ombre, radius: 20, y: 14)
    }
}

/// L'orbe d'Endry au centre de la barre. Toucher : parler à Endry. Toucher long : dicter une saisie terrain.
struct BoutonOrbe: View {
    var actif: Bool
    var ouvrirAssistant: () -> Void
    var dicter: () -> Void
    @State private var presse = false
    @State private var appuiLongDeclenche = false
    @State private var dictee = 0

    var body: some View {
        Button {
            // Après un toucher long (dictée ouverte), le relâchement n'ouvre pas l'assistant.
            if appuiLongDeclenche {
                appuiLongDeclenche = false
                return
            }
            ouvrirAssistant()
        } label: {
            OrbeSiri(diametre: 52, actif: actif || presse)
                .shadow(color: Color.ombre, radius: 12, y: 8)
                .overlay(Circle().strokeBorder(Color.filet, lineWidth: Espace.filet))
                .scaleEffect(presse ? 1.06 : 1)
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    appuiLongDeclenche = true
                    dictee += 1
                    dicter()
                }
        )
        .onLongPressGesture(minimumDuration: 0.45, perform: {}, onPressingChanged: { enCours in
            withAnimation(.endryVif) { presse = enCours }
        })
        .sensoryFeedback(.impact(weight: .medium), trigger: dictee)
        .accessibilityLabel(Text("Parler à Endry"))
        .accessibilityHint(Text("Toucher long : dicter une saisie terrain."))
        .accessibilityAction(named: Text("Dicter une saisie terrain")) { dicter() }
        .accessibilityIdentifier("parler-endry")
    }
}

// MARK: - Toasts

struct ToastView: View {
    var toast: Toast

    var body: some View {
        HStack(spacing: Espace.s) {
            Image(systemName: icone)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(couleur)
                .symbolEffect(.bounce, value: toast.id)
            Text(toast.message)
                .styleTexte(15, relativeTo: .subheadline, graisse: .medium)
                .foregroundStyle(Color.encre)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Espace.m)
        .padding(.vertical, 12)
        .frame(maxWidth: 560)
        // Bandeau aux coins arrondis : une capsule devient une bulle ronde dès que le texte fait plusieurs lignes.
        .verre(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.ombre, radius: 18, y: 8)
        .padding(.horizontal, Espace.l)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    private var icone: String {
        switch toast.style {
        case .succes: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .erreur: "exclamationmark.circle.fill"
        }
    }

    private var couleur: Color {
        switch toast.style {
        case .succes: .vertControle
        case .info: .bronze
        case .erreur: .rouille
        }
    }
}

extension View {
    /// Affiche le toast au-dessus de la barre d'onglets et le retire après quelques secondes.
    func toast(_ toast: Binding<Toast?>, decalageBas: CGFloat = 96) -> some View {
        overlay(alignment: .bottom) {
            ZStack {
                if let valeur = toast.wrappedValue {
                    ToastView(toast: valeur)
                        .id(valeur.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.92)))
                        .task(id: valeur.id) {
                            try? await Task.sleep(for: .seconds(valeur.style == .erreur ? 4.5 : 2.8))
                            withAnimation(.endry) {
                                if toast.wrappedValue?.id == valeur.id { toast.wrappedValue = nil }
                            }
                        }
                        .onTapGesture { withAnimation(.endry) { toast.wrappedValue = nil } }
                }
            }
            .padding(.bottom, decalageBas)
            .animation(.endry, value: toast.wrappedValue?.id)
        }
    }
}
