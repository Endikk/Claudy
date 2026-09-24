@testable import Claudy

extension OwnTokenStore {
    /// No token of Claudy's own, and nothing written or erased: a test client built with it
    /// never reaches the real keychain.
    static let empty = OwnTokenStore(load: { nil }, persist: { _ in true }, erase: {})
}
