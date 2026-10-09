import Foundation

enum ProviderAPIError: Error, LocalizedError {
    case missingCredential(String)
    case rejectedCredential(String)
    case response(String, Int?)
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingCredential(let name): return LF("Configure a credencial de %@ nas Preferências.", name)
        case .rejectedCredential(let name): return LF("%@ recusou a credencial — conecte a conta novamente.", name)
        case .response(let name, let code):
            return LF("%@ respondeu com erro (código %@).", name, code.map(String.init) ?? L("desconhecido"))
        case .malformedResponse(let name): return LF("%@ não retornou dados de uso válidos.", name)
        }
    }
}
