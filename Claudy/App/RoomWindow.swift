import AppKit
import SwiftUI

/// The agent room's window: the card's borderless glass, draggable from anywhere like the card,
/// but an ordinary window otherwise: it does not float over the others, and Escape closes it.
final class RoomPanel: FloatingPanel {

    var onCancel: (() -> Void)?

    override init(contentRect: NSRect) {
        super.init(contentRect: contentRect)
        isFloatingPanel = false
        level = .normal
        collectionBehavior = [.fullScreenAuxiliary]
        animationBehavior = .documentWindow
        isReleasedWhenClosed = false
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Opens the agent room in the middle of the screen and takes it down when it closes: a closed
/// room draws nothing and walks nobody.
@MainActor
final class RoomWindowController {

    private let room: RoomViewModel
    private let content: (RoomView) -> AnyView
    private var panel: RoomPanel?

    /// `content` hands the room's view the objects its subviews read from the environment.
    init(room: RoomViewModel, content: @escaping (RoomView) -> AnyView) {
        self.room = room
        self.content = content
    }

    var isOpen: Bool { panel != nil }

    func toggle() {
        if isOpen { close() } else { show() }
    }

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let view = RoomView(room: room, close: { [weak self] in self?.close() })
        let controller = NSHostingController(rootView: content(view))
        let size = controller.view.fittingSize
        let panel = RoomPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.contentViewController = controller
        panel.setContentSize(size)
        panel.onCancel = { [weak self] in self?.close() }
        centre(panel)
        self.panel = panel
        room.isVisible = true
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        room.isVisible = false
        room.isSummaryOpen = false
        guard let closing = panel else { return }
        panel = nil
        closing.orderOut(nil)
        // The close button lives in the view being taken down: let its action return first.
        DispatchQueue.main.async { closing.contentViewController = nil }
    }

    /// The middle of the screen the pointer is on.
    private func centre(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: (visible.midX - panel.frame.width / 2).rounded(),
                                     y: (visible.midY - panel.frame.height / 2).rounded()))
    }
}
