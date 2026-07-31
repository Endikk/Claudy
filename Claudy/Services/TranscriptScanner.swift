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
}

/// Lecture des transcripts `<config>/projects/**/*.jsonl`.
///
/// Les transcripts ne font que grossir : le scanner mémorise donc un curseur par fichier et ne
/// relit que la queue ajoutée depuis le passage précédent. Sans ça, un rafraîchissement toutes
/// les 60 s relirait des centaines de mégaoctets à chaque fois.
actor TranscriptScanner {

    /// Fenêtre conservée en mémoire. La vue la plus large est « 7 jours » ; la marge absorbe
    /// les décalages de fuseau et les semaines calendaires à cheval.
    private let retention: TimeInterval = 9 * 86_400

    private var cursors: [URL: UInt64] = [:]
    private var entries: [TranscriptEntry] = []

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
    func scan() -> [TranscriptEntry] {
        let cutoff = Date().addingTimeInterval(-retention)

        for url in transcriptURLs(modifiedSince: cutoff) {
            ingest(url, cutoff: cutoff)
        }

        entries.removeAll { $0.date < cutoff }
        entries.sort { $0.date < $1.date }
        return entries
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

    private func ingest(_ url: URL, cutoff: Date) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        var offset = cursors[url] ?? 0

        // Fichier tronqué ou remplacé : on repart de zéro.
        if size < offset { offset = 0 }
        guard size > offset else { return }

        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return }

        // La dernière ligne peut être incomplète (Claude Code écrit pendant qu'on lit) :
        // on ne consomme que jusqu'au dernier saut de ligne.
        guard let lastBreak = data.lastIndex(of: 0x0A) else { return }
        let complete = data[data.startIndex...lastBreak]
        cursors[url] = offset + UInt64(complete.count)

        for line in complete.split(separator: 0x0A) where !line.isEmpty {
            // Filtre bon marché avant le coût du parsing JSON : la grande majorité des lignes
            // d'un transcript (attachements, snapshots, prompts) ne portent pas d'usage.
            guard line.range(of: Self.usageMarker) != nil else { continue }
            if let entry = parse(Data(line)), entry.date >= cutoff {
                entries.append(entry)
            }
        }
    }

    private static let usageMarker = Data("\"usage\"".utf8)

    private func parse(_ line: Data) -> TranscriptEntry? {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              root["type"] as? String == "assistant",
              let message = root["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String, ModelName.isReal(model),
              let stamp = root["timestamp"] as? String,
              let date = isoWithFraction.date(from: stamp) ?? iso.date(from: stamp)
        else { return nil }

        func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        let tokens = count("input_tokens")
            + count("output_tokens")
            + count("cache_creation_input_tokens")
            + count("cache_read_input_tokens")
        guard tokens > 0 else { return nil }

        // Le nom de dossier de projet est une translittération du chemin (accents et séparateurs
        // perdus) : le `cwd` de la ligne est la seule source fidèle.
        let project = (root["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "—"

        return TranscriptEntry(
            date: date,
            model: model,
            tokens: tokens,
            project: project.isEmpty ? "—" : project,
            sessionID: (root["sessionId"] as? String) ?? "",
            isSidechain: (root["isSidechain"] as? Bool) ?? false
        )
    }
}
