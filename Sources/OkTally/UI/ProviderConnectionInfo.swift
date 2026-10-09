import Foundation

enum ProviderConnectionInfo {
    static func placeholder(for kind: AccountKind) -> String {
        kind == .mistral ? L("Chave administrativa da Mistral") : "API Key"
    }

    static func note(for kind: AccountKind) -> String? {
        switch kind {
        case .deepseek: return L("A chave da DeepSeek API acompanha o saldo da conta. A assinatura do chat não é incluída.")
        case .kimiAPI: return L("Use uma chave de platform.kimi.ai (Global). O saldo da API é separado da assinatura Kimi Code.")
        case .zai: return L("Use a chave do GLM Coding Plan da Z.ai Global para acompanhar as cotas de programação e ferramentas.")
        case .zaiAPI: return L("A conexão valida a chave de API da Z.ai Global. O saldo e os gastos por consumo são consultados no portal.")
        case .mistral: return L("Use uma chave Admin API criada no Backoffice. Ela acompanha gastos e limite mensal da organização; não conecta a assinatura pessoal do chat.")
        case .mistralAPI: return L("Use a chave comum da Mistral API. Para acompanhar gastos da organização, adicione Mistral Organização com a chave Admin API.")
        case .metaAPI: return L("Esta chave conecta a Meta Model API. O saldo e o uso total são consultados no portal. O acompanhamento da assinatura Muse Code ainda não está disponível.")
        case .qwen: return L("Use uma chave Global: sk-sp- para Coding Plan ou sk-/sk-ws- para API por consumo. A conexão valida o acesso; as cotas e os gastos exigem o console da Alibaba Cloud.")
        default: return nil
        }
    }

    static func portal(for kind: AccountKind) -> URL? {
        let url: String
        switch kind {
        case .deepseek: url = "https://platform.deepseek.com/usage"
        case .kimiAPI: url = "https://platform.kimi.ai/console/info"
        case .zai, .zaiAPI: url = "https://z.ai/manage-apikey/apikey-list"
        case .mistral, .mistralAPI: url = "https://console.mistral.ai/"
        case .metaAPI: url = "https://dev.meta.ai/"
        case .qwen: url = "https://bailian.console.alibabacloud.com/"
        default: return nil
        }
        return URL(string: url)
    }
}
