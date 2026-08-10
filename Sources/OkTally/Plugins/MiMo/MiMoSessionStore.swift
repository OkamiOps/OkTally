// Sources/OkTally/Plugins/MiMo/MiMoSessionStore.swift
import Foundation

/// Remembers whether the user has completed the in-app MiMo web login. The actual session
/// lives in the shared web view's persistent cookie store; this is just the "should we try
/// the automatic path" flag, cleared when the session turns out to be expired.
protocol MiMoSessionStoring: AnyObject {
    var isLoggedIn: Bool { get set }
}

final class MiMoSessionStore: MiMoSessionStoring {
    private let defaults: UserDefaults
    private let key = "mimo.loggedIn"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isLoggedIn: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
