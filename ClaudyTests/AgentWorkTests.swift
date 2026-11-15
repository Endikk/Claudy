import XCTest
@testable import Claudy

/// What a tool call is for, read from the call alone: its tool, its command, its file.
final class AgentWorkTests: XCTestCase {

    private func work(of command: String) -> AgentWork {
        AgentWork.read(tool: "Bash", command: command).work
    }

    func testACommandIsNamedByItsProgram() {
        XCTAssertEqual(work(of: "swift test"), .tests)
        XCTAssertEqual(work(of: "pytest -q tests/"), .tests)
        XCTAssertEqual(work(of: "xcodebuild -project Claudy.xcodeproj -scheme Claudy build"), .build)
        XCTAssertEqual(work(of: "hyperfine './scan'"), .benchmark)
        XCTAssertEqual(work(of: "terraform plan -out tf.plan"), .infra)
        XCTAssertEqual(work(of: "kubectl get pods"), .infra)
        XCTAssertEqual(work(of: "trivy fs ."), .security)
        XCTAssertEqual(work(of: "psql -c 'select 1'"), .data)
        XCTAssertEqual(work(of: "git commit -m wip"), .git)
        XCTAssertEqual(work(of: "rg TODO Claudy"), .search)
        XCTAssertEqual(work(of: "curl -s https://example.com"), .web)
        XCTAssertEqual(work(of: "./Scripts/build-app.sh"), .terminal)
    }

    func testTheFirstArgumentDecidesForProgramsThatDoSeveralThings() {
        XCTAssertEqual(work(of: "npm test"), .tests)
        XCTAssertEqual(work(of: "npm install left-pad"), .install)
        XCTAssertEqual(work(of: "npm audit"), .security)
        XCTAssertEqual(work(of: "npm run build"), .build)
        XCTAssertEqual(work(of: "pnpm run test:unit"), .tests)
        XCTAssertEqual(work(of: "cargo bench"), .benchmark)
        XCTAssertEqual(work(of: "go test -bench=. ./..."), .benchmark)
        XCTAssertEqual(work(of: "docker push registry/app"), .deploy)
        XCTAssertEqual(work(of: "docker compose up"), .infra)
        XCTAssertEqual(work(of: "gh workflow run release.yml"), .deploy)
    }

    func testTheActionOfXcodebuildIsFoundAfterItsOptions() {
        XCTAssertEqual(work(of: "xcodebuild test -project Claudy.xcodeproj -scheme Claudy"), .tests)
        XCTAssertEqual(work(of: "xcodebuild -project Claudy.xcodeproj -scheme Claudy test"), .tests)
    }

    func testReadingGitIsReviewAndWritingItIsGit() {
        XCTAssertEqual(work(of: "git diff main...HEAD"), .review)
        XCTAssertEqual(work(of: "gh pr view 12"), .review)
        XCTAssertEqual(work(of: "gh pr create --fill"), .git)
        XCTAssertEqual(work(of: "git push origin develop"), .git)
    }

    func testAChainedLineIsNamedByItsMostTellingCommand() {
        XCTAssertEqual(work(of: "cd app && npm test"), .tests)
        XCTAssertEqual(work(of: "export CI=1; git status && cargo build | tail -5"), .build)
        XCTAssertEqual(work(of: "FOO=bar sudo npx jest --watch"), .tests)
    }

    func testWhatQuotesHoldNeitherSplitsNorNamesTheLine() {
        XCTAssertEqual(work(of: "gh pr create --title \"run checks\""), .git)
        XCTAssertEqual(work(of: "git commit -m 'fix the log | swift test'"), .git)
        XCTAssertEqual(work(of: "git commit -m wip diff"), .git)
    }

    func testAFileNamedBenchIsNotABenchmark() {
        XCTAssertEqual(work(of: "cat benchmarks.md"), .search)
        XCTAssertEqual(work(of: "grep -r benchmark ."), .search)
        XCTAssertEqual(AgentWork.read(tool: "Bash", command: "npm run test").detail, "npm run test")
    }

    func testTheDetailIsTheCommandsFirstWords() {
        XCTAssertEqual(AgentWork.read(tool: "Bash", command: "cd app && swift test --filter Scan").detail, "swift test")
        XCTAssertEqual(AgentWork.read(tool: "Bash", command: "/usr/bin/make -j8").detail, "make")
        XCTAssertNil(AgentWork.read(tool: "Bash", command: "cd app").detail)
    }

    func testAWrittenFileIsNamedByWhereItIsAndWhatItIs() {
        func written(_ path: String) -> AgentWork { AgentWork.read(tool: "Edit", path: path).work }
        XCTAssertEqual(written("/repo/Claudy/Services/AgentScanner.swift"), .code)
        XCTAssertEqual(written("/repo/README.md"), .docs)
        XCTAssertEqual(written("/repo/specs/001-room/spec.md"), .plan)
        XCTAssertEqual(written("/repo/tasks.md"), .plan)
        XCTAssertEqual(written("/repo/web/styles/card.css"), .design)
        XCTAssertEqual(written("/repo/infra/main.tf"), .infra)
        XCTAssertEqual(written("/repo/.github/workflows/preflight.yml"), .deploy)
        XCTAssertEqual(written("/repo/db/migrations/0004_add.sql"), .data)
    }

    func testOtherToolsAreNamedByWhatTheyAre() {
        XCTAssertEqual(AgentWork.read(tool: "Grep").work, .search)
        XCTAssertEqual(AgentWork.read(tool: "WebSearch").work, .web)
        XCTAssertEqual(AgentWork.read(tool: "Agent").work, .delegating)
        XCTAssertEqual(AgentWork.read(tool: "mcp__plugin_chrome-devtools__click").work, .web)
        XCTAssertEqual(AgentWork.read(tool: "TodoWrite").work, .other)
    }

    func testAnUnknownSkillOrServerShowsUnderItsOwnName() {
        let skill = AgentWork.read(tool: "Skill", skill: "speckit-plan")
        XCTAssertEqual(skill.work, .skill)
        XCTAssertEqual(skill.detail, "speckit-plan")
        let served = AgentWork.read(tool: "mcp__notion__search")
        XCTAssertEqual(served.work, .mcp)
        XCTAssertEqual(served.detail, "notion")
    }

    func testEveryWorkThatSaysWhereItIsDoneHasAFamily() {
        XCTAssertEqual(AgentWork.code.family, .writing)
        XCTAssertEqual(AgentWork.tests.family, .commands)
        XCTAssertEqual(AgentWork.web.family, .research)
        XCTAssertNil(AgentWork.delegating.family)
        XCTAssertNil(AgentWork.skill.family)
    }

    // MARK: - Where an agent sits

    private func agent(_ calls: [(tool: String, command: String?, secondsAgo: TimeInterval)], now: Date) -> RunningAgent {
        let actions = calls.map { call in
            let reading = AgentWork.read(tool: call.tool, command: call.command)
            return AgentAction(date: now.addingTimeInterval(-call.secondsAgo), kind: AgentActionKind(tool: call.tool),
                               tool: call.tool, file: nil, work: reading.work, detail: reading.detail)
        }
        return RunningAgent(id: "a", sessionID: "s", sessionPID: 1, sessionStartedAt: nil, sessionName: "s",
                            title: "t", startedAt: now.addingTimeInterval(-600), lastActivity: now, isFinished: false,
                            actionCount: actions.count, recent: actions, lastAction: actions.last, editedFiles: [])
    }

    func testOneCallDoesNotMoveAnAgentAcrossTheRoom() {
        let now = Date(timeIntervalSince1970: 1_793_468_000)
        let reader = agent([("Read", nil, 50), ("Grep", nil, 40), ("Read", nil, 30), ("Bash", "swift test", 5)], now: now)
        XCTAssertEqual(reader.family(at: now), .research)
        XCTAssertEqual(reader.workLabel, "tests · swift test")
    }

    func testTheLatestFamilyWinsATie() {
        let now = Date(timeIntervalSince1970: 1_793_468_000)
        let turned = agent([("Read", nil, 40), ("Bash", "swift test", 5)], now: now)
        XCTAssertEqual(turned.family(at: now), .commands)
    }

    func testOldCallsNoLongerCount() {
        let now = Date(timeIntervalSince1970: 1_793_468_000)
        let moved = agent([("Read", nil, 300), ("Read", nil, 280), ("Bash", "make", 10)], now: now)
        XCTAssertEqual(moved.family(at: now), .commands)
    }
}
