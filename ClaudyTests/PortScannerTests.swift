import XCTest
@testable import Claudy

final class PortScannerTests: XCTestCase {

    /// Real `lsof -nP -iTCP -sTCP:LISTEN -a -u <uid> -F pcn` output. lsof emits fields that
    /// were never asked for — `f` here — and the parser must ignore them.
    private let output = """
    p46694
    cPython
    f3
    n127.0.0.1:4000
    p95778
    cbun
    f22
    n127.0.0.1:37701
    p40964
    cOrbStack
    f11
    n*:3001
    p5771
    cnode
    f18
    n[::1]:3000
    """

    func testParsesPidCommandAndPort() {
        let listeners = PortScanner.parseListeners(output)
        XCTAssertEqual(listeners.count, 4)
        XCTAssertEqual(listeners[0], Listener(pid: 46694, command: "Python", port: 4000, address: "127.0.0.1"))
    }

    func testParsesWildcardAndIPv6Addresses() {
        let listeners = PortScanner.parseListeners(output)
        XCTAssertEqual(listeners[2].port, 3001)
        XCTAssertEqual(listeners[2].address, "*")
        XCTAssertEqual(listeners[3].port, 3000)
        XCTAssertEqual(listeners[3].address, "[::1]")
    }

    /// One server holds several descriptors on the same port — one per address family, one per
    /// accepting socket — and lsof reports each of them. Observed on this machine: every single
    /// listener came out twice. Left as is, two rows would share one `id`.
    func testCollapsesDescriptorsOnTheSamePort() {
        let listeners = PortScanner.parseListeners("""
        p1271
        cControlCenter
        f10
        n*:7000
        f11
        n*:7000
        f12
        n127.0.0.1:5000
        f13
        n[::1]:5000
        """)
        XCTAssertEqual(listeners.count, 2)
        XCTAssertEqual(listeners.map(\.port), [7000, 5000])
    }

    func testDeniesContainerRuntimes() {
        XCTAssertTrue(PortScanner.isDenied(command: "OrbStack"))
        XCTAssertTrue(PortScanner.isDenied(command: "com.docker.backend"))
        XCTAssertTrue(PortScanner.isDenied(command: "Docker"))
        XCTAssertFalse(PortScanner.isDenied(command: "node"))
    }

    private func table(_ processes: [RunningProcess]) -> ProcessTable {
        ProcessTable(processes: Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) }))
    }

    private let epoch = Date(timeIntervalSince1970: 1_788_000_000)

    func testAttributesLivePortWhenClaudeAncestorIsAlive() {
        let result = PortScanner.attribute(
            listeners: [Listener(pid: 46694, command: "Python", port: 4000, address: "127.0.0.1")],
            table: table([
                RunningProcess(pid: 46694, parent: 8859, startedAt: epoch, arguments: "python3 -m http.server"),
                RunningProcess(pid: 8859, parent: 1, startedAt: epoch, arguments: "/Users/x/.claude/local/claude"),
            ]),
            markers: { _ in ProcessEnvironment.Markers(isClaude: true, projectDirectory: "/Users/x/Dev/Surikat") }
        )
        XCTAssertEqual(result.ports.count, 1)
        XCTAssertEqual(result.ports[0].attribution, .live)
        XCTAssertEqual(result.ports[0].sessionRootPID, 8859)
        XCTAssertEqual(result.ports[0].projectName, "Surikat")
    }

    func testAttributesOrphanWhenClaudeAncestorIsGone() {
        let result = PortScanner.attribute(
            listeners: [Listener(pid: 95778, command: "bun", port: 37701, address: "127.0.0.1")],
            table: table([RunningProcess(pid: 95778, parent: 1, startedAt: epoch, arguments: "bun worker")]),
            markers: { _ in ProcessEnvironment.Markers(isClaude: true, projectDirectory: nil) }
        )
        XCTAssertEqual(result.ports[0].attribution, .orphan)
        XCTAssertNil(result.ports[0].sessionRootPID)
    }

    func testDropsPortsWithoutMarkers() {
        let result = PortScanner.attribute(
            listeners: [Listener(pid: 5771, command: "node", port: 3000, address: "*")],
            table: table([RunningProcess(pid: 5771, parent: 1, startedAt: epoch, arguments: "next-server")]),
            markers: { _ in ProcessEnvironment.Markers(isClaude: false, projectDirectory: nil) }
        )
        XCTAssertTrue(result.ports.isEmpty)
    }

    /// A container runtime publishes ports on behalf of everything it hosts: killing it would
    /// take the whole runtime down, so it is never attributed whatever its environment says.
    func testDropsDeniedCommandsEvenWithMarkers() {
        let result = PortScanner.attribute(
            listeners: [Listener(pid: 40964, command: "OrbStack", port: 3001, address: "*")],
            table: table([RunningProcess(pid: 40964, parent: 1, startedAt: epoch, arguments: "OrbStack")]),
            markers: { _ in ProcessEnvironment.Markers(isClaude: true, projectDirectory: nil) }
        )
        XCTAssertTrue(result.ports.isEmpty)
    }

    func testIdentityCombinesPidAndPort() {
        let result = PortScanner.attribute(
            listeners: [Listener(pid: 46694, command: "Python", port: 4000, address: "127.0.0.1")],
            table: table([RunningProcess(pid: 46694, parent: 1, startedAt: epoch, arguments: "python3")]),
            markers: { _ in ProcessEnvironment.Markers(isClaude: true, projectDirectory: nil) }
        )
        XCTAssertEqual(result.ports[0].id, "46694-4000")
    }

    /// When the kernel refuses to hand over an environment, attribution falls back to the
    /// process tree: a live session is still recognisable, so the tab keeps working for the
    /// common case instead of showing an empty list.
    func testFallsBackToAncestryWhenEnvironmentIsUnreadable() {
        let result = PortScanner.attribute(
            listeners: [Listener(pid: 46694, command: "Python", port: 4000, address: "127.0.0.1")],
            table: table([
                RunningProcess(pid: 46694, parent: 8859, startedAt: epoch, arguments: "python3 -m http.server"),
                RunningProcess(pid: 8859, parent: 1, startedAt: epoch, arguments: "/Users/x/.claude/local/claude"),
            ]),
            markers: { _ in nil }
        )
        XCTAssertEqual(result.ports.count, 1)
        XCTAssertEqual(result.ports[0].attribution, .live)
        XCTAssertTrue(result.isDegraded)
    }

    /// The fallback cannot see orphans — that is exactly what the degraded flag warns about.
    func testFallbackDropsOrphans() {
        let result = PortScanner.attribute(
            listeners: [Listener(pid: 95778, command: "bun", port: 37701, address: "127.0.0.1")],
            table: table([RunningProcess(pid: 95778, parent: 1, startedAt: epoch, arguments: "bun worker")]),
            markers: { _ in nil }
        )
        XCTAssertTrue(result.ports.isEmpty)
        XCTAssertTrue(result.isDegraded)
    }
}
