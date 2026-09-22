import AppKit
import SwiftUI
import Combine

/// The menu bar face of Claudy: the pixel mascot and the 5h percentage next to the clock and
/// the battery. Left click opens a short card in a popover, right click a small menu.
@MainActor
final class MenuBarController: NSObject {

    private let viewModel: UsageViewModel
    private let updates: UpdateChecker
    private var item: NSStatusItem?
    private let popover = NSPopover()
    /// Drops from the item once per new version, and stays until the user answers it.
    private lazy var bubble = UpdateBubblePanel(content: UpdateBubble { [weak self] in self?.closeBubble() }
        .environmentObject(updates))
    private var cancellables = Set<AnyCancellable>()

    private var timer: Timer?
    private var tick = 0
    /// Frames rendered for the current tint; rebuilt only when the tint changes band.
    private var frames: [ClaudyTyping.Pose: NSImage] = [:]
    private var overloadFrames: [NSImage] = []
    private var waveFrames: [NSImage] = []
    private var framesTint: Color?
    private var framesBadged: Bool?

    /// What the icon is doing. The explosion plays only when the quota fills while the item is
    /// up; opening Claudy on a full quota shows the dead state directly, as the widget does.
    private enum Animation: Equatable {
        case still, typing
        case exploding(since: Date)
        case dead
        /// A new version is out and its bubble has not been answered yet.
        case waving
    }
    private var animation: Animation = .still
    private var wasOverloaded: Bool?

    /// Half a point per sprite pixel: 27 pixels tall fits the menu bar, and lands on whole
    /// device pixels on Retina screens.
    private static let cell: CGFloat = 0.5

    init(viewModel: UsageViewModel, updates: UpdateChecker) {
        self.viewModel = viewModel
        self.updates = updates
        super.init()

        let controller = NSHostingController(rootView: MenuBarView()
            .environmentObject(viewModel)
            .environmentObject(updates))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true

    }

    func show() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Claudy")
        }
        self.item = item

        viewModel.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in self?.update(with: snapshot) }
            .store(in: &cancellables)

        updates.$available
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.update(with: self.viewModel.snapshot)
            }
            .store(in: &cancellables)

        updates.$shouldAnnounce
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] announce in
                if announce { self?.scheduleBubble(attempt: 0) }
            }
            .store(in: &cancellables)

        // `update` reads the published value, which is only set once the sink returns: wait a turn.
        updates.$isGreeting
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.update(with: self.viewModel.snapshot)
                }
            }
            .store(in: &cancellables)
    }

    func hide() {
        popover.performClose(nil)
        bubble.dismiss()
        stopAnimating()
        animation = .still
        wasOverloaded = nil
        cancellables.removeAll()
        if let item {
            NSStatusBar.system.removeStatusItem(item)
        }
        item = nil
    }

    // MARK: - Content

    private func update(with snapshot: UsageSnapshot) {
        guard let button = item?.button else { return }
        let session = snapshot.session
        let tint = Theme.tint(session.accent, at: session.percent)

        let badged = updates.available != nil
        if framesTint != tint || framesBadged != badged {
            let finish = { (image: NSImage) in badged ? Self.withUpdateDot(image) : image }
            frames = Dictionary(uniqueKeysWithValues: [ClaudyTyping.Pose.resting, .leftDown, .rightDown].map {
                ($0, finish(ClaudyTyping.image($0, tint: tint, cell: Self.cell)))
            })
            overloadFrames = ClaudyOverload.frames.indices.map {
                finish(ClaudyTyping.overloadImage($0, tint: tint, cell: Self.cell))
            }
            waveFrames = ClaudyWave.frames.indices.map {
                finish(ClaudyTyping.waveImage($0, tint: tint, cell: Self.cell))
            }
            framesTint = tint
            framesBadged = badged
        }

        let percent = session.isMeasured ? "\(Int(session.percent * 100))%" : "—"
        button.attributedTitle = NSAttributedString(
            string: " \(percent)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)]
        )
        // The title just changed width and the bar moved the icon: keep the bubble's arrow on it.
        if bubble.isVisible {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.bubble.isVisible, let button = self.item?.button else { return }
                self.bubble.show(below: button)
            }
        }
                button.toolTip = session.isActive
            ? "Session \(percent) · reset \(UsageViewModel.clock(session.resetDate))"
            : "Claudy"

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let overloaded = snapshot.isOverloaded
        // The pre-launch placeholder is not a reading: remembering it would turn the first real
        // reading of a full quota into an explosion at launch instead of the dead state.
        let isReading = snapshot.isDemo || [session, snapshot.weekly, snapshot.sonnet].contains(where: \.isMeasured)
        defer { if isReading { wasOverloaded = overloaded } }

        if overloaded {
            if wasOverloaded == false && !reduceMotion {
                animation = .exploding(since: Date())
            } else if case .exploding = animation {
                // Keep playing: a refresh mid-explosion must not cut it short.
            } else {
                animation = .dead
            }
        } else if updates.isGreeting && !reduceMotion {
            // A full quota matters more than a new version: the dead state wins over the wave.
            animation = .waving
        } else {
            animation = session.isActive && !reduceMotion ? .typing : .still
        }
        applyAnimation(reduceMotion: reduceMotion)
    }

    private func applyAnimation(reduceMotion: Bool) {
        stopAnimating()
        switch animation {
        case .still:
            item?.button?.image = frames[.resting]
        case .typing:
            startTimer(every: ClaudyTyping.frameDuration)
        case .exploding:
            startTimer(every: 0.035)
        case .waving:
            startTimer(every: 0.03)
        case .dead:
            if reduceMotion {
                item?.button?.image = overloadFrame(elapsed: nil)
            } else {
                startTimer(every: 0.13)
            }
        }
        advanceFrame()
    }

    private func startTimer(every interval: TimeInterval) {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                (NSApp.delegate as? AppDelegate)?.menuBar.advanceFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func advanceFrame() {
        switch animation {
        case .still:
            break
        case .typing:
            tick += 1
            item?.button?.image = frames[ClaudyTyping.sequence[tick % ClaudyTyping.sequence.count]]
        case .exploding(let since):
            let elapsed = Date().timeIntervalSince(since)
            item?.button?.image = overloadFrame(elapsed: elapsed)
            if elapsed >= ClaudyOverload.introDuration {
                animation = .dead
                applyAnimation(reduceMotion: false)
            }
        case .waving:
            let index = ClaudyWave.frameIndex(elapsed: Date().timeIntervalSinceReferenceDate)
            if waveFrames.indices.contains(index) { item?.button?.image = waveFrames[index] }
        case .dead:
            item?.button?.image = overloadFrame(
                elapsed: ClaudyOverload.introDuration + Date().timeIntervalSinceReferenceDate
            )
        }
    }

    private func overloadFrame(elapsed: TimeInterval?) -> NSImage? {
        let index = ClaudyOverload.frameIndex(elapsed: elapsed)
        return overloadFrames.indices.contains(index) ? overloadFrames[index] : nil
    }

    /// The icon with the coral update dot in its top-right corner, where the sprite is empty.
    private static func withUpdateDot(_ image: NSImage) -> NSImage {
        let diameter: CGFloat = 4
        return NSImage(size: image.size, flipped: true) { rect in
            image.draw(in: rect)
            NSColor(Theme.Accent.coral.color).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - diameter, y: 0, width: diameter, height: diameter)).fill()
            return true
        }
    }

    private func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if bubble.isVisible { closeBubble() }
        updates.acknowledgeGreeting()
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// Attaching the menu for one click is how AppKit places it under the item like the
    /// system's own; the item goes back to sending actions right after.
    private func showMenu(from button: NSStatusBarButton) {
        popover.performClose(nil)
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show floating widget", action: #selector(leaveMenuBar), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Claudy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item?.menu = menu
        button.performClick(nil)
        item?.menu = nil
    }

    // MARK: - Update bubble

    /// A status item just created is not placed in the menu bar yet, and a popover shown from
    /// it opens nowhere. Wait for the bar to lay it out, then retry a few times if it still did
    /// not open (menu bar hidden by a full-screen app, for instance).
    private func scheduleBubble(attempt: Int) {
        guard attempt < Self.bubbleAttempts else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.8 : 2)) { [weak self] in
            guard let self, self.updates.shouldAnnounce, !self.bubble.isVisible else { return }
            self.showBubble()
            if !self.bubble.isVisible { self.scheduleBubble(attempt: attempt + 1) }
        }
    }

    private static let bubbleAttempts = 5

    private func showBubble() {
        guard let button = item?.button, let window = button.window, window.frame.width > 0,
              !bubble.isVisible, !popover.isShown else { return }
        bubble.show(below: button)
        update(with: viewModel.snapshot)
    }

    private func closeBubble() {
        bubble.dismiss()
        updates.markAnnounced()
        update(with: viewModel.snapshot)
    }

    @objc private func refresh() {
        Task { await viewModel.refresh(userInitiated: true) }
    }

    @objc private func leaveMenuBar() {
        viewModel.toggleMenuBar()
    }
}
