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
        // sujets, auxiliaires et petits mots qui appellent une suite (« tu dois… », « il faut… », « pour les… »)
        "je", "tu", "il", "elle", "on", "ils", "elles", "ce", "cette", "ces", "mon", "ma", "mes", "ton", "ta", "tes",
        "son", "sa", "ses", "notre", "votre", "leur", "leurs", "dois", "doit", "devez", "faut", "peux", "peut",
        "veux", "veut", "est", "sont", "ai", "as", "avons", "avez", "ont", "vais", "va", "par", "sans", "comme",
        "quand", "car", "parce", "ne", "y", "en", "tout", "tous", "toutes", "aussi", "surtout", "utile",
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
        // Réglé le 06.10.2026 : le patron réfléchit en parlant, et une seconde de silence coupait ses phrases
        // (« Pour les offres de BTK tu dois… » partait tel quel au bureau). On laisse le temps de respirer ;
        // pour répondre plus tôt, il reste le toucher de la sphère et le réglage « Court ».
        if motsSuspendus.contains(dernier) { return 4_500 }
        guard provisoire.trimmingCharacters(in: .whitespaces).isEmpty else { return 2_800 }
        if definitif.trimmingCharacters(in: .whitespaces).last == "?" { return 1_600 }
        return 2_200
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

/// Réponse qui s'écrit (modèle d'Apple en flux) : la phrase suivante, dès qu'elle est complète, pour la dire
/// pendant que le reste s'écrit encore. Décalages en UTF-16 (ceux de l'allumage des mots).
public enum DecoupeurPhrases {
    /// Plus courte, une phrase attend la suivante (« Oui. » seul sonnerait haché), sauf à la fin.
    static let longueurMin = 18

    /// `(phrase, fin)` : la phrase qui commence à `depuis` et se termine avant `fin` ; `nil` si rien n'est prêt.
    public static func prochaine(_ texte: String, depuis: Int, fini: Bool) -> (phrase: String, fin: Int)? {
        let utf = Array(texte.utf16)
        guard depuis < utf.count else { return nil }
        var i = depuis
        while i < utf.count {
            let c = utf[i]
            // . ? ! … suivis d'une espace ou d'un retour à la ligne ; un retour à la ligne seul termine aussi.
            let finDePhrase = c == 0x0A || ((c == 0x2E || c == 0x3F || c == 0x21 || c == 0x2026)
                && i + 1 < utf.count && (utf[i + 1] == 0x20 || utf[i + 1] == 0x0A))
            if finDePhrase {
                let fin = i + 1
                let morceau = String(decoding: utf[depuis..<fin], as: UTF16.self)
                if morceau.trimmingCharacters(in: .whitespacesAndNewlines).count >= longueurMin {
                    return (morceau.trimmingCharacters(in: .whitespacesAndNewlines), fin)
                }
            }
            i += 1
        }
        guard fini else { return nil }
        let reste = String(decoding: utf[depuis...], as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return reste.isEmpty ? nil : (reste, utf.count)
    }
}


/// Relais au bureau : ce que le patron dit part **mot pour mot** au bureau (Claude sur le PC), sans que le modèle
/// de l'iPhone l'interprète, cherche ou réponde à sa place. L'iPhone dit seulement qu'il transmet, puis lit la
/// réponse du bureau quand elle arrive.
public enum RelaisBureau {
    /// Phrase dite pendant l'envoi.
    public static let annonceEnvoi = "Je transmets au bureau."
    /// Préfixe de la réponse lue.
    public static func annonceReponse(agent: String?) -> String {
        agent.map { "Le bureau, côté \($0), répond : " } ?? "Le bureau répond : "
    }
    /// Une phrase coupée partirait telle quelle au bureau : un peu plus de patience qu'en conversation locale,
    /// sans faire attendre (le réglage « Long » reste disponible).
    public static func patience(_ reglage: Double) -> Double { max(reglage, 1.2) }
    /// Texte envoyé : exactement ce qui a été dit (espaces nettoyés), rien d'ajouté ni de reformulé.
    public static func texte(_ dit: String) -> String {
        dit.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
