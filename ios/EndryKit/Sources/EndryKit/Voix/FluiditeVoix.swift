import Foundation

/// Fin de phrase : combien de silence attendre avant de répondre.
///
/// On ne coupe jamais la parole : la dictée d'Apple met un point à chaque pause, donc un point ne suffit pas
/// à dire que la phrase est finie. Une question (« ? ») confirmée : réponse un peu plus tôt. Des mots encore
/// incertains, ou une phrase qui s'arrête sur « euh », « et », « pour » : on attend nettement plus.
/// `patience` multiplie tous les délais (réglage « Temps avant la réponse »).
public enum FinDePhrase {
    /// Mots après lesquels une phrase n'est manifestement pas finie.
    static let motsSuspendus: Set<String> = [
        "euh", "heu", "hum", "et", "mais", "donc", "alors", "ou", "pour", "de", "du", "des", "le", "la", "les",
        "un", "une", "a", "au", "aux", "avec", "chez", "sur", "dans", "que", "qui", "si", "puis", "ensuite",
    ]

    /// Réglages proposés : « Court », « Normal » (par défaut), « Long ».
    public static let patiences: [(libelle: String, valeur: Double)] = [("Court", 0.7), ("Normal", 1.0), ("Long", 1.5)]

    public static func delai(definitif: String, provisoire: String, patience: Double = 1.0) -> Duration {
        .milliseconds(Int((Double(base(definitif: definitif, provisoire: provisoire)) * max(patience, 0.5)).rounded()))
    }

    /// Délai de base, en millisecondes.
    static func base(definitif: String, provisoire: String) -> Int {
        let phrase = [definitif, provisoire].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
        let dernier = RepondeurLocal.normaliser(phrase).split(separator: " ").last.map(String.init) ?? ""
        if motsSuspendus.contains(dernier) { return 2_400 }
        guard provisoire.trimmingCharacters(in: .whitespaces).isEmpty else { return 1_800 }
        if definitif.trimmingCharacters(in: .whitespaces).last == "?" { return 1_200 }
        return 1_500
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

/// Conversation continue : le patron coupe Endry en parlant, comme avec un interlocuteur.
///
/// Le micro reste ouvert pendant qu'Endry parle (annulation d'écho du système). Ce qui reste d'écho de sa propre
/// voix est écarté : seuls comptent les mots qu'Endry n'est pas en train de dire.
public enum Interruption {
    /// Un seul mot suffit pour ceux-là.
    static let motsDArret: Set<String> = ["stop", "attends", "attend", "arrete", "non", "pardon", "tais toi", "chut", "merci"]
    /// Hésitations : ne coupent pas.
    static let hesitations: Set<String> = ["euh", "heu", "hum", "hm", "ah", "oh", "bon"]

    private static func mots(_ texte: String) -> [String] {
        RepondeurLocal.normaliser(texte).split(separator: " ").map(String.init)
    }

    /// Mots entendus qui ne viennent pas de la voix d'Endry (ni hésitations).
    public static func motsDuPatron(_ entendu: String, pendant dit: String) -> [String] {
        let echo = Set(mots(dit))
        return mots(entendu).filter { !echo.contains($0) && !hesitations.contains($0) }
    }

    /// Couper Endry : deux vrais mots du patron, ou un mot d'arrêt (« stop », « attends », « non »…).
    public static func couper(_ entendu: String, pendant dit: String) -> Bool {
        let patron = motsDuPatron(entendu, pendant: dit)
        if patron.count >= 2 { return true }
        let tout = RepondeurLocal.normaliser(entendu)
        return patron.count == 1 && (motsDArret.contains(patron[0]) || motsDArret.contains(tout))
    }

    /// Ce que le patron a dit, sans les premiers mots d'écho.
    public static func sansEcho(_ entendu: String, pendant dit: String) -> String {
        let echo = Set(mots(dit))
        var morceaux = entendu.split(separator: " ").map(String.init)
        while let premier = morceaux.first, let n = mots(premier).first, echo.contains(n) || hesitations.contains(n) {
            morceaux.removeFirst()
        }
        return morceaux.joined(separator: " ")
    }

    /// Le patron reprend la parole juste après qu'Endry a commencé (moins de 4 s) : c'est la suite de sa phrase,
    /// pas une nouvelle question. Une commande (« stop », « répète ») reste une commande.
    public static func suite(de precedente: String, nouvelle: String, apres secondes: TimeInterval) -> String {
        let n = nouvelle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard secondes < 4, !precedente.isEmpty, CommandeVocale.detecter(n) == nil,
              !motsDArret.contains(RepondeurLocal.normaliser(n)) else { return n }
        var p = precedente.trimmingCharacters(in: .whitespacesAndNewlines)
        while let d = p.last, ".?!".contains(d) { p.removeLast() }
        let debut = n.first.map { String($0).lowercased() + n.dropFirst() } ?? n
        return p + " " + debut
    }
}
