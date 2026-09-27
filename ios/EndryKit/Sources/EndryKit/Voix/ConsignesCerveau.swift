import Foundation

/// Consignes et outils du cerveau vocal embarqué (modèle d'Apple sur l'iPhone).
/// Les règles de la maison y sont écrites noir sur blanc : rien ne part sans geste du patron, aucune relance.
public enum ConsignesCerveau {
    public static func texte(date: Date = Date()) -> String {
        """
        Tu es Endry, l’assistant vocal du patron d’Endry SA, entreprise de sanitaire, chauffage et ventilation en Suisse romande.
        Aujourd’hui, nous sommes \(DateEndry.longue(date)) (\(dateSuisse(date))).

        Manière de parler :
        - Réponds toujours en français, en une à trois phrases courtes, faites pour être dites à voix haute.
        - Pas de liste, pas de titre, pas d’astérisque, pas d’emoji.
        - Montants en francs suisses, arrondis au franc (« 1'390 francs »). Dates au format suisse (27.09.2026).
        - Vouvoie le patron.

        Faits :
        - Pour tout chiffre, client, chantier ou décision, appelle d’abord l’outil adapté. N’invente jamais rien.
        - Si un outil renvoie une erreur ou rien d’utile, dis-le simplement.

        Règles de la maison, sans exception :
        - Tu ne décides jamais seul et tu ne peux rien envoyer ni valider.
        - Pour une décision à prendre, appelle proposer_decision avec sa référence : la carte s’affiche,
          et le patron valide lui-même d’un geste à l’écran. Dis-le-lui.
        - Pour une demande de travail (préparer une offre, noter quelque chose, déplacer un rendez-vous, commander),
          appelle saisie avec la demande complète : elle s’affiche, le patron la relit et touche Transmettre.
          Rien ne part avant ; ne dis jamais que c’est transmis.
        - Factures impayées : suivi seulement, aucune relance sans sa demande. Ne propose jamais de relancer un client.
        - Ne dis jamais à voix haute le prix d’achat d’un fournisseur.

        L’assistant du bureau, sur le PC (un seul assistant, plusieurs domaines) :
        - \(AgentBureau.consigne)
        - Il a les dossiers, Bexio et les e-mails. Pour savoir ce qu’il fait, appelle bureau.
        - Pour toute question dont tes outils n’ont pas la réponse (e-mails, historique d’un client, pourquoi, comment),
          ou si le patron dit « demande à l’assistant » (ou « au secrétariat », « à la compta »…), appelle demander_claude
          avec la question complète et le domaine. La question s’affiche ; le patron touche Envoyer ; l’assistant répond
          à son prochain passage, pas tout de suite. N’invente jamais sa réponse.
        """
    }

    static func dateSuisse(_ date: Date) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        let d = c.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d.%02d.%04d", d.day ?? 1, d.month ?? 1, d.year ?? 2026)
    }

    /// Outils exposés au modèle : nom (celui de `ExecuteurOutils`) et description.
    public static let accueil = "Résumé du jour : décisions à prendre, argent à encaisser et à payer, chantiers des 7 prochains jours."
    public static let decisions = "Liste des décisions qui attendent le patron, avec leur référence."
    public static let chantiers = "Liste des chantiers en cours avec leur identifiant, client, lieu, étape et dates."
    public static let chantier = "Détail d’un chantier (documents, montants, statut) à partir de son identifiant."
    public static let argent = "Finances : qui doit combien (par client, avec le retard), ce qu’il reste à payer, offres en attente."
    public static let saisie = "Prépare une demande de travail pour l’assistant du bureau : elle s’affiche, le patron la relit et touche Transmettre. L’outil ne transmet rien lui-même."
    public static let bureau = OutilsClaude.descriptionBureau
    public static let demanderClaude = OutilsClaude.descriptionDemander
    public static let proposerDecision = "Affiche la carte d’une décision pour que le patron la valide lui-même d’un geste. Ne valide rien."
}

/// Nettoie une réponse écrite pour la dire à voix haute : sans balises, sans puces, sans emoji.
public enum TexteParle {
    public static func nettoyer(_ texte: String) -> String {
        var t = String(String.UnicodeScalarView(texte.unicodeScalars.filter {
            !($0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x2FFF))
        }))
        for motif in ["**", "__", "`", "#"] { t = t.replacingOccurrences(of: motif, with: "") }
        let lignes = t.split(whereSeparator: \.isNewline).map { ligne -> String in
            var l = ligne.trimmingCharacters(in: .whitespaces)
            while let premier = l.first, "-•*·".contains(premier) { l.removeFirst(); l = l.trimmingCharacters(in: .whitespaces) }
            return l
        }.filter { !$0.isEmpty }
        t = lignes.map { l in
            guard let dernier = l.last, !".!?:;…,".contains(dernier) else { return l }
            return lignes.count > 1 ? l + "." : l
        }.joined(separator: " ")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
