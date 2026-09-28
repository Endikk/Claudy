import Foundation

/// When the island opens and closes as the pointer comes and goes. Opening waits a beat, so a
/// pointer crossing the ears on its way to the menu bar leaves the island shut; closing waits a
/// little longer, so grazing the edge does not snap it closed.
@MainActor
final class NotchHover {

    nonisolated static let openDelay: TimeInterval = 0.15
    nonisolated static let closeDelay: TimeInterval = 0.3

    private(set) var isOpen = false

    private let openDelay: TimeInterval
    private let closeDelay: TimeInterval
    private let open: @MainActor () -> Void
    private let close: @MainActor () -> Void
    /// False while the island must stay open whatever the pointer does: a text field in it is
    /// being edited.
    private let mayClose: @MainActor () -> Bool
    private var pending: Task<Void, Never>?

    init(
        openDelay: TimeInterval = NotchHover.openDelay,
        closeDelay: TimeInterval = NotchHover.closeDelay,
        open: @escaping @MainActor () -> Void,
        close: @escaping @MainActor () -> Void,
        mayClose: @escaping @MainActor () -> Bool = { true }
    ) {
        self.openDelay = openDelay
        self.closeDelay = closeDelay
        self.open = open
        self.close = close
        self.mayClose = mayClose
    }

    /// The pointer entered or left the island. Each call replaces whatever was pending.
    func pointer(inside: Bool) {
        pending?.cancel()
        pending = nil
        if inside {
            guard !isOpen else { return }
            pending = after(openDelay) { [weak self] in
                guard let self else { return }
                self.isOpen = true
                self.open()
            }
        } else {
            guard isOpen else { return }
            pending = after(closeDelay) { [weak self] in
                guard let self, self.mayClose() else { return }
                self.isOpen = false
                self.close()
            }
        }
    }

    /// Closed at once with nothing pending, without calling `close`: the island is being hidden
    /// and its owner resets what it shows.
    func reset() {
        pending?.cancel()
        pending = nil
        isOpen = false
    }

    private func after(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
