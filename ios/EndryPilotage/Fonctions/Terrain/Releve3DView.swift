import EndryKit
import RoomPlan
import SwiftUI
import simd

/// Relevé d'une pièce : RoomPlan (LiDAR, iPhone Pro) mesure murs, portes, fenêtres et équipements (WC, baignoire,
/// lavabo…) ; l'app en tire surfaces, plan 2D et fichier 3D pour que le bureau prépare l'offre.
/// Sans LiDAR : relevé manuel (longueur, largeur, hauteur, équipements).
struct Releve3DView: View {
    @Environment(ModeleApp.self) private var app
    @Environment(\.dismiss) private var fermer

    @State private var chantierId: String?
    @State private var libre = ""
    @State private var piece = "Salle de bains"
    @State private var releve: ReleveMesures?
    @State private var usdz: Data?
    @State private var plan: Data?
    @State private var photos: [FormulaireMultipart.Fichier] = []
    @State private var capture = false
    @State private var manuel = ManuelReleve()
    @State private var envoi = false
    @State private var resultat: ModeleSaisie.ResultatTerrain?

    init(chantier: Dossier?) {
        _chantierId = State(initialValue: chantier?.id)
    }

    private var lidar: Bool { RoomCaptureSession.isSupported }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espace.m) {
                    if let resultat {
                        ResultatEnvoiTerrain(resultat: resultat) { fermer() }.padding(.top, Espace.l)
                    } else if let releve {
                        synthese(releve)
                    } else {
                        depart
                    }
                }
                .padding(.horizontal, Espace.bord)
                .padding(.bottom, Espace.xxl)
                .animation(.endry, value: resultat)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FondAmbiant())
            .navigationTitle("Relevé 3D")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { fermer() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { ClavierTerrain.fermer() }.fontWeight(.semibold)
                }
            }
        }
        .fullScreenCover(isPresented: $capture) {
            CaptureRoomPlan { salle in
                capture = false
                if let salle { terminer(salle) }
            }
        }
    }

    // MARK: - Départ

    @ViewBuilder
    private var depart: some View {
        VStack(alignment: .leading, spacing: Espace.xxs) {
            Text("Relevé").styleSurtitre()
            Text(lidar ? "Filmez la pièce, les mesures se font seules." : "Mesures de la pièce")
                .styleTitre(28, relativeTo: .largeTitle).foregroundStyle(Color.encre)
        }
        .padding(.top, Espace.s)
        ChoixChantier(chantierId: $chantierId, libre: $libre)
        SectionTerrain(titre: "Pièce", icone: "square.split.bottomrightquarter") {
            TextField("Nom de la pièce", text: $piece).styleTexte(16, graisse: .medium)
        }
        if lidar {
            Text("Balayez lentement les murs, le sol et les équipements. Portes, fenêtres, WC, baignoire et lavabos sont reconnus.")
                .styleTexte(14).foregroundStyle(Color.encreDouce)
            Button { capture = true } label: { Label("Commencer le relevé", systemImage: "cube.transparent") }
                .buttonStyle(BoutonPrincipal())
                .accessibilityIdentifier("commencer-releve")
            DisclosureGroup("Relevé manuel") { formulaireManuel }
                .styleTexte(15, graisse: .semibold)
                .tint(Color.bronze)
        } else {
            Label("Le relevé 3D automatique demande un iPhone Pro (capteur LiDAR). Relevé manuel :", systemImage: "info.circle")
                .styleTexte(13, relativeTo: .footnote)
                .foregroundStyle(Color.encreDouce)
            formulaireManuel
        }
    }

    private var formulaireManuel: some View {
        SectionTerrain(titre: "Dimensions (m)", icone: "ruler") {
            ligneMesure("Longueur", valeur: $manuel.longueurTexte)
            ligneMesure("Largeur", valeur: $manuel.largeurTexte)
            ligneMesure("Hauteur", valeur: $manuel.hauteurTexte)
            Stepper("Portes : \(manuel.portes)", value: $manuel.portes, in: 0...6).styleTexte(15)
            Stepper("Fenêtres : \(manuel.fenetres)", value: $manuel.fenetres, in: 0...8).styleTexte(15)
            ForEach(ManuelReleve.equipementsProposes, id: \.self) { cat in
                Stepper("\(ReleveMesures.nomObjet(cat).capitalized) : \(manuel.equipements[cat, default: 0])",
                        value: Binding(get: { manuel.equipements[cat, default: 0] }, set: { manuel.equipements[cat] = $0 }), in: 0...6)
                    .styleTexte(15)
            }
            Button {
                releve = manuel.releve(piece: piece, chantierId: chantierId, chantier: nomChantier)
                plan = releve.flatMap { PlanPiece.png(murs: PlanPiece.rectangle(longueur: manuel.longueur, largeur: manuel.largeur), releve: $0) }
            } label: { Label("Calculer", systemImage: "function") }
                .buttonStyle(BoutonPrincipal())
                .disabled(manuel.longueur <= 0 || manuel.largeur <= 0)
                .accessibilityIdentifier("calculer-releve")
        }
    }

    /// Mesure en mètres : « 2,40 » comme « 2.40 ».
    private func ligneMesure(_ titre: String, valeur: Binding<String>) -> some View {
        HStack {
            Text(titre).styleTexte(15)
            Spacer()
            TextField("0,00", text: valeur)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .styleTexte(16, graisse: .semibold)
        }
    }

    // MARK: - Synthèse

    @ViewBuilder
    private func synthese(_ r: ReleveMesures) -> some View {
        VStack(alignment: .leading, spacing: Espace.xxs) {
            Text("Relevé · \(r.piece)").styleSurtitre()
            Text(r.surfaceSol.map { ReleveMesures.m2($0) } ?? "Relevé terminé")
                .styleTitre(34, relativeTo: .largeTitle).foregroundStyle(Color.encre)
        }
        .padding(.top, Espace.s)

        if let plan, let image = UIImage(data: plan) {
            Image(uiImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 260)
                .padding(Espace.m)
                .surfaceCarte()
                .accessibilityLabel(Text("Plan de la pièce"))
        }

        SectionTerrain(titre: "Mesures", icone: "ruler") {
            if let s = r.surfaceSol { LabeledContent("Sol", value: ReleveMesures.m2(s)) }
            LabeledContent("Périmètre", value: ReleveMesures.m(r.perimetre))
            if let h = r.hauteur { LabeledContent("Hauteur", value: ReleveMesures.m(h)) }
            LabeledContent("Murs (nets)", value: ReleveMesures.m2(r.surfaceMursNette))
            let portes = r.ouvertures.filter { $0.type == .porte }.count
            let fenetres = r.ouvertures.filter { $0.type == .fenetre }.count
            LabeledContent("Ouvertures", value: "\(portes) porte\(portes > 1 ? "s" : ""), \(fenetres) fenêtre\(fenetres > 1 ? "s" : "")")
        }
        .styleTexte(15)

        if !r.equipements.isEmpty {
            SectionTerrain(titre: "Équipements", icone: "shower") {
                ForEach(Array(r.equipements.enumerated()), id: \.offset) { _, e in
                    LabeledContent(e.nom.capitalized, value: "\(e.nombre)")
                }
            }
            .styleTexte(15)
        }

        ChoixChantier(chantierId: $chantierId, libre: $libre)
        SectionTerrain(titre: "Remarques", icone: "text.bubble") {
            TextField("Accès, état, souhaits du client…", text: Binding(get: { releve?.remarques ?? "" }, set: { releve?.remarques = $0 }),
                      axis: .vertical)
                .styleTexte(15)
                .lineLimit(2...6)
        }
        SectionTerrain(titre: "Photos", icone: "camera") {
            PhotosTerrain(photos: $photos, prefixe: "releve")
        }
        Button {
            Task { await transmettre() }
        } label: {
            HStack(spacing: Espace.xs) {
                if envoi { ProgressView().tint(Color.fond) } else { Image(systemName: "paperplane.fill") }
                Text(envoi ? "Transmission…" : "Transmettre pour l’offre")
            }
        }
        .buttonStyle(BoutonPrincipal())
        .disabled(envoi)
        .accessibilityIdentifier("transmettre-releve")
        if let usdz {
            Text("Fichier 3D joint (\(ByteCountFormatter.string(fromByteCount: Int64(usdz.count), countStyle: .file))).")
                .styleTexte(12, relativeTo: .caption).foregroundStyle(Color.encrePale)
        }
    }

    private var nomChantier: String? {
        app.dossier(chantierId)?.titre ?? (libre.isEmpty ? nil : libre)
    }

    private func terminer(_ salle: CapturedRoom) {
        let r = PlanPiece.releve(depuis: salle, piece: piece, chantierId: chantierId, chantier: nomChantier)
        releve = r
        plan = PlanPiece.png(murs: PlanPiece.segments(salle), releve: r)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("releve-\(UUID().uuidString).usdz")
        if (try? salle.export(to: url)) != nil {
            usdz = try? Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func transmettre() async {
        guard var r = releve else { return }
        r.chantierId = chantierId
        r.chantier = nomChantier
        envoi = true
        let resultatEnvoi = await app.transmettre(r.envoi(usdz: usdz, plan: plan, photos: photos))
        envoi = false
        withAnimation(.endry) { resultat = resultatEnvoi }
    }
}

// MARK: - Relevé manuel

struct ManuelReleve: Equatable {
    static let equipementsProposes = ["toilet", "sink", "bathtub", "washerDryer"]
    var longueurTexte = ""
    var largeurTexte = ""
    var hauteurTexte = "2,50"
    var longueur: Double { Double.depuisTexteSuisse(longueurTexte) ?? 0 }
    var largeur: Double { Double.depuisTexteSuisse(largeurTexte) ?? 0 }
    var hauteur: Double { Double.depuisTexteSuisse(hauteurTexte) ?? 2.5 }
    var portes = 1
    var fenetres = 0
    var equipements: [String: Int] = [:]

    func releve(piece: String, chantierId: String?, chantier: String?) -> ReleveMesures {
        let murs = [longueur, largeur, longueur, largeur].map { ReleveMesures.Mur(largeur: $0, hauteur: hauteur) }
        let ouvertures = Array(repeating: ReleveMesures.Ouverture(type: .porte, largeur: 0.8, hauteur: 2.0), count: portes)
            + Array(repeating: ReleveMesures.Ouverture(type: .fenetre, largeur: 0.8, hauteur: 1.0), count: fenetres)
        let objets = Self.equipementsProposes.flatMap { cat in
            Array(repeating: ReleveMesures.Objet(categorie: cat, largeur: 0, profondeur: 0, hauteur: 0), count: equipements[cat, default: 0])
        }
        let contour = [ReleveMesures.Point(x: 0, y: 0), .init(x: longueur, y: 0), .init(x: longueur, y: largeur), .init(x: 0, y: largeur)]
        return ReleveMesures(piece: piece, chantierId: chantierId, chantier: chantier, date: DateEndry.iso(Date()), murs: murs,
                             ouvertures: ouvertures, contourSol: contour, objets: objets, remarques: "Relevé manuel.")
    }
}

// MARK: - RoomPlan

/// Capture RoomPlan plein écran, avec l'interface d'Apple (guidage, aperçu 3D).
struct CaptureRoomPlan: View {
    var terminer: (CapturedRoom?) -> Void
    @State private var arreter = false

    var body: some View {
        ZStack(alignment: .top) {
            VueCaptureRoomPlan(arreter: $arreter, terminer: terminer)
                .ignoresSafeArea()
            HStack {
                Button("Annuler") { terminer(nil) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Terminer") { arreter = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.bronzeMoyen)
                    .disabled(arreter)
            }
            .padding()
        }
    }
}

struct VueCaptureRoomPlan: UIViewRepresentable {
    @Binding var arreter: Bool
    var terminer: (CapturedRoom?) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let vue = RoomCaptureView(frame: .zero)
        vue.delegate = context.coordinator
        vue.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return vue
    }

    func updateUIView(_ vue: RoomCaptureView, context: Context) {
        if arreter, !context.coordinator.arrete {
            context.coordinator.arrete = true
            vue.captureSession.stop()
        }
    }

    static func dismantleUIView(_ vue: RoomCaptureView, coordinator: CoordinateurRoomPlan) {
        vue.captureSession.stop()
    }

    func makeCoordinator() -> CoordinateurRoomPlan { CoordinateurRoomPlan(terminer: terminer) }
}

/// Délégué RoomPlan (le protocole exige NSCoding : nom Objective-C stable, classe de premier niveau).
@MainActor
@objc(EndryCoordinateurRoomPlan)
final class CoordinateurRoomPlan: NSObject {
    let terminer: (CapturedRoom?) -> Void
    var arrete = false

    init(terminer: @escaping (CapturedRoom?) -> Void) {
        self.terminer = terminer
    }

    nonisolated required init?(coder: NSCoder) { nil }
    nonisolated func encode(with coder: NSCoder) {}
}

extension CoordinateurRoomPlan: @preconcurrency RoomCaptureViewDelegate {
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool { true }

    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        terminer(error == nil ? processedResult : nil)
    }
}

// MARK: - Plan 2D et mesures

enum PlanPiece {
    typealias Segment = (a: CGPoint, b: CGPoint)

    /// Murs vus de dessus (x, z), en mètres.
    static func segments(_ salle: CapturedRoom) -> [Segment] {
        salle.walls.map { mur in
            let t = mur.transform
            let centre = SIMD2<Float>(t.columns.3.x, t.columns.3.z)
            let axe = simd_normalize(SIMD2<Float>(t.columns.0.x, t.columns.0.z))
            let demi = axe * (mur.dimensions.x / 2)
            let a = centre - demi, b = centre + demi
            return (CGPoint(x: CGFloat(a.x), y: CGFloat(a.y)), CGPoint(x: CGFloat(b.x), y: CGFloat(b.y)))
        }
    }

    static func rectangle(longueur: Double, largeur: Double) -> [Segment] {
        let p = [CGPoint(x: 0, y: 0), CGPoint(x: longueur, y: 0), CGPoint(x: longueur, y: largeur), CGPoint(x: 0, y: largeur)]
        return (0..<4).map { (p[$0], p[($0 + 1) % 4]) }
    }

    static func releve(depuis salle: CapturedRoom, piece: String, chantierId: String?, chantier: String?) -> ReleveMesures {
        let murs = salle.walls.map { ReleveMesures.Mur(largeur: Double($0.dimensions.x), hauteur: Double($0.dimensions.y)) }
        let ouvertures = salle.doors.map { ReleveMesures.Ouverture(type: .porte, largeur: Double($0.dimensions.x), hauteur: Double($0.dimensions.y)) }
            + salle.windows.map { ReleveMesures.Ouverture(type: .fenetre, largeur: Double($0.dimensions.x), hauteur: Double($0.dimensions.y)) }
            + salle.openings.map { ReleveMesures.Ouverture(type: .ouverture, largeur: Double($0.dimensions.x), hauteur: Double($0.dimensions.y)) }
        let objets = salle.objects.map {
            ReleveMesures.Objet(categorie: String(describing: $0.category), largeur: Double($0.dimensions.x),
                                profondeur: Double($0.dimensions.z), hauteur: Double($0.dimensions.y))
        }
        var contour: [ReleveMesures.Point] = []
        if let sol = salle.floors.first {
            contour = sol.polygonCorners.map { coin in
                let monde = sol.transform * SIMD4<Float>(coin.x, coin.y, coin.z, 1)
                return ReleveMesures.Point(x: Double(monde.x), y: Double(monde.z))
            }
        }
        return ReleveMesures(piece: piece, chantierId: chantierId, chantier: chantier, date: DateEndry.iso(Date()), murs: murs,
                             ouvertures: ouvertures, contourSol: contour, objets: objets)
    }

    /// Plan PNG : murs en encre, cotes des murs, sur papier clair.
    @MainActor
    static func png(murs: [Segment], releve: ReleveMesures) -> Data? {
        guard !murs.isEmpty else { return nil }
        let xs = murs.flatMap { [$0.a.x, $0.b.x] }, ys = murs.flatMap { [$0.a.y, $0.b.y] }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let taille = CGSize(width: 900, height: 700)
        let marge: CGFloat = 90
        let echelle = min((taille.width - 2 * marge) / max(maxX - minX, 0.1), (taille.height - 2 * marge) / max(maxY - minY, 0.1))
        func p(_ q: CGPoint) -> CGPoint {
            CGPoint(x: marge + (q.x - minX) * echelle + (taille.width - 2 * marge - (maxX - minX) * echelle) / 2,
                    y: marge + (q.y - minY) * echelle + (taille.height - 2 * marge - (maxY - minY) * echelle) / 2)
        }
        let rendu = UIGraphicsImageRenderer(size: taille)
        let image = rendu.image { ctx in
            UIColor(red: 0.965, green: 0.96, blue: 0.95, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: taille))
            let encre = UIColor(red: 0.14, green: 0.12, blue: 0.09, alpha: 1)
            let or = UIColor(red: 0.62, green: 0.45, blue: 0.16, alpha: 1)
            ctx.cgContext.setLineCap(.round)
            for m in murs {
                ctx.cgContext.setStrokeColor(encre.cgColor)
                ctx.cgContext.setLineWidth(9)
                ctx.cgContext.move(to: p(m.a))
                ctx.cgContext.addLine(to: p(m.b))
                ctx.cgContext.strokePath()
                let longueur = hypot(m.b.x - m.a.x, m.b.y - m.a.y)
                let milieu = CGPoint(x: (p(m.a).x + p(m.b).x) / 2, y: (p(m.a).y + p(m.b).y) / 2)
                let texte = ReleveMesures.m(Double(longueur)) as NSString
                let attributs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: or]
                let t = texte.size(withAttributes: attributs)
                texte.draw(at: CGPoint(x: milieu.x - t.width / 2, y: milieu.y - t.height - 10), withAttributes: attributs)
            }
            let titre = "\(releve.piece)\(releve.surfaceSol.map { " — " + ReleveMesures.m2($0) } ?? "")" as NSString
            titre.draw(at: CGPoint(x: 28, y: 22), withAttributes: [.font: UIFont.systemFont(ofSize: 26, weight: .bold), .foregroundColor: encre])
        }
        return image.pngData()
    }
}
