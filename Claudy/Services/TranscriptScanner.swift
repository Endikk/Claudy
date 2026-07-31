import Foundation

/// Une réponse du modèle relevée dans un transcript.
struct TranscriptEntry {
    let date: Date
    let model: String
    let tokens: Int
    let project: String
    let sessionID: String
    /// Réponse d'un sous-agent. Ses tokens comptent, mais ce n'est pas une session utilisateur.
    let isSidechain: Bool
    /// `message.id:requestId` — Claude Code réécrit la même réponse sur plusieurs lignes
    /// (une par bloc de contenu) avec un bloc `usage` identique ; sans cette clé, chaque
    /// réponse serait comptée plusieurs fois. `nil` = pas d'identifiants, toujours comptée.
    let dedupKey: String?
}

/// Résultat d'un passage de scan.
struct ScanResult {
    let entries: [TranscriptEntry]
    /// Lignes qui ressemblaient à une réponse assistant mais n'ont pas pu être lues.
    /// Un compteur qui grimpe signale un changement de format des transcripts.
    let skippedLines: Int
}

/// Lecture des transcripts `<config>/projects/**/*.jsonl`.
///
/// Les transcripts ne font que grossir : le scanner mémorise donc un curseur par fichier et ne
/// relit que la queue ajoutée depuis le passage précédent. Sans ça, un rafraîchissement toutes
/// les 60 s relirait des centaines de mégaoctets à chaque fois.
///
/// Les lectures sont synchrones et bloquent un thread du pool coopératif : ~2 s au premier
/// passage sur un gros historique, quelques millisecondes ensuite. Compromis assumé.
actor TranscriptScanner {

    /// Fenêtre conservée en mémoire. La vue la plus large est « 7 jours » ; la marge absorbe
    /// les décalages de fuseau et les semaines calendaires à cheval.
    private let retention: TimeInterval = 9 * 86_400

    /// État de lecture d'un fichier. Les entrées sont rattachées à leur fichier pour pouvoir
    /// être purgées si celui-ci est tronqué ou remplacé.
    private struct FileState {
        var offset: UInt64
        /// Identifiant du fichier (inode) : détecte un remplacement à taille égale ou supérieure.
        var fileID: NSObject?
        var entries: [TranscriptEntry]
        var lastSeen: Date
    }

    private var files: [URL: FileState] = [:]

    /// Clés déjà comptées, globales à tous les fichiers : une session reprise (`--resume`)
    /// réécrit les mêmes réponses dans un autre transcript.
    private var seenKeys: [String: (url: URL, date: Date)] = [:]

    private var skippedLines = 0
    private var warnedUsageKeys: Set<String> = []

    private let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Toutes les réponses relevées sur la fenêtre de rétention, du plus ancien au plus récent.
    func scan() -> ScanResult {
        let now = Date()
        let cutoff = now.addingTimeInterval(-retention)
        skippedLines = 0

        let discovered = transcriptURLs(modifiedSince: cutoff)
        for url in discovered {
            ingest(url, cutoff: cutoff, now: now)
        }

        // Purges : fichiers disparus depuis la rétention, clés et entrées expirées.
        let discoveredSet = Set(discovered)
        for (url, state) in files where !discoveredSet.contains(url) && state.lastSeen < cutoff {
            files.removeValue(forKey: url)
        }
        seenKeys = seenKeys.filter { $0.value.date >= cutoff }
        for url in files.keys {
            files[url]?.entries.removeAll { $0.date < cutoff }
        }

        var all = files.values.flatMap(\.entries)
        all.sort { $0.date < $1.date }

        if skippedLines > 0 {
            NSLog("[Claudy] %d ligne(s) de transcript illisible(s) ignorée(s).", skippedLines)
        }
        return ScanResult(entries: all, skippedLines: skippedLines)
    }

    // MARK: - Découverte

    private func transcriptURLs(modifiedSince cutoff: Date) -> [URL] {
        let manager = FileManager.default
        let root = ClaudeHome.projectsDirectory
        guard let projects = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [URL] = []
        for project in projects {
            guard let files = try? manager.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                // Un fichier non touché depuis la fenêtre ne peut rien apporter de neuf.
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                if let modified, modified < cutoff { continue }
                found.append(file)
            }
        }
        return found
    }

    // MARK: - Lecture incrémentale

    private func ingest(_ url: URL, cutoff: Date, now: Date) {
        let currentID = (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?
            .fileResourceIdentifier as? NSObject

        var state = files[url] ?? FileState(offset: 0, fileID: currentID, entries: [], lastSeen: now)
        state.lastSeen = now
        defer { files[url] = state }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0

        // Fichier tronqué ou remplacé (inode différent) : on repart de zéro et on oublie tout
        // ce qui en avait été lu — y compris ses clés de dédup, sans quoi la ré-ingestion
        // serait intégralement dédupliquée et les entrées perdues.
        let replaced = state.fileID != nil && currentID != nil && !state.fileID!.isEqual(currentID)
        if replaced || size < state.offset {
            state.offset = 0
            state.entries = []
            state.fileID = currentID
            seenKeys = seenKeys.filter { $0.value.url != url }
        }
        if state.fileID == nil { state.fileID = currentID }

        guard size > state.offset,
              (try? handle.seek(toOffset: state.offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return }

        // La dernière ligne peut être incomplète (Claude Code écrit pendant qu'on lit) :
        // on ne consomme que jusqu'au dernier saut de ligne. Sans aucun saut de ligne, la
        // queue est soit une écriture en cours (retentée au prochain passage), soit une
        // ligne finale sans \n : consommée seulement si son JSON est complet.
        let complete: Data
        if let lastBreak = data.lastIndex(of: 0x0A) {
            complete = Data(data[data.startIndex...lastBreak])
        } else if (try? JSONSerialization.jsonObject(with: data)) != nil {
            complete = data
        } else {
            return
        }
        state.offset += UInt64(complete.count)

        for line in complete.split(separator: 0x0A) where !line.isEmpty {
            // Filtre bon marché avant le coût du parsing JSON : la grande majorité des lignes
            // d'un transcript (attachements, snapshots, prompts) ne portent pas d'usage.
            guard line.range(of: Self.usageMarker) != nil else { continue }

            switch parse(Data(line)) {
            case .entry(let entry):
                guard entry.date >= cutoff else { continue }
                if let key = entry.dedupKey {
                    // Réécriture de la même réponse : la première occurrence fait foi.
                    if seenKeys[key] != nil { continue }
                    seenKeys[key] = (url, entry.date)
                }
                state.entries.append(entry)
            case .malformed:
                skippedLines += 1
            case .irrelevant:
                continue
            }
        }
    }

    private static let usageMarker = Data("\"usage\"".utf8)
    private static let assistantMarker = Data("\"type\":\"assistant\"".utf8)

    // MARK: - Parsing

    private enum ParseOutcome {
        case entry(TranscriptEntry)
        /// Ligne valide mais hors sujet (pas une réponse assistant comptable).
        case irrelevant
        /// Ligne qui devrait être une réponse assistant mais ne se lit pas : canari de format.
        case malformed
    }

    private func parse(_ line: Data) -> ParseOutcome {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return line.range(of: Self.assistantMarker) != nil ? .malformed : .irrelevant
        }
        guard root["type"] as? String == "assistant" else { return .irrelevant }
        guard let message = root["message"] as? [String: Any] else { return .malformed }
        // « usage » du pré-filtre peut venir du contenu du message : absence = ligne hors sujet.
        guard let usage = message["usage"] as? [String: Any] else { return .irrelevant }
        guard let model = message["model"] as? String else { return .malformed }
        guard ModelName.isReal(model) else { return .irrelevant }
        guard let stamp = root["timestamp"] as? String,
              let date = isoWithFraction.date(from: stamp) ?? iso.date(from: stamp)
        else { return .malformed }

        warnAboutUnknownCounters(in: usage)

        func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        let tokens = count("input_tokens")
            + count("output_tokens")
            + count("cache_creation_input_tokens")
            + count("cache_read_input_tokens")
        guard tokens > 0 else { return .irrelevant }

        // Le nom de dossier de projet est une translittération du chemin (accents et séparateurs
        // perdus) : le `cwd` de la ligne est la seule source fidèle.
        let project = (root["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "—"

        let messageID = message["id"] as? String
        let requestID = root["requestId"] as? String
        let dedupKey: String? = if let messageID, let requestID, !messageID.isEmpty, !requestID.isEmpty {
            "\(messageID):\(requestID)"
        } else {
            nil
        }

        return .entry(TranscriptEntry(
            date: date,
            model: model,
            tokens: tokens,
            project: project.isEmpty ? "—" : project,
            sessionID: (root["sessionId"] as? String) ?? "",
            isSidechain: (root["isSidechain"] as? Bool) ?? false,
            dedupKey: dedupKey
        ))
    }

    /// Journalise (une fois par clé) tout nouveau compteur numérique apparu dans `usage`.
    /// `server_tool_use` et consorts sont connus et volontairement ignorés : ce sont des
    /// compteurs de requêtes (recherche web…), pas des tokens.
    private static let knownUsageKeys: Set<String> = [
        "input_tokens", "output_tokens",
        "cache_creation_input_tokens", "cache_read_input_tokens",
        "server_tool_use", "cache_creation", "service_tier",
        "speed", "iterations", "inference_geo",
    ]

    private func warnAboutUnknownCounters(in usage: [String: Any]) {
        for (key, value) in usage where value is NSNumber && !Self.knownUsageKeys.contains(key) {
            guard warnedUsageKeys.insert(key).inserted else { continue }
            NSLog("[Claudy] Clé d'usage inconnue dans les transcripts : %@ (ignorée).", key)
        }
    }
}
