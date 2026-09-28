// Sources/OkTally/Core/PluginRegistry.swift
import Foundation

/// Os provedores ativos. Muda em tempo de execução (adicionar/remover conta) e é lido de
/// dentro das tasks do scheduler, fora do main actor — por isso a trava.
final class PluginRegistry {
    private let lock = NSLock()
    private var _providers: [UsageProvider] = []

    var providers: [UsageProvider] {
        lock.lock()
        defer { lock.unlock() }
        return _providers
    }

    func register(_ provider: UsageProvider) {
        add([provider])
    }

    func add(_ providers: [UsageProvider]) {
        lock.lock()
        defer { lock.unlock() }
        _providers.append(contentsOf: providers)
    }

    func remove(ids: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        _providers.removeAll { ids.contains($0.id) }
    }
}
