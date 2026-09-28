import Foundation

/// Un résultat de la recherche globale (⌘F, loupe d'Aujourd'hui).
public struct ResultatRecherche: Identifiable, Hashable, Sendable {
    public enum Genre: String, Sendable, CaseIterable {
        case decision, chantier, facture, offre, fournisseur, message

        public var libelle: String {
            switch self {
            case .decision: "Décisions"
            case .chantier: "Chantiers"
            case .facture: "Factures"
            case .offre: "Offres"
            case .fournisseur: "Fournisseurs"
            case .message: "Conversation"
            }
        }
    }

    /// Où mène le résultat.
    public enum Cible: Hashable, Sendable {
        case decision(String)
        case chantier(String)
        case document(chemin: String, nom: String)
        case conversation
        case aucune
    }

    public var id: String
    public var genre: Genre
    public var titre: String
    public var detail: String
    public var cible: Cible
    public var score: Int
}

/// Recherche dans ce que l'iPhone connaît déjà (données en cache et fil de conversation) : instantanée,
/// sans réseau. Tous les mots tapés doivent se retrouver ; un mot qui commence un mot compte davantage.
public enum RechercheGlobale {
    /// `nil` : un mot de la requête ne se trouve nulle part.
    public static func score(_ champs: [String?], requete: String, titre: String? = nil) -> Int? {
        let mots = RepondeurLocal.normaliser(requete).split(separator: " ").map(String.init)
        guard !mots.isEmpty else { return nil }
        let texte = " " + RepondeurLocal.normaliser(champs.compactMap { $0 }.joined(separator: " ")) + " "
        var total = 0
        for mot in mots {
            if texte.contains(" " + mot) {
                total += 3
            } else if texte.contains(mot) {
                total += 1
            } else {
                return nil
            }
        }
        if let titre, RepondeurLocal.normaliser(titre).hasPrefix(RepondeurLocal.normaliser(requete)) { total += 4 }
        return total
    }

    public static func chercher(_ requete: String, cartes: [Carte] = [], chantiers: [Dossier] = [], argent: Argent? = nil,
                                messages: [MessageConversation] = [], fournisseurs: Bool = true,
                                limite: Int = 40) -> [ResultatRecherche] {
        guard !requete.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var resultats: [ResultatRecherche] = []

        for c in cartes {
            guard let s = score([c.titre, c.motif, c.reference, c.genre, c.destinataires.joined(separator: " "), c.texte],
                                requete: requete, titre: c.titre) else { continue }
            resultats.append(.init(id: "D:" + c.reference, genre: .decision, titre: c.titre,
                                   detail: "À décider · \(c.reference)", cible: .decision(c.reference), score: s + 2))
        }
        for d in chantiers {
            let nom = d.client.isEmpty ? d.titre : d.client
            guard let s = score([d.client, d.titre, d.lieu, d.id, d.etapeLibelle, d.note], requete: requete, titre: nom) else { continue }
            let detail = [d.titre == nom ? nil : d.titre, d.etapeLibelle, d.lieu].compactMap { $0 }.joined(separator: " · ")
            resultats.append(.init(id: "C:" + d.id, genre: .chantier, titre: nom, detail: detail, cible: .chantier(d.id), score: s + 1))
        }
        if let argent {
            for f in argent.encaisser.factures {
                guard let s = score([f.numero, f.client, f.titre], requete: requete, titre: f.numero) else { continue }
                let echeance = f.retardJours > 0 ? "\(f.retardJours) j de retard" : "à échoir"
                resultats.append(.init(id: "F:" + f.factureId, genre: .facture, titre: "\(f.numero) · \(f.client)",
                                       detail: "\(FormatSuisse.chf(f.montant)) · \(echeance)",
                                       cible: .document(chemin: f.cheminPDF, nom: "\(f.numero).pdf"), score: s))
            }
            for o in argent.offres.offres {
                guard let s = score([o.numero, o.client, o.titre], requete: requete, titre: o.numero) else { continue }
                resultats.append(.init(id: "O:" + o.offreId, genre: .offre, titre: "\(o.numero) · \(o.client)",
                                       detail: "\(o.titre) · \(FormatSuisse.chf(o.montant))",
                                       cible: .document(chemin: o.cheminPDF, nom: "\(o.numero).pdf"), score: s))
            }
            if fournisseurs {
                for f in argent.payer.factures {
                    guard let s = score([f.numero, f.fournisseur, f.objet], requete: requete, titre: f.fournisseur) else { continue }
                    // Jamais de montant d'achat fournisseur affiché dans la recherche.
                    let detail = ["Facture fournisseur", f.echeance.map { "échéance \($0)" }].compactMap { $0 }.joined(separator: " · ")
                    resultats.append(.init(id: "P:" + f.id, genre: .fournisseur, titre: "\(f.fournisseur) · \(f.numero)",
                                           detail: detail, cible: .aucune, score: s))
                }
            }
        }
        for m in messages where m.role != .note && m.etat == .recu || m.role == .patron {
            guard !m.texte.isEmpty, let s = score([m.texte], requete: requete) else { continue }
            let texte = ResumeOral.lisible(m.texte).replacingOccurrences(of: "\n", with: " ")
            resultats.append(.init(id: "M:" + m.id, genre: .message,
                                   titre: texte.count > 90 ? String(texte.prefix(88)) + "…" : texte,
                                   detail: (m.role == .patron ? "Vous" : (m.agent.map { "Assistant · \($0)" } ?? "Assistant"))
                                       + " · " + DateEndry.heure(m.le),
                                   cible: .conversation, score: s - 1))
        }
        let ordre = Dictionary(uniqueKeysWithValues: ResultatRecherche.Genre.allCases.enumerated().map { ($1, $0) })
        return Array(resultats.sorted {
            $0.score != $1.score ? $0.score > $1.score : (ordre[$0.genre] ?? 0) < (ordre[$1.genre] ?? 0)
        }.prefix(limite))
    }
}
