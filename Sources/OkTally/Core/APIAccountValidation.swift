import Foundation

/// New integrations validate a candidate key before it becomes a saved account.
/// The candidate stays in memory; cancelling a draft cannot leave it in Keychain.
enum APIAccountValidation {
    static func provider(kind: AccountKind, instanceId: String, key: String, session: URLSession = .shared) -> UsageProvider? {
        switch kind {
        case .deepseek: return DeepSeekUsageProvider(instanceId: instanceId, apiKeyProvider: { key }, session: session)
        case .metaAPI: return MetaAPIUsageProvider(instanceId: instanceId, apiKeyProvider: { key }, session: session)
        case .kimiAPI: return MoonshotUsageProvider(instanceId: instanceId, apiKeyProvider: { key }, session: session)
        case .zai: return ZaiUsageProvider(instanceId: instanceId, apiKeyProvider: { key }, session: session)
        case .zaiAPI: return CatalogConnectionProvider(instanceId: instanceId, service: .zai, apiKeyProvider: { key }, session: session)
        case .mistral: return MistralUsageProvider(instanceId: instanceId, apiKeyProvider: { key }, session: session)
        case .mistralAPI: return CatalogConnectionProvider(instanceId: instanceId, service: .mistral, apiKeyProvider: { key }, session: session)
        case .qwen: return QwenUsageProvider(instanceId: instanceId, apiKeyProvider: { key }, session: session)
        default: return nil
        }
    }
}
