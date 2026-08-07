import Foundation

/// Thread-safe guard ensuring an action (typically resuming a `CheckedContinuation`)
/// executes at most once, even when invoked concurrently from multiple threads —
/// e.g. a Network framework callback racing with a timeout `Task`.
///
/// Resuming a `CheckedContinuation` more than once is a runtime `fatalError`, so
/// every path that can call `continuation.resume(...)` must go through the same
/// `SingleResume` instance.
final class SingleResume {
    private let lock = NSLock()
    private var hasFired = false

    /// Executes `body` only on the first call; subsequent calls are no-ops.
    /// Returns `true` if this call was the one that executed `body`.
    @discardableResult
    func fire(_ body: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasFired else { return false }
        hasFired = true
        body()
        return true
    }
}
