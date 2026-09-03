import XCTest
@testable import Claudy

private struct StubScanner: PortScanning {
    let result: PortScanState
    func scan() -> PortScanState { result }
}

@MainActor
final class PortsViewModelTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_788_000_000)

    private func port(_ pid: pid_t, _ attribution: PortAttribution) -> ListeningPort {
        ListeningPort(id: "\(pid)-4000", pid: pid, port: 4000, command: "Python",
                      projectName: "Surikat", startedAt: epoch, attribution: attribution, sessionRootPID: nil)
    }

    func testPublishesScannedPorts() async {
        let model = PortsViewModel(scanner: StubScanner(result: .ready([port(500, .orphan)], isDegraded: false)))
        await model.refresh()
        XCTAssertEqual(model.state, .ready([port(500, .orphan)], isDegraded: false))
    }

    func testCountsOnlyOrphans() async {
        let model = PortsViewModel(
            scanner: StubScanner(result: .ready([port(500, .orphan), port(501, .live)], isDegraded: false))
        )
        await model.refresh()
        XCTAssertEqual(model.orphanCount, 1)
    }

    func testUnavailableScanIsPublishedAsIs() async {
        let model = PortsViewModel(scanner: StubScanner(result: .unavailable("lsof did not respond")))
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
}
