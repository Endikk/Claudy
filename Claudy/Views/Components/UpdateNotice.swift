import SwiftUI

extension ClaudyWave {
    static let loopDuration: TimeInterval = Double(sequence.reduce(0) { $0 + $1.ms }) / 1000

    /// The frame on screen `elapsed` seconds into the loop.
    static func frameIndex(elapsed: TimeInterval) -> Int {
        var remaining = Int((elapsed.truncatingRemainder(dividingBy: loopDuration) * 1000).rounded(.down))
        for step in sequence {
            if remaining < step.ms { return step.frame }
            remaining -= step.ms
        }
        return sequence[0].frame
    }

    /// Arm up and smiling: the still frame when motion is reduced.
    static let stillFrame = 4

    /// Rows any frame draws on. The grid keeps empty rows for the export's margin; cropping
    /// them lets Claudy waving take the typing mascot's place at the same scale.
    static let contentRows: Range<Int> = {
        let used = frames.flatMap { frame in
            frame.indices.filter { frame[$0].contains { $0 != "." } }
        }
        return (used.min() ?? 0)..<((used.max() ?? rows - 1) + 1)
    }()
}

/// Claudy waving in a loop, drawn with the sprite's inks and the gauge tint.
struct ClaudyWaving: View {
    var tint: Color = Theme.Accent.coral.color
    /// Side of one sprite pixel, in points before snapping to device pixels.
    var cell: CGFloat = 1.5

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let tick: TimeInterval = 1.0 / 30

    var body: some View {
        let cell = max(1, (cell * displayScale).rounded()) / displayScale
        Group {
            if reduceMotion {
                canvas(ClaudyWave.frames[ClaudyWave.stillFrame], cell: cell)
            } else {
                TimelineView(.periodic(from: .now, by: Self.tick)) { context in
                    let elapsed = context.date.timeIntervalSinceReferenceDate
                    canvas(ClaudyWave.frames[ClaudyWave.frameIndex(elapsed: elapsed)], cell: cell)
                }
            }
        }
        .frame(width: CGFloat(ClaudyWave.columns) * cell, height: CGFloat(ClaudyWave.contentRows.count) * cell)
        .accessibilityLabel("Claudy waving")
    }

    private func canvas(_ frame: [String], cell: CGFloat) -> some View {
        let tint = tint
        return Canvas { context, _ in
            var paths: [Character: Path] = [:]
            for (row, line) in frame[ClaudyWave.contentRows].enumerated() {
                for (column, ink) in line.enumerated() where ink != "." {
                    paths[ink, default: Path()].addRect(CGRect(
                        x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell
                    ))
                }
            }
            for (ink, path) in paths {
                for color in ClaudyTyping.colors(for: ink, tint: tint) {
                    context.fill(path, with: .color(color))
                }
            }
        }
    }
}

/// The dot that says a new version is out: the error dot's size, in coral.
struct UpdateDot: View {
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(Theme.Accent.coral.color)
            .frame(width: size, height: size)
            .help("A new version of Claudy is available")
    }
}

/// The Update button and its states: upgrading in the background, restarting, or offering
/// Terminal when brew failed. Without Homebrew it downloads from the release page.
struct UpdateButton: View {
    @EnvironmentObject private var updates: UpdateChecker

    var body: some View {
        switch updates.upgradeState {
        case .idle:
            Button(updates.canUpgradeInPlace ? "Update" : "Download", action: updates.update)
                .help(updates.canUpgradeInPlace
                      ? "Update with Homebrew: Claudy restarts in the new version"
                      : "Open the release page to download it")
        case .upgrading:
            progress("Updating…")
        case .restarting:
            progress("Restarting…")
        case .failed:
            Button("Open in Terminal", action: updates.upgradeInTerminal)
                .help("The update did not finish. Run it in Terminal to see why.")
        }
    }

    private func progress(_ label: String) -> some View {
        HStack(spacing: 5) {
            ProgressView().controlSize(.mini)
            Text(label)
        }
        .foregroundStyle(.primary.opacity(0.6))
    }
}

/// One slim line above the footer, only while a newer release exists.
struct UpdateRow: View {
    @EnvironmentObject private var updates: UpdateChecker

    var body: some View {
        if let release = updates.available {
            HStack(spacing: 7) {
                UpdateDot()
                Text(updates.upgradeState == .failed ? "Update failed" : "Claudy \(release.version.description) is available")
                    .font(Theme.Font.label(11, .medium))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(1)
                Spacer(minLength: 0)
                UpdateButton()
                    .buttonStyle(.borderless)
                    .font(Theme.Font.label(11, .semibold))
                    .foregroundStyle(Theme.Accent.coral.color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.Accent.coral.color.opacity(0.12))
            )
        }
    }
}

/// The bubble that drops from the menu bar item when a new version is out, once per version.
struct UpdateBubble: View {
    @EnvironmentObject private var updates: UpdateChecker
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ClaudyWaving()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Claudy \(updates.available?.version.description ?? "") is out")
                        .font(Theme.Font.label(13, .semibold))
                        .foregroundStyle(.primary.opacity(0.92))
                    HStack(spacing: 4) {
                        if let current = updates.current {
                            Text("You have \(current.description) ·")
                                .foregroundStyle(.primary.opacity(0.5))
                        }
                        Button("What's new", action: updates.openReleasePage)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.primary.opacity(0.7))
                            .underline()
                    }
                    .font(Theme.Font.label(10.5, .medium))
                }
            }

            HStack(spacing: 8) {
                Button("Later", action: onClose)
                    .foregroundStyle(.primary.opacity(0.75))
                    .disabled(updates.upgradeState == .upgrading || updates.upgradeState == .restarting)
                Spacer(minLength: 0)
                UpdateButton()
                    .foregroundStyle(Theme.Accent.coral.color)
            }
            .buttonStyle(.borderless)
            .font(Theme.Font.label(11.5, .semibold))
        }
        .padding(14)
        .frame(width: 256)
    }
}
