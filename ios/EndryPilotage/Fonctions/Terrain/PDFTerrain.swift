import EndryKit
import UIKit

/// Documents PDF produits sur l'iPhone (bon de régie signé). Aucun prix : le client signe le travail, pas un montant.
enum PDFTerrain {
    private static let page = CGRect(x: 0, y: 0, width: 595, height: 842)
    private static let marge: CGFloat = 48

    static func regie(_ bon: BonRegie, signature: Data?, entreprise: String) -> Data {
        UIGraphicsPDFRenderer(bounds: page).pdfData { contexte in
            contexte.beginPage()
            var y: CGFloat = marge
            let largeur = page.width - 2 * marge
            let or = UIColor(red: 0.62, green: 0.45, blue: 0.16, alpha: 1)
            let encre = UIColor(red: 0.14, green: 0.12, blue: 0.09, alpha: 1)
            let pale = UIColor(red: 0.43, green: 0.41, blue: 0.39, alpha: 1)

            func police(_ taille: CGFloat, serif: Bool = false, gras: Bool = false) -> UIFont {
                if serif, let f = UIFont(name: gras ? "CormorantGaramond-SemiBold" : "CormorantGaramond-Medium", size: taille) { return f }
                return .systemFont(ofSize: taille, weight: gras ? .semibold : .regular)
            }
            @discardableResult
            func texte(_ s: String, _ f: UIFont, _ c: UIColor = encre, x: CGFloat = marge, largeurMax: CGFloat? = nil) -> CGFloat {
                let attributs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: c]
                let l = largeurMax ?? largeur
                let h = (s as NSString).boundingRect(with: CGSize(width: l, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin], attributes: attributs, context: nil).height
                (s as NSString).draw(with: CGRect(x: x, y: y, width: l, height: h), options: [.usesLineFragmentOrigin],
                                     attributes: attributs, context: nil)
                return ceil(h)
            }
            func filet(_ couleur: UIColor = or, epaisseur: CGFloat = 0.6) {
                couleur.setFill()
                UIRectFill(CGRect(x: marge, y: y, width: largeur, height: epaisseur))
            }
            func nouvellePageSiBesoin(_ hauteur: CGFloat) {
                if y + hauteur > page.height - marge - 150 {
                    contexte.beginPage()
                    y = marge
                }
            }

            // En-tête
            y += texte(entreprise.uppercased(), police(11, gras: true), or)
            y += 2
            y += texte("Bon de régie", police(30, serif: true, gras: true))
            y += 4
            y += texte("N° \(bon.numero) · \(DateEndry.courte(bon.date))", police(11), pale)
            y += 12
            filet()
            y += 16

            // Chantier
            let lieu = [bon.client, bon.lieu].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            y += texte("CHANTIER", police(9, gras: true), or)
            y += 3
            y += texte(bon.chantier.isEmpty ? bon.client : bon.chantier, police(15, gras: true))
            if !lieu.isEmpty { y += texte(lieu, police(11), pale) }
            y += 16

            // Travaux
            y += texte("TRAVAUX RÉALISÉS", police(9, gras: true), or)
            y += 4
            y += texte(bon.travaux.isEmpty ? "—" : bon.travaux, police(12))
            y += 16

            // Heures
            if !bon.heures.isEmpty {
                nouvellePageSiBesoin(40 + CGFloat(bon.heures.count) * 18)
                y += texte("HEURES", police(9, gras: true), or)
                y += 6
                for h in bon.heures {
                    texte(h.intervenant, police(12))
                    y += texte(FormatSuisse.heures(h.heures), police(12, gras: true), encre, x: page.width - marge - 120, largeurMax: 120)
                    y += 2
                }
                filet(pale.withAlphaComponent(0.4), epaisseur: 0.4)
                y += 4
                texte("Total", police(12, gras: true))
                y += texte(FormatSuisse.heures(bon.totalHeures), police(12, gras: true), encre, x: page.width - marge - 120, largeurMax: 120)
                y += 16
            }

            // Matériel
            if !bon.materiel.isEmpty {
                nouvellePageSiBesoin(40 + CGFloat(bon.materiel.count) * 18)
                y += texte("MATÉRIEL", police(9, gras: true), or)
                y += 6
                for m in bon.materiel {
                    texte("\(FormatQuantite.texte(m.quantite)) \(m.unite)", police(12, gras: true), encre, x: marge, largeurMax: 70)
                    y += texte(m.designation, police(12), encre, x: marge + 76, largeurMax: largeur - 76)
                    y += 2
                }
                y += 14
            }

            y += texte(bon.deplacement ? "Déplacement compté." : "Sans déplacement.", police(11), pale)
            if !bon.remarques.isEmpty {
                y += 6
                y += texte("Remarques : \(bon.remarques)", police(11), pale)
            }
            y += 22

            // Signature
            nouvellePageSiBesoin(150)
            filet()
            y += 12
            y += texte("SIGNATURE DU CLIENT", police(9, gras: true), or)
            y += 6
            if let signature, let image = UIImage(data: signature) {
                let h: CGFloat = 80
                let l = min(largeur * 0.6, image.size.width / max(image.size.height, 1) * h)
                image.draw(in: CGRect(x: marge, y: y, width: l, height: h))
                y += h + 6
            }
            if let signataire = bon.signataire, let signeLe = bon.signeLe, let d = DateEndry.lire(signeLe) {
                y += texte("\(signataire) — signé le \(DateEndry.courte(d)) à \(DateEndry.heure(d))", police(11), pale)
            }
            y += 10
            texte("Le client confirme les travaux, les heures et le matériel ci-dessus. La facture suivra ; ce bon ne mentionne aucun prix.",
                  police(9), pale)
        }
    }
}
