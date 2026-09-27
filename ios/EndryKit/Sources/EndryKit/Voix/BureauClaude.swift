import Foundation

/// Ce que fait Claude, l'assistant du bureau sur le PC : pause, file d'attente, travaux en cours et derniers résultats.
public struct EtatBureau: Sendable, Equatable {
    public var etat: EtatAssistant?
    /// Saisies les plus récentes (la plus récente d'abord).
    public var saisies: [SaisieHistorique]

    public init(etat: EtatAssistant?, saisies: [SaisieHistorique]) {
        self.etat = etat
        self.saisies = saisies
    }

    public var enPause: Bool { etat?.pause ?? false }
    public var enCours: [SaisieHistorique] { saisies.filter { $0.statut == .enCours || $0.statut == .transmis } }
    public var traitees: [SaisieHistorique] { saisies.filter { $0.statut == .traite } }

    /// Libellé court pour la pastille de l'assistant vocal.
    public var libelleCourt: String {
        if enPause { return "Claude en pause" }
        let n = max(etat?.file ?? 0, enCours.count)
        if n > 0 { return "Claude travaille · \(n) en cours" }
        return "Claude disponible"
    }

    /// Phrase à dire : tout ce qui se passe sur le PC, en trois temps.
    public var phrase: String {
        var morceaux: [String] = []
        if enPause {
            morceaux.append("Claude est en pause sur le PC : rien ne part tant que vous ne le relancez pas")
        } else {
            let n = max(etat?.file ?? 0, enCours.count)
            morceaux.append(n == 0 ? "Claude est disponible, rien en attente"
                                   : "Claude travaille sur le PC, \(n) demande\(n > 1 ? "s" : "") en cours")
        }
        if let courante = enCours.first {
            morceaux.append("En ce moment : « \(Self.abreger(courante.texte)) »")
        }
        let faits = traitees.prefix(3).compactMap { s -> String? in
            guard let resume = s.resume, !resume.isEmpty else { return nil }
            return s.decisionReference == nil ? resume : "\(Self.sansPoint(resume)), à valider"
        }
        if !faits.isEmpty {
            morceaux.append("Derniers travaux : " + faits.map(Self.sansPoint).joined(separator: " ; "))
        }
        if let date = etat?.derniereActivite.flatMap(DateEndry.lire) {
            morceaux.append("Dernière activité \(DateEndry.ilYa(date))")
        }
        return morceaux.joined(separator: ". ") + "."
    }

    static func abreger(_ texte: String, max: Int = 90) -> String {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > max else { return t }
        return String(t.prefix(max)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func sansPoint(_ texte: String) -> String {
        var t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        while let d = t.last, ".;".contains(d) { t.removeLast() }
        return t
    }
}

/// Question posée à Claude sur le PC.
public enum QuestionPosee: Sendable, Equatable {
    /// Le PC a répondu tout de suite (`POST /assistant/question`, facultatif).
    case reponse(String)
    /// Question déposée comme saisie : la réponse arrivera dans son résumé.
    case enAttente(saisieId: String?, texte: String)
}

/// Dialogue avec Claude, l'assistant du bureau, par le contrat existant :
/// la question part comme une saisie (`POST /saisie`), la réponse revient dans son résumé (`GET /saisies`).
/// Si le PC expose `POST /assistant/question` (facultatif), la réponse est immédiate.
public struct BureauClaude: Sendable {
    public let api: any EndryAPI

    public init(api: any EndryAPI) {
        self.api = api
    }

    /// Préfixe qui dit à Claude ce qu'on attend : une réponse, pas une action.
    public static let prefixeQuestion = "Question du patron (depuis l’assistant vocal de l’iPhone). Réponds-lui dans le résumé, en deux ou trois phrases à dire à voix haute ; ne prépare et n’envoie rien : "

    public static func texteQuestion(_ question: String) -> String {
        prefixeQuestion + "« \(question.trimmingCharacters(in: .whitespacesAndNewlines)) »"
    }

    public static func estQuestion(_ texte: String) -> Bool { texte.hasPrefix(prefixeQuestion) }

    /// La question telle que le patron l'a posée (sans le préfixe), pour l'historique.
    public static func questionSeule(_ texte: String) -> String {
        guard estQuestion(texte) else { return texte }
        var q = String(texte.dropFirst(prefixeQuestion.count))
        if q.hasPrefix("« ") { q.removeFirst(2) }
        if q.hasSuffix(" »") { q.removeLast(2) }
        return q
    }

    /// Libellé d'historique : « Question à Claude : … » plutôt que le texte technique envoyé au PC.
    public static func libelle(_ texte: String) -> String {
        estQuestion(texte) ? "Question à Claude : " + questionSeule(texte) : texte
    }

    /// Pause, file, travaux en cours et derniers résultats. `nil` si le PC ne connaît pas ces routes (v1.0).
    public func etat() async -> EtatBureau? {
        async let etat = try? api.etatAssistant()
        async let saisies = try? api.saisies()
        let (e, s) = await (etat, saisies)
        guard e != nil || s != nil else { return nil }
        return EtatBureau(etat: e, saisies: s ?? [])
    }

    public func poser(_ question: String) async throws(ErreurAPI) -> QuestionPosee {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw .refus("La question est vide.") }
        // Route directe, si le PC la propose ; sinon on passe par la saisie.
        if let data = try? await api.envoyer(.questionClaude(q)),
           let reponse = try? JSONDecoder().decode(ReponseQuestion.self, from: data), let texte = reponse.texte, !texte.isEmpty {
            return .reponse(texte)
        }
        let texte = Self.texteQuestion(q)
        let formulaire = FormulaireMultipart(champs: [Parametre("texte", texte)])
        let reponse = try await api.charger(ReponseSimple.self, .saisie(formulaire))
        guard reponse.ok else { throw .refus(reponse.message ?? "Le PC n’a pas accepté la question.") }
        return .enAttente(saisieId: reponse.saisieId, texte: texte)
    }

    /// Attend que Claude ait traité la question (résumé disponible), en interrogeant `GET /saisies`.
    public func attendre(saisieId: String?, texte: String,
                         delai: Duration = .seconds(300), intervalle: Duration = .seconds(3)) async -> SaisieHistorique? {
        let limite = ContinuousClock.now + delai
        while ContinuousClock.now < limite, !Task.isCancelled {
            if let saisies = try? await api.saisies(),
               let s = saisies.first(where: { saisie in saisieId.map { $0 == saisie.id } ?? (saisie.texte == texte) }),
               s.statut == .traite || s.statut == .erreur {
                return s
            }
            try? await Task.sleep(for: intervalle)
        }
        return nil
    }
}

/// Réponse de `POST /assistant/question` : `{reponse}` ou `{message}`.
struct ReponseQuestion: Decodable {
    var texte: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.champs()
        texte = c.texte("reponse") ?? c.texte("message")
    }
}

extension Requete {
    /// Facultatif (proposé au PC) : question directe à Claude, réponse synchrone.
    public static func questionClaude(_ question: String) -> Requete {
        .init(.post, "\(prefixe)/assistant/question", corps: .json(json(["question": question])), delai: 90)
    }
}
