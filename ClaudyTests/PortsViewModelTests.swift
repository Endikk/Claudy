import XCTest
@testable import Claudy

private struct StubScanner: PortScanning {
    let result: PortScanState
    func scan() -> PortScanState { result }
}

/// Returns fixed servers and remembers which pids the ports scan handed over.
private final class StubMcpScanner: McpScanning {
    let servers: [McpOrphan]
    private(set) var excluded: Set<pid_t>?

    init(_ servers: [McpOrphan] = []) {
        self.servers = servers
    }

    func scan(excluding portPIDs: Set<pid_t>) -> [McpOrphan] {
        excluded = portPIDs
        return servers
    }
}

@MainActor
final class PortsViewModelTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_788_000_000)

    private func port(_ pid: pid_t, _ attribution: PortAttribution, number: Int = 4000) -> ListeningPort {
        ListeningPort(id: "\(pid)-\(number)", pid: pid, port: number, command: "Python",
                      projectName: "Surikat", startedAt: epoch, attribution: attribution, sessionRootPID: nil)
    }

    private func server(_ pid: pid_t, _ name: String, megabytes: UInt64 = 100) -> McpOrphan {
        McpOrphan(id: "mcp-\(pid)", pid: pid, startedAt: epoch, name: name,
                  projectName: "GoodFood", residentBytes: megabytes << 20)
    }

    /// Every model gets a stub for both scans: the real MCP scan would read this machine.
    private func model(_ ports: PortScanState, servers: [McpOrphan] = []) -> PortsViewModel {
        PortsViewModel(scanner: StubScanner(result: ports), mcpScanner: StubMcpScanner(servers))
    }

    func testPublishesScannedPorts() async {
        let model = model(.ready([port(500, .orphan)], isDegraded: false))
        await model.refresh()
        XCTAssertEqual(model.state, .ready([port(500, .orphan)], isDegraded: false))
    }

    func testCountsOnlyOrphans() async {
        let model = model(.ready([port(500, .orphan), port(501, .live)], isDegraded: false))
        await model.refresh()
        XCTAssertEqual(model.orphanCount, 1)
    }

    func testUnavailableScanIsPublishedAsIs() async {
        let model = model(.unavailable("lsof did not respond"))
        await model.refresh()
        XCTAssertEqual(model.state, .unavailable("lsof did not respond"))
    }

    func testAgeReadsInTheLargestUsefulUnit() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        XCTAssertEqual(PortsViewModel.age(since: now.addingTimeInterval(-45), now: now), "45 s")
        XCTAssertEqual(PortsViewModel.age(since: now.addingTimeInterval(-3 * 60), now: now), "3 min")
        XCTAssertEqual(PortsViewModel.age(since: now.addingTimeInterval(-5 * 3600), now: now), "5 h")
        XCTAssertEqual(PortsViewModel.age(since: now.addingTimeInterval(-2 * 86400), now: now), "2 d")
    }

    /// The bulk action never touches a live session's ports — only what Claude left behind.
    func testBulkTargetsOrphansOnly() async {
        let model = model(.ready([port(500, .orphan), port(501, .live), port(502, .orphan)], isDegraded: false))
        await model.refresh()
        XCTAssertEqual(model.orphans.map(\.pid), [500, 502])
    }

    func testBulkConfirmationIsRequiredBeforeAnyKill() async {
        let model = model(.ready([port(500, .orphan)], isDegraded: false))
        await model.refresh()
        XCTAssertFalse(model.isConfirmingBulkKill)
        model.requestBulkKill()
        XCTAssertTrue(model.isConfirmingBulkKill)
    }

    // MARK: - MCP servers left behind

    /// The tab's badge counts everything Claude left behind, ports and servers alike.
    func testOrphanCountIncludesMcpServers() async {
        let model = model(.ready([port(500, .orphan), port(501, .live)], isDegraded: false),
                          servers: [server(600, "chrome-devtools-mcp"), server(700, "figma-mcp")])
        await model.refresh()
        XCTAssertEqual(model.mcpOrphans.map(\.pid), [600, 700])
        XCTAssertEqual(model.orphanCount, 3)
    }

    func testMcpOrphansAloneStillCount() async {
        let model = model(.ready([], isDegraded: false), servers: [server(600, "chrome-devtools-mcp")])
        await model.refresh()
        XCTAssertEqual(model.orphanCount, 1)
        model.requestBulkKill()
        XCTAssertTrue(model.isConfirmingBulkKill)
    }

    /// A process already listed by port must not come back as a server.
    func testMcpScanSkipsThePidsListedAsPorts() async {
        let mcp = StubMcpScanner()
        let model = PortsViewModel(
            scanner: StubScanner(result: .ready([port(500, .orphan), port(501, .live)], isDegraded: false)),
            mcpScanner: mcp
        )
        await model.refresh()
        XCTAssertEqual(mcp.excluded, [500, 501])
    }

    func testMcpScanRunsEvenWhenThePortScanCannot() async {
        let model = model(.unavailable("lsof did not respond"), servers: [server(600, "chrome-devtools-mcp")])
        await model.refresh()
        XCTAssertEqual(model.mcpOrphans.count, 1)
    }

    /// The confirmation names what it is about to kill: ports by number, servers by name.
    func testBulkTargetsNamePortsThenServers() async {
        let model = model(
            .ready([port(500, .orphan, number: 3000), port(501, .live, number: 5173)], isDegraded: false),
            servers: [server(600, "chrome-devtools-mcp"), server(700, "figma-mcp")]
        )
        await model.refresh()
        XCTAssertEqual(model.bulkKillTargets, "3000, chrome-devtools-mcp, figma-mcp")
    }

    func testMcpMemoryAddsUpEveryServer() async {
        let model = model(.ready([], isDegraded: false),
                          servers: [server(600, "chrome-devtools-mcp", megabytes: 412),
                                    server(700, "figma-mcp", megabytes: 301)])
        await model.refresh()
        XCTAssertEqual(model.mcpMemory, 713 << 20)
    }

    func testMemoryReadsInMegabytesThenGigabytes() {
        XCTAssertEqual(PortsViewModel.memory(412 << 20), "412 MB")
        XCTAssertEqual(PortsViewModel.memory(0), "0 MB")
        XCTAssertEqual(PortsViewModel.memory(1_101 << 20), "1.1 GB")
        XCTAssertEqual(PortsViewModel.memory(1_023 << 20 + 900 << 10), "1.0 GB")
    }
}
