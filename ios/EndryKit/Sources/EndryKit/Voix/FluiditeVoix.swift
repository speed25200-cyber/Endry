import Foundation

/// Fin de phrase : combien de silence attendre avant de répondre.
///
/// La reconnaissance a confirmé la phrase et elle se termine par un point ou un point d'interrogation :
/// on répond vite. Des mots encore incertains, ou une phrase qui s'arrête sur « euh », « et », « pour » :
/// on laisse le temps de finir.
public enum FinDePhrase {
    /// Mots après lesquels une phrase n'est manifestement pas finie.
    static let motsSuspendus: Set<String> = [
        "euh", "heu", "hum", "et", "mais", "donc", "alors", "ou", "pour", "de", "du", "des", "le", "la", "les",
        "un", "une", "a", "au", "aux", "avec", "chez", "sur", "dans", "que", "qui", "si", "puis", "ensuite",
    ]

    public static func delai(definitif: String, provisoire: String) -> Duration {
        let phrase = [definitif, provisoire].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
        let dernier = RepondeurLocal.normaliser(phrase).split(separator: " ").last.map(String.init) ?? ""
        if motsSuspendus.contains(dernier) { return .milliseconds(1_300) }
        guard provisoire.trimmingCharacters(in: .whitespaces).isEmpty else { return .milliseconds(1_000) }
        if let fin = definitif.trimmingCharacters(in: .whitespaces).last, "?.!".contains(fin) { return .milliseconds(550) }
        return .milliseconds(750)
    }
}

/// Réponse dite à voix haute : les premières phrases seulement quand elle est longue ; le reste est à l'écran.
public enum ResumeOral {
    public static let renvoi = " La suite est à l’écran."

    /// Texte lisible (sans Markdown ni puces), une idée par ligne.
    public static func lisible(_ texte: String) -> String {
        BlocTexte.sansBalises(texte)
            .components(separatedBy: "\n")
            .map { ligne -> String in
                var l = ligne.trimmingCharacters(in: .whitespaces)
                for puce in ["- ", "* ", "• ", "– "] where l.hasPrefix(puce) { l = String(l.dropFirst(puce.count)) }
                return l
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// `dit` : début de `lisible(texte)` (mêmes caractères, pour allumer les mots au rythme de la voix) ;
    /// `complet` : tout est dit.
    public static func pourLaVoix(_ texte: String, limite: Int = 320) -> (dit: String, complet: Bool) {
        let t = lisible(texte)
        guard t.count > limite else { return (t, true) }
        // Coupe après la dernière fin de phrase (ou de ligne) avant la limite.
        let debut = t.prefix(limite)
        var coupe: String.Index?
        var i = debut.startIndex
        while i < debut.endIndex {
            let c = debut[i]
            let suivant = debut.index(after: i)
            if c == "\n" || ("?.!".contains(c) && (suivant == debut.endIndex || debut[suivant] == " " || debut[suivant] == "\n")) {
                coupe = suivant
            }
            i = suivant
        }
        if let coupe, debut.distance(from: debut.startIndex, to: coupe) >= 40 {
            return (String(debut[..<coupe]).trimmingCharacters(in: .whitespacesAndNewlines), false)
        }
        // Une seule longue phrase : jusqu'au dernier mot entier.
        if let espace = debut.lastIndex(of: " ") { return (String(debut[..<espace]), false) }
        return (String(debut), false)
    }
}

/// Commandes dites à l'assistant, traitées tout de suite sur l'iPhone (sans modèle, sans le bureau).
public enum CommandeVocale: Equatable, Sendable {
    case repeter
    case terminer
    case ouvrirConversation
    case nouvelleConversation
    case plusLentement
    case plusVite

    private static let formules: [(CommandeVocale, [String])] = [
        (.repeter, ["repete", "repete s il te plait", "repete stp", "tu peux repeter", "peux tu repeter", "redis", "redis le",
                    "redis moi", "pardon", "j ai pas compris", "je n ai pas compris", "tu peux redire"]),
        (.terminer, ["merci", "merci endry", "merci beaucoup", "c est tout", "c est tout merci", "merci c est tout", "ca ira",
                     "ca ira merci", "au revoir", "ferme", "ferme l assistant", "fermer", "stop", "arrete", "c est bon",
                     "c est bon merci", "a plus", "bonne journee", "salut"]),
        (.ouvrirConversation, ["ouvre la conversation", "montre la conversation", "affiche la conversation", "passe a l ecrit",
                               "montre moi la reponse", "montre la reponse"]),
        (.nouvelleConversation, ["nouvelle conversation", "on change de sujet", "change de sujet", "autre sujet", "on recommence"]),
        (.plusLentement, ["plus lentement", "parle plus lentement", "moins vite", "parle moins vite", "doucement"]),
        (.plusVite, ["plus vite", "parle plus vite", "accelere", "plus rapidement", "parle plus rapidement"]),
    ]

    /// Seulement une phrase courte qui est exactement une commande : « merci pour la facture » reste une question.
    public static func detecter(_ phrase: String) -> CommandeVocale? {
        let n = RepondeurLocal.normaliser(phrase)
        guard !n.isEmpty, n.split(separator: " ").count <= 6 else { return nil }
        for (commande, liste) in formules where liste.contains(n) { return commande }
        return nil
    }
}
