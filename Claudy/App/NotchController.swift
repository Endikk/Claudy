import AppKit
import SwiftUI
import Combine

/// Claudy around the notch: the ears at rest, the menu bar popover underneath on hover. The app
/// delegate shows it instead of the card and the menu bar item when the user picks it and a
/// screen has a notch.
@MainActor
final class NotchController {

    private let viewModel: UsageViewModel
    private let updates: UpdateChecker
    private let model = NotchModel()
    /// The island's right-click menu. Its items target it, so it lives as long as the island.
    private lazy var menu = ClaudyMenu(viewModel: viewModel)
    private lazy var hover = NotchHover(
        open: { [weak self] in self?.open() },
        close: { [weak self] in self?.close() },
        mayClose: { [weak self] in !(self?.isEditingText ?? false) }
    )
    private var panel: NotchPanel?
    private var layout: NotchLayout?
    /// Shrinks the window once the shape has finished closing.
    private var settle: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var resignObserver: NSObjectProtocol?

    /// Opening drops from the notch with a slight bounce, as the Dynamic Island does; closing
    /// goes back quicker and without one.
    private static let opening = Animation.spring(response: 0.42, dampingFraction: 0.74)
    private static let closing = Animation.spring(response: 0.3, dampingFraction: 0.92)
    /// Long enough for `closing` to come to rest.
    private static let settleDelay: TimeInterval = 0.5

    init(viewModel: UsageViewModel, updates: UpdateChecker) {
        self.viewModel = viewModel
        self.updates = updates
    }

    deinit {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
    }

    /// Puts the island on the notch. A new notch rectangle (another resolution, another screen)
    /// closes it first, so the window never spans the old place and the new one.
    func show(on geometry: NotchGeometry) {
        let panel = panel ?? makePanel()
        if layout?.geometry != geometry {
            let layout = NotchLayout(geometry: geometry)
            self.layout = layout
            collapse()
            model.notchSize = geometry.notch.size
            panel.setFrame(layout.restingFrame, display: true)
        }
        panel.orderFrontRegardless()
        resyncPointer()
    }

    /// Takes the island away, closed, with nothing left pending.
    func hide() {
        collapse()
        if let layout { panel?.setFrame(layout.restingFrame, display: false) }
        panel?.orderOut(nil)
    }

    /// The screens just changed: the notch may have moved, or gone with the lid. Hidden at once
    /// rather than left where its old frame now falls, possibly on another screen, until the
    /// delayed pass shows it again where it belongs.
    func hideIfMoved() {
        guard panel?.isVisible == true, NotchGeometry.current() != layout?.geometry else { return }
        hide()
    }

    /// A click elsewhere ended the edit that held the island open: close it if the pointer left.
    func panelResignedKey() {
        guard let panel else { return }
        panel.makeFirstResponder(nil)
        if !panel.frame.contains(NSEvent.mouseLocation) {
            hover.pointer(inside: false)
        }
    }

    private func makePanel() -> NotchPanel {
        let host = NotchHostingView(rootView: NotchView(model: model)
            .environmentObject(viewModel)
            .environmentObject(updates))
        // The window follows the shape through `fit`, not through SwiftUI's own sizing.
        host.sizingOptions = []
        host.onHover = { [weak self] inside in self?.hover.pointer(inside: inside) }
        host.contextMenu = { [weak self] in self?.menu.make() }

        let panel = NotchPanel()
        panel.contentView = host
        self.panel = panel

        model.$shapeSize
            .removeDuplicates()
            .sink { [weak self] size in self?.fit(size) }
            .store(in: &cancellables)

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                (NSApp.delegate as? AppDelegate)?.notch.panelResignedKey()
            }
        }
        return panel
    }

    private func collapse() {
        hover.reset()
        settle?.cancel()
        model.isOpen = false
    }

    private func open() {
        // Opening the island counts as opening Claudy: the wave has been seen.
        updates.acknowledgeGreeting()
        widenForOpening()
        withAnimation(reduceMotion ? nil : Self.opening) { model.isOpen = true }
    }

    /// The island grows sideways as well as down. Widening the window first, while the island is
    /// still at rest and laid out at once, keeps that out of the animation: widened mid-flight,
    /// the window slid the whole island from left to right as it dropped.
    private func widenForOpening() {
        settle?.cancel()
        guard let panel, let layout else { return }
        let width = layout.openWidth(content: Theme.Metric.islandWidth, margin: Theme.Metric.shadowInset)
        let wide = layout.frame(for: CGSize(width: width, height: panel.frame.height))
        let step = NotchLayout.step(from: panel.frame, to: wide)
        guard step.now != panel.frame else { return }
        panel.setFrame(step.now, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func close() {
        withAnimation(reduceMotion ? nil : Self.closing) { model.isOpen = false }
    }

    /// No spring with Reduce Motion on: the island is simply open or closed.
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// The manual sign-in code is being typed in the open island.
    private var isEditingText: Bool {
        (panel?.firstResponder as? NSTextView)?.isFieldEditor == true
    }

    /// Fits the window to the shape: at once when it grows, after the animation when it shrinks.
    private func fit(_ shape: CGSize) {
        guard let panel, let layout, shape.width > 0, shape.height > 0 else { return }
        let step = NotchLayout.step(from: panel.frame, to: layout.frame(for: shape))
        if step.now != panel.frame { panel.setFrame(step.now, display: true) }
        settle?.cancel()
        guard step.settle != step.now else { return }
        // Without the spring there is no closing to wait for.
        let delay = reduceMotion ? 0 : Self.settleDelay
        settle = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.panel?.setFrame(step.settle, display: true)
            self.resyncPointer()
        }
    }

    /// A window that shrinks away from a still pointer, or appears under one, hears no crossing
    /// from its tracking area: the pointer's real place decides. Without it, a sign-out from the
    /// open island left the black panel down over the front app.
    private func resyncPointer() {
        guard let panel, panel.isVisible else { return }
        hover.resync(pointerInside: panel.frame.contains(NSEvent.mouseLocation))
    }
}
