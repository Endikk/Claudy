import Foundation

/// The area of the agent room a kind of work sits in.
enum WorkFamily: String, CaseIterable, Sendable {
    case writing, commands, research

    /// The name on the area's sign.
    var title: String {
        switch self {
        case .writing: "Writing"
        case .commands: "Commands"
        case .research: "Research"
        }
    }
}

/// What one tool call is for, as the agent room shows it on a desk's screen. Read from what the
/// call says about itself (the tool, the command it ran, the file it touched), never from a list
/// of known skills: a skill nobody has heard of is told apart by the commands it runs.
enum AgentWork: String, CaseIterable, Sendable {
    case code, docs, plan, design
    case search, review, web
    case terminal, tests, build, benchmark, install, git, data, infra, deploy, security
    case delegating, skill, mcp, other

    /// The area this work is done in. A call that says nothing of the work (launching an agent,
    /// loading a skill) has none: the agent stays where it sits.
    var family: WorkFamily? {
        switch self {
        case .code, .docs, .plan, .design: .writing
        case .search, .review, .web: .research
        case .terminal, .tests, .build, .benchmark, .install, .git, .data, .infra, .deploy, .security: .commands
        case .delegating, .skill, .mcp, .other: nil
        }
    }

    /// One word for it, before the file or the command.
    var label: String {
        switch self {
        case .plan: "spec"
        case .mcp: "MCP"
        case .other: "working"
        default: rawValue
        }
    }

    /// The more telling of two kinds of command, when one line chains several.
    private var weight: Int {
        switch self {
        case .security: 12
        case .benchmark: 11
        case .tests: 10
        case .build: 9
        case .deploy: 8
        case .infra: 7
        case .install: 6
        case .data: 5
        case .review: 4
        case .git: 3
        case .web: 2
        case .search: 1
        default: 0
        }
    }

    // MARK: - Reading a call

    /// The work behind one tool call, and the few words that name it: the command's first words,
    /// the skill's name, the MCP server's.
    static func read(tool: String, command: String? = nil, path: String? = nil,
                     skill: String? = nil) -> (work: AgentWork, detail: String?) {
        switch tool {
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            return (written(path), nil)
        case "Read", "Grep", "Glob", "LS", "NotebookRead":
            return (.search, nil)
        case "WebFetch", "WebSearch":
            return (.web, nil)
        case "Agent", "Task":
            return (.delegating, nil)
        case "Skill":
            return (.skill, skill.flatMap { $0.isEmpty ? nil : $0 })
        case "Bash":
            return command.map(ran) ?? (.terminal, nil)
        case "BashOutput", "KillShell", "KillBash":
            return (.terminal, nil)
        default:
            return served(tool)
        }
    }

    /// A tool an MCP server brings, under the name its plugin chose: `mcp__<server>__<tool>`.
    private static func served(_ tool: String) -> (work: AgentWork, detail: String?) {
        guard tool.hasPrefix("mcp__") else { return (.other, nil) }
        let server = tool.dropFirst("mcp__".count).components(separatedBy: "__").first
        let name = tool.lowercased()
        if ["browser", "chrome", "devtools", "playwright"].contains(where: name.contains) { return (.web, server) }
        if name.contains("figma") { return (.design, server) }
        return (.mcp, server)
    }

    /// The work of writing a file, told by where the file is and what it is.
    private static func written(_ path: String?) -> AgentWork {
        guard let path, !path.isEmpty else { return .code }
        let lowered = path.lowercased()
        let name = (lowered as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        if lowered.contains(".github/workflows/") { return .deploy }
        if ["tf", "tfvars", "hcl"].contains(ext) || name == "dockerfile" || name.hasPrefix("docker-compose") {
            return .infra
        }
        if ext == "sql" || lowered.contains("/migrations/") { return .data }
        if ["css", "scss", "sass", "less", "svg"].contains(ext) { return .design }
        if ["md", "mdx", "rst", "txt", "adoc"].contains(ext) {
            let planned = ["plan.md", "tasks.md", "spec.md", "prd.md", "constitution.md"].contains(name)
                || ["/specs/", "/spec/", "/plans/"].contains(where: lowered.contains)
            return planned ? .plan : .docs
        }
        return .code
    }

    // MARK: - Reading a command

    /// Programs that say what they do by their name alone.
    private static let programs: [String: AgentWork] = [
        "trivy": .security, "semgrep": .security, "gitleaks": .security, "snyk": .security, "bandit": .security,
        "pip-audit": .security, "osv-scanner": .security,
        "hyperfine": .benchmark, "k6": .benchmark, "wrk": .benchmark, "lighthouse": .benchmark,
        "pytest": .tests, "jest": .tests, "vitest": .tests, "rspec": .tests, "phpunit": .tests, "playwright": .tests,
        "xcodebuild": .build, "make": .build, "cmake": .build, "tsc": .build, "gradle": .build, "gradlew": .build,
        "mvn": .build, "webpack": .build, "ninja": .build,
        "vercel": .deploy, "netlify": .deploy, "flyctl": .deploy,
        "terraform": .infra, "tofu": .infra, "terragrunt": .infra, "kubectl": .infra, "helm": .infra,
        "docker": .infra, "ansible": .infra, "ansible-playbook": .infra, "pulumi": .infra, "aws": .infra,
        "gcloud": .infra, "az": .infra,
        "brew": .install, "pip": .install, "pip3": .install,
        "git": .git, "gh": .git,
        "psql": .data, "mysql": .data, "sqlite3": .data, "dbt": .data, "mongosh": .data, "redis-cli": .data,
        "alembic": .data,
        "grep": .search, "rg": .search, "find": .search, "ls": .search, "cat": .search, "head": .search,
        "tail": .search, "wc": .search, "fd": .search, "tree": .search,
        "curl": .web, "wget": .web,
    ]

    /// Programs whose first argument decides: `npm test` is not `npm install`.
    private static let subcommands: [String: [String: AgentWork]] = [
        "npm": ["test": .tests, "t": .tests, "install": .install, "i": .install, "ci": .install, "audit": .security],
        "pnpm": ["test": .tests, "install": .install, "add": .install, "audit": .security, "build": .build],
        "yarn": ["test": .tests, "install": .install, "add": .install, "audit": .security, "build": .build],
        "bun": ["test": .tests, "install": .install, "add": .install, "build": .build],
        "swift": ["test": .tests, "build": .build],
        "cargo": ["test": .tests, "build": .build, "bench": .benchmark, "add": .install, "install": .install,
                  "audit": .security],
        "go": ["test": .tests, "build": .build, "get": .install],
        "dotnet": ["test": .tests, "build": .build],
        "mvn": ["test": .tests], "gradle": ["test": .tests], "gradlew": ["test": .tests],
        "xcodebuild": ["test": .tests],
        "uv": ["add": .install, "sync": .install, "pip": .install],
        "bundle": ["install": .install],
        "docker": ["push": .deploy],
        "gh": ["workflow": .deploy, "run": .deploy, "release": .deploy],
        "git": ["diff": .review, "log": .review, "show": .review, "blame": .review],
        "fly": ["deploy": .deploy],
        "prisma": ["migrate": .data],
    ]

    /// Words that run another program and say nothing themselves.
    private static let wrappers: Set<String> = ["sudo", "time", "npx", "bunx", "exec", "command", "env", "nohup"]

    /// The work of one shell line. A line chains commands; the most telling one names it:
    /// `cd app && npm test` is tests.
    static func ran(_ command: String) -> (work: AgentWork, detail: String?) {
        var best: (work: AgentWork, detail: String?) = (.terminal, nil)
        for segment in segments(of: command) {
            guard let found = one(segment) else { continue }
            if best.detail == nil || found.work.weight > best.work.weight { best = found }
        }
        return best
    }

    /// Programs whose action comes after their options: `xcodebuild -scheme App test`.
    private static let actsLate: Set<String> = ["xcodebuild", "gradle", "gradlew", "mvn"]

    /// The line without what its quotes hold: a commit message or a title is not a command, and
    /// must neither split the line nor name it.
    private static func unquoted(_ command: Substring) -> String {
        var result = ""
        var quote: Character?
        for character in command {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
                result.append("_")
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func segments(of command: String) -> [[String]] {
        var separated = unquoted(command.prefix(2_000))
        for separator in ["&&", "||", ";", "|", "\n"] {
            separated = separated.replacingOccurrences(of: separator, with: "\u{1F}")
        }
        return separated.split(separator: "\u{1F}").map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
    }

    /// The work of one command of the line, `nil` for one that only moves around (`cd`, `export`).
    private static func one(_ words: [String]) -> (work: AgentWork, detail: String?)? {
        let meaningful = words.drop { $0.contains("=") || wrappers.contains($0) }
        guard let first = meaningful.first else { return nil }
        let program = (first as NSString).lastPathComponent.lowercased()
        guard !["cd", "export", "source", "echo", "mkdir", "set", "true", "pushd", "popd"].contains(program) else {
            return nil
        }
        let arguments = meaningful.dropFirst().map { $0.lowercased() }
        let named = arguments.first.flatMap { $0.hasPrefix("-") ? nil : $0 }
        let detail = [program, named].compactMap { $0 }.joined(separator: " ")
        // `gh pr view` reads, `gh pr create` writes.
        if program == "gh", named == "pr", ["view", "diff", "checks", "list"].contains(where: arguments.contains) {
            return (.review, detail)
        }
        let isBench = named == "bench" || named == "benchmark"
            || arguments.contains { $0.hasPrefix("-bench") || $0.hasPrefix("--bench") }
        if isBench || program.hasPrefix("bench") {
            return (.benchmark, detail)
        }
        if ["npm", "pnpm", "yarn", "bun"].contains(program), arguments.first == "run", arguments.count > 1 {
            let script = arguments[1]
            let scripted = "\(program) run \(script)"
            if script.contains("bench") { return (.benchmark, scripted) }
            if script.contains("test") { return (.tests, scripted) }
            if script.contains("build") { return (.build, scripted) }
            return (.terminal, scripted)
        }
        if let named, let work = subcommands[program]?[named] { return (work, detail) }
        if actsLate.contains(program), let work = arguments.lazy.compactMap({ subcommands[program]?[$0] }).first {
            return (work, detail)
        }
        return (programs[program] ?? .terminal, detail)
    }
}
