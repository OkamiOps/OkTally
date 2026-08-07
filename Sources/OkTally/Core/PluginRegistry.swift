// Sources/OkTally/Core/PluginRegistry.swift
final class PluginRegistry {
    private(set) var providers: [UsageProvider] = []

    func register(_ provider: UsageProvider) {
        providers.append(provider)
    }
}
