import AppKit
import SwiftUI

extension View {
    /// Tells whether the window this view is in can be seen: on screen and not wholly covered.
    /// What only moves for the eye (a mascot typing, the agent room) stops while it cannot: a
    /// timeline in a hidden window is laid out and drawn all the same.
    func onWindowVisibility(_ report: @escaping (Bool) -> Void) -> some View {
        background(WindowVisibilityProbe(report: report))
    }
}

private struct WindowVisibilityProbe: NSViewRepresentable {
    let report: (Bool) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.report = report
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.report = report
    }

    final class ProbeView: NSView {
        var report: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?
        private var told: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.tell() }
            }
            tell()
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        private func stopObserving() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }

        /// After the pass that is laying the view out: its state is not to be set during it.
        private func tell() {
            guard let window else { return }
            let isVisible = window.occlusionState.contains(.visible)
            guard isVisible != told else { return }
            told = isVisible
            DispatchQueue.main.async { [weak self] in self?.report?(isVisible) }
        }
    }
}
