import Foundation

/// Monitoramento de assinatura do Muse Code via MSP (`muse serve`). Não usa a
/// Meta Model API e nunca envia um prompt: `usage/read` devolve apenas o último
/// uso observado pelo host. O contrato é experimental no Muse 1.4.4.
///
/// Referências do contrato validado em 2026-10-09:
/// - https://dev.meta.ai/docs/muse-code/changelog
/// - https://meta-models.github.io/muse-code-sdk/next/generated/msp/methods/usage-read/
/// - https://meta-models.github.io/muse-code-sdk/next/generated/msp/types/subscriptionusage/
final class MuseUsageProvider: UsageProvider {
    let id: String
    let displayName = "Meta Muse Code"
    let authMethod: AuthMethod
    /// Polls do último estado observado não gastam prompts, mas tampouco tornam a
    /// observação atual. Cinco minutos evita iniciar `muse serve` em excesso.
    let refreshInterval: TimeInterval = 300

    private let reader: MuseUsageReading
    private let now: () -> Date

    init(
        instanceId: String,
        authFilePath: String,
        reader: MuseUsageReading,
        now: @escaping () -> Date = Date.init
    ) {
        self.id = instanceId
        self.authMethod = .localFile(path: authFilePath)
        self.reader = reader
        self.now = now
    }

    func isAuthenticated() async -> Bool {
        guard let state = try? await reader.readUsage() else { return false }
        return state.account.isSubscriptionLogin
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let state = try await reader.readUsage()
        guard state.account.isSubscriptionLogin else {
            throw MuseUsageError.subscriptionLoginRequired
        }

        // Absence is an explicit, successful `usage/read` state: forcing a model
        // request just to populate a dashboard would spend the user's allowance.
        guard let usage = state.usage else {
            return ProviderSnapshot(
                providerId: id,
                fetchedAt: now(),
                quotas: [],
                usageDetail: nil,
                connectionNote: L("A assinatura Muse está conectada, mas este host ainda não observou uso. Nenhuma chamada de modelo foi feita para preencher as cotas.")
            )
        }

        try usage.validate()
        let observedAt = usage.observedAt
        let currentReset = usage.window.resetAt
        let currentDuration = TimeInterval(usage.window.windowDurationMins * 60)
        let current = QuotaWindow(
            label: Self.windowLabel(minutes: usage.window.windowDurationMins),
            shape: .rollingWindow(
                used: Double(usage.window.usedPercent),
                limit: 100,
                windowStart: currentReset.addingTimeInterval(-currentDuration),
                resetAt: currentReset
            )
        )
        let weeklyReset = usage.weekly.resetAt
        let weekly = QuotaWindow(
            label: "semanal",
            shape: .rollingWindow(
                used: Double(usage.weekly.usedPercent),
                limit: 100,
                windowStart: weeklyReset.addingTimeInterval(-7 * 24 * 60 * 60),
                resetAt: weeklyReset
            ),
            renewalCadence: .weekly
        )

        return ProviderSnapshot(
            providerId: id,
            // `observedAtMs` is the host-arrival time, not this app's refresh time.
            fetchedAt: observedAt,
            quotas: [current, weekly],
            usageDetail: nil,
            planLabel: usage.tier,
            connectionNote: L("Último uso de assinatura observado pelo Muse; não é uma consulta de cota ao vivo.")
        )
    }

    private static func windowLabel(minutes: Int) -> String {
        if minutes == 300 { return "5h" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)min"
    }
}

enum MuseUsageError: LocalizedError, Equatable {
    case subscriptionLoginRequired
    case malformedUsage
    case hostUnavailable
    case hostRejected
    case credentialImportInvalid

    var errorDescription: String? {
        switch self {
        case .subscriptionLoginRequired:
            return L("O monitoramento de assinatura exige login da conta Meta no Muse Code. Chaves da Meta Model API são pay-as-you-go e não expõem esta cota.")
        case .malformedUsage:
            return L("O Muse retornou uma observação de uso inválida.")
        case .hostUnavailable:
            return L("Não foi possível iniciar o host local do Muse para ler a última observação de uso.")
        case .hostRejected:
            return L("O host local do Muse recusou a leitura de uso.")
        case .credentialImportInvalid:
            return L("O arquivo selecionado não é uma credencial Muse em JSON de texto simples compatível.")
        }
    }
}

// MARK: - MSP data contract

struct MuseUsageReadState: Equatable {
    let account: MuseAccountState
    let usage: MuseSubscriptionUsage?
}

protocol MuseUsageReading {
    func readUsage() async throws -> MuseUsageReadState
}

struct MuseAccountState: Decodable, Equatable {
    let credentialRequired: Bool
    let state: String
    let label: String?

    var isSubscriptionLogin: Bool { state == "accountLogin" }
}

struct MuseUsageReadResult: Decodable, Equatable {
    let usage: MuseSubscriptionUsage?
}

struct MuseSubscriptionUsage: Decodable, Equatable {
    let observedAtMs: Int64
    let tier: String
    let window: MuseSubscriptionUsageWindow
    let weekly: MuseSubscriptionUsageWeekly

    var observedAt: Date { Date(timeIntervalSince1970: TimeInterval(observedAtMs) / 1_000) }

    func validate() throws {
        guard observedAtMs >= 0,
              !tier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              window.usedPercent >= 0,
              window.windowDurationMins > 0,
              window.resetsAtMs >= 0,
              weekly.usedPercent >= 0,
              weekly.resetsAtMs >= 0
        else { throw MuseUsageError.malformedUsage }
    }
}

struct MuseSubscriptionUsageWindow: Decodable, Equatable {
    let resetsAtMs: Int64
    let usedPercent: Int
    let windowDurationMins: Int

    var resetAt: Date { Date(timeIntervalSince1970: TimeInterval(resetsAtMs) / 1_000) }
}

struct MuseSubscriptionUsageWeekly: Decodable, Equatable {
    let resetsAtMs: Int64
    let usedPercent: Int

    var resetAt: Date { Date(timeIntervalSince1970: TimeInterval(resetsAtMs) / 1_000) }
}

// MARK: - Explicit local credential import

/// O chamador deve invocar isto somente depois de o usuário selecionar o arquivo de
/// origem. Não há descoberta automática de `~/.config/muse`, nem leitura de Keychain.
/// A cópia inteira fica em um diretório exclusivo da conta, que o runner usa como
/// `XDG_CONFIG_HOME`; isso impede que uma conta global do CLI substitua outra.
enum MuseCredentialImporter {
    static func importPlaintextAuth(from sourceURL: URL, to destinationURL: URL) throws {
        guard sourceURL.isFileURL, destinationURL.isFileURL else {
            throw MuseUsageError.credentialImportInvalid
        }
        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw MuseUsageError.credentialImportInvalid
        }
        guard isCompatiblePlaintextAuth(data) else {
            throw MuseUsageError.credentialImportInvalid
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)
        } catch {
            throw MuseUsageError.credentialImportInvalid
        }
    }

    /// Deliberadamente só confirma que é um documento Muse em texto JSON; os campos
    /// internos são preservados sem reinterpretar, para não quebrar versões futuras.
    static func isCompatiblePlaintextAuth(_ data: Data) -> Bool {
        guard let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              document["schema_version"] is NSNumber,
              let providers = document["providers"] as? [String: Any],
              providers["meta"] is [String: Any]
        else { return false }
        return true
    }
}

// MARK: - Fixed-command Muse CLI reader

/// Isolated configuration for one Muse account. `configurationRoot` and `dataRoot`
/// must be per-instance app-support directories, never the user's global Muse dirs.
struct MuseCLIConfiguration: Equatable {
    let executableURL: URL
    let configurationRoot: URL
    let dataRoot: URL
    let neutralWorkingDirectory: URL

    var authFileURL: URL {
        configurationRoot.appendingPathComponent("muse/auth.json", isDirectory: false)
    }
}

/// Launches exactly `muse serve --provider meta --no-session-log --disable-shell
/// --disable-write`. There is no shell, prompt, caller-provided argv, or model request.
///
/// Muse 1.4.4 accepts JSON-RPC frames one per stdio line. The exchange must be:
/// `initialize(experimentalApi:true)` -> `initialized` -> `account/read` ->
/// `usage/read`. `account/*` is experimental; `usage/read` has no params/session id.
final class MuseCLIUsageReader: MuseUsageReading {
    private let configuration: MuseCLIConfiguration

    init(configuration: MuseCLIConfiguration) {
        self.configuration = configuration
    }

    func readUsage() async throws -> MuseUsageReadState {
        let process = Process()
        process.executableURL = configuration.executableURL
        process.arguments = ["serve", "--provider", "meta", "--no-session-log", "--disable-shell", "--disable-write"]
        process.currentDirectoryURL = configuration.neutralWorkingDirectory

        var environment = ProcessInfo.processInfo.environment
        // The direct 1.4.4 binary resolves auth under XDG_CONFIG_HOME/muse/auth.json.
        // MUSE_AUTH_PATH remains set for launcher compatibility, but it is not the
        // isolation boundary relied on by this reader.
        environment["XDG_CONFIG_HOME"] = configuration.configurationRoot.path
        environment["XDG_DATA_HOME"] = configuration.dataRoot.path
        environment["MUSE_AUTH_PATH"] = configuration.authFileURL.path
        environment["HOME"] = configuration.configurationRoot.path
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        // Stderr can include provider diagnostics. Never funnel it to an app log that
        // might inadvertently retain credential-adjacent details.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw MuseUsageError.hostUnavailable
        }

        let lineReader = MuseMSPLineReader(fileHandle: output.fileHandleForReading)
        defer {
            input.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
        }

        do {
            try MuseMSPWire.write(MuseMSPWire.initialize(id: 1), to: input.fileHandleForWriting)
            _ = try await lineReader.result(id: 1, as: MuseInitializeResult.self)
            try MuseMSPWire.write(MuseMSPWire.initialized(), to: input.fileHandleForWriting)

            try MuseMSPWire.write(MuseMSPWire.request(id: 2, method: "account/read"), to: input.fileHandleForWriting)
            let account = try await lineReader.result(id: 2, as: MuseAccountState.self)

            try MuseMSPWire.write(MuseMSPWire.request(id: 3, method: "usage/read"), to: input.fileHandleForWriting)
            let usage = try await lineReader.result(id: 3, as: MuseUsageReadResult.self)
            return MuseUsageReadState(account: account, usage: usage.usage)
        } catch let error as MuseUsageError {
            throw error
        } catch {
            throw MuseUsageError.hostUnavailable
        }
    }
}

private struct MuseInitializeResult: Decodable {
    let experimentalApi: Bool
}

enum MuseMSPWire {
    static func initialize(id: Int) -> Data {
        frame([
            "jsonrpc": "2.0",
            "id": id,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "oktally", "version": "1"],
                "capabilities": ["experimentalApi": true, "userInputDialogs": false]
            ]
        ])
    }

    static func initialized() -> Data {
        frame(["jsonrpc": "2.0", "method": "initialized"])
    }

    static func request(id: Int, method: String) -> Data {
        frame(["jsonrpc": "2.0", "id": id, "method": method])
    }

    /// Retido para o coordenador de Auth do app: é o método experimental de login
    /// device-code. O provider de uso nunca o chama automaticamente e não é dono do
    /// processo de longa duração necessário para receber `account/loginCompleted`.
    static func deviceCodeLoginStart(id: Int) -> Data {
        frame([
            "jsonrpc": "2.0",
            "id": id,
            "method": "account/loginStart",
            "params": ["type": "deviceCode"]
        ])
    }

    static func write(_ data: Data, to handle: FileHandle) throws {
        try handle.write(contentsOf: data + Data([0x0A]))
    }

    private static func frame(_ object: [String: Any]) -> Data {
        // These are constant protocol frames; JSON serialization cannot receive user
        // input or credentials from this provider.
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}

private final class MuseMSPLineReader {
    private let nextLine: () async throws -> String?

    init(fileHandle: FileHandle) {
        var iterator = fileHandle.bytes.lines.makeAsyncIterator()
        nextLine = { try await iterator.next() }
    }

    func result<Result: Decodable>(id: Int, as type: Result.Type) async throws -> Result {
        while let line = try await nextLine() {
            let data = Data(line.utf8)
            guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseID = envelope["id"] as? Int,
                  responseID == id
            else { continue } // notification or response belonging to another request

            let response = try JSONDecoder().decode(MuseMSPResponse<Result>.self, from: data)
            guard response.jsonrpc == "2.0" else { throw MuseUsageError.hostRejected }
            if response.error != nil { throw MuseUsageError.hostRejected }
            guard let result = response.result else { throw MuseUsageError.hostRejected }
            return result
        }
        throw MuseUsageError.hostUnavailable
    }
}

private struct MuseMSPResponse<Result: Decodable>: Decodable {
    let jsonrpc: String
    let id: Int
    let result: Result?
    let error: MuseMSPError?
}

private struct MuseMSPError: Decodable {
    let code: Int
}
