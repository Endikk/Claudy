import SwiftUI
import XCTest
@testable import Claudy

final class ClaudyOverloadTests: XCTestCase {

    // MARK: - Frame data

    func testEveryFrameHasTheGridSize() {
        for (index, frame) in ClaudyOverload.frames.enumerated() {
            XCTAssertEqual(frame.count, ClaudyOverload.rows, "frame \(index) row count")
            for line in frame {
                XCTAssertEqual(line.count, ClaudyOverload.columns, "frame \(index) row width")
            }
        }
    }

    func testDurationsMatchFrames() {
        XCTAssertEqual(ClaudyOverload.durations.count, ClaudyOverload.frames.count)
        XCTAssertTrue(ClaudyOverload.durations.allSatisfy { $0 > 0 })
    }

    func testEveryInkHasAColour() {
        let inks = Set(ClaudyOverload.frames.joined().joined()).subtracting([Character(".")])
        for ink in inks {
            XCTAssertFalse(ClaudyTyping.colors(for: ink, tint: .red).isEmpty, "ink \(ink) has no colour")
        }
    }

    func testEverySpriteInkHasAColour() {
        let poses: [ClaudyTyping.Pose] = [.resting, .leftDown, .rightDown]
        let inks = Set(poses.flatMap { ClaudyTyping.frame($0) }.joined()).subtracting([Character(".")])
        for ink in inks {
            XCTAssertFalse(ClaudyTyping.colors(for: ink, tint: .red).isEmpty, "ink \(ink) has no colour")
        }
    }

    /// Switching from typing to the explosion must not move Claude by a single pixel.
    func testTypingSpriteSitsAtSpriteOriginInTheOpeningFrames() {
        let origin = ClaudyOverload.spriteOrigin
        let expected: [(Int, ClaudyTyping.Pose)] = [(0, .leftDown), (1, .rightDown)]
        for (index, pose) in expected {
            let sprite = ClaudyTyping.frame(pose)
            let frame = ClaudyOverload.frames[index]
            for (row, line) in sprite.enumerated() {
                let overloadLine = Array(frame[origin.row + row])
                let slice = String(overloadLine[origin.column..<origin.column + line.count])
                XCTAssertEqual(slice, line, "frame \(index), sprite row \(row)")
            }
        }
    }

    func testDeadFramesShowCrossedEyesAndAsh() {
        for frame in ClaudyOverload.frames.suffix(ClaudyOverload.deadLoopCount) {
            let inks = Set(frame.joined())
            XCTAssertTrue(inks.contains("c"), "dead Claude is ash")
            XCTAssertFalse(inks.contains("C"), "no living body colour left")
            XCTAssertFalse(inks.contains("L"), "the laptop lid is gone")
        }
    }

    // MARK: - Timeline

    private var deadStart: Int { ClaudyOverload.frames.count - ClaudyOverload.deadLoopCount }

    func testUnwitnessedOverloadGoesStraightToTheDeadLoop() {
        XCTAssertEqual(ClaudyOverload.frameIndex(elapsed: nil), deadStart)
    }

    func testIntroStartsAtTheFirstFrame() {
        XCTAssertEqual(ClaudyOverload.frameIndex(elapsed: 0), 0)
        XCTAssertEqual(ClaudyOverload.frameIndex(elapsed: -1), 0)
    }

    func testIntroAdvancesFrameByFrame() {
        var elapsed: TimeInterval = 0
        for index in 0..<deadStart {
            XCTAssertEqual(ClaudyOverload.frameIndex(elapsed: elapsed + 0.001), index)
            elapsed += TimeInterval(ClaudyOverload.durations[index]) / 1000
        }
        XCTAssertEqual(elapsed, ClaudyOverload.introDuration, accuracy: 0.0001)
    }

    func testAfterTheIntroTheDeadLoopRepeats() {
        let intro = ClaudyOverload.introDuration
        XCTAssertEqual(ClaudyOverload.frameIndex(elapsed: intro + 0.001), deadStart)
        let loop = TimeInterval(ClaudyOverload.durations.suffix(ClaudyOverload.deadLoopCount).reduce(0, +)) / 1000
        for cycle in [1.0, 7.0, 1_000.0] {
            let index = ClaudyOverload.frameIndex(elapsed: intro + loop * cycle + 0.001)
            XCTAssertEqual(index, deadStart, "cycle \(cycle)")
        }
        let hours = ClaudyOverload.frameIndex(elapsed: intro + 5 * 3600 + 0.1234)
        XCTAssertTrue((deadStart..<ClaudyOverload.frames.count).contains(hours))
    }

    // MARK: - When it triggers

    private func snapshot(session: Double?, weekly: Double?, sonnet: Double? = nil) -> UsageSnapshot {
        var snapshot = UsageSnapshot.placeholder
        if let session { snapshot.session.percent = session; snapshot.session.isMeasured = true }
        if let weekly { snapshot.weekly.percent = weekly; snapshot.weekly.isMeasured = true }
        if let sonnet { snapshot.sonnet.percent = sonnet; snapshot.sonnet.isMeasured = true }
        return snapshot
    }

    func testFullSessionOverloads() {
        XCTAssertTrue(snapshot(session: 1.0, weekly: 0.4).isOverloaded)
    }

    func testFullWeekOverloads() {
        XCTAssertTrue(snapshot(session: 0.2, weekly: 1.0).isOverloaded)
    }

    func testBelowFullDoesNotOverload() {
        XCTAssertFalse(snapshot(session: 0.99, weekly: 0.99).isOverloaded)
    }

    func testFullPerModelWindowDoesNotOverload() {
        XCTAssertFalse(snapshot(session: 0.3, weekly: 0.3, sonnet: 1.0).isOverloaded)
    }

    func testUnmeasuredWindowsNeverOverload() {
        XCTAssertFalse(UsageSnapshot.placeholder.isOverloaded)
    }
}
