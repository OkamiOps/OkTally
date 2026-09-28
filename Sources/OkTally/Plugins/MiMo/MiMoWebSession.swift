// Sources/OkTally/Plugins/MiMo/MiMoWebSession.swift
import AppKit
import WebKit

// MARK: - Usage payload (pinned from a captured live response of GET /api/v1/tokenPlan/usage)

struct MiMoUsageResponse: Decodable, Equatable {
    struct Bucket: Decodable, Equatable {
        let percent: Double?   // a fraction, e.g. 0.0622 == 6.22%
    }
    struct DataField: Decodable, Equatable {
        let usage: Bucket?       // whole-plan usage
        let monthUsage: Bucket?  // current-month usage
    }
    let data: DataField?
}

enum MiMoConsoleError: Error, LocalizedError, Equatable {
    /// O SSO da Xiaomi em si não está mais de pé: só um login manual resolve.
    case notLoggedIn
    /// O console respondeu, mas não com o uso (SPA bootando, gateway mudo, corpo vazio).
    case noData
    /// Este tick caiu, mas a sessão tem como voltar sozinha no próximo — os cookies de
    /// console são session-only e a cadeia do SSO leva alguns segundos para se refazer.
    /// Existe para que um tropeço não seja apresentado ao dono como "entre de novo".
    case sessionRecovering
    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return L("Sessão do MiMo expirada — entre novamente.")
        case .noData: return L("MiMo ainda não retornou o uso — abra o painel do plano e aguarde.")
        case .sessionRecovering: return L("Renovando a sessão do MiMo — o próximo ciclo deve voltar.")
        }
    }
}

protocol MiMoUsageFetching {
    func fetchUsageJSON() async throws -> Data
}

// MARK: - Web session

/// One long-lived `WKWebView` used for both the login window and the headless usage read.
/// Because the same web view performs the fetch, the request carries the exact session the
/// user's own navigation established (Xiaomi SSO + STS), which a copied cookie or a second
/// web view never reproduced.
@MainActor
final class MiMoWebSession: NSObject, MiMoUsageFetching {
    static let shared = MiMoWebSession()

    /// Teto da espera pela cadeia de redirects do SSO. Generoso de propósito: o ciclo do
    /// provider é de 10 min, então 20s "presos" aqui custam nada perto de declarar logout.
    private static let sessionWaitTimeout: TimeInterval = 20
    private static let probeInterval: UInt64 = 500_000_000

    private let webView: WKWebView
    private var loginWindow: NSWindow?
    private var onDone: (() -> Void)?
    private var loadWaiters: [CheckedContinuation<Void, Error>] = []
    private var everLoaded = false
    private var inFlight: Task<Data, Error>?

    /// Casa permanente e invisível da web view.
    ///
    /// Quando "Concluir" fazia `removeFromSuperview()`, a web view ficava órfã de janela — e
    /// o WebKit throttla agressivamente timers e JS de uma view fora de tela: a cadeia de
    /// redirects do re-login passava a levar dezenas de segundos (ou a não rodar até o app
    /// voltar ao primeiro plano), o que fazia toda recuperação estourar o prazo. Uma janela
    /// borderless, transparente e posicionada fora de qualquer tela mantém a view "na tela"
    /// aos olhos do WebKit sem aparecer para ninguém.
    private lazy var hostWindow: NSWindow = {
        let frame = NSRect(x: -20_000, y: -20_000, width: 1_000, height: 760)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        return window
    }()

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // persistent: login survives app restarts
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 980, height: 720), configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    // MARK: - Login window

    func presentLogin(onDone: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let done = NSButton(title: L("Concluir"), target: self, action: #selector(doneTapped))
        done.bezelStyle = .rounded
        let hint = NSTextField(labelWithString: L("Faça login e abra o painel do plano; depois clique em Concluir."))
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        let bar = NSStackView(views: [hint, NSView(), done])
        bar.orientation = .horizontal
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        webView.removeFromSuperview()
        let stack = NSStackView(views: [bar, webView])
        stack.orientation = .vertical; stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 780),
                           styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.title = L("Entrar no MiMo"); win.isReleasedWhenClosed = false; win.center()
        let content = NSView(frame: win.frame); content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        win.contentView = content
        // Fechar no botão vermelho NUNCA chamava `onDone`: quem logava e fechava a janela
        // pelo título ficava com `mimo.loggedIn` em falso e sem uso automático nenhum.
        win.delegate = self
        loginWindow = win; self.onDone = onDone
        everLoaded = false
        win.makeKeyAndOrderFront(nil)
        MiMoLog.session.notice("login: janela aberta")
        webView.load(URLRequest(url: MiMoConsoleHost.planManageURL))
    }

    @objc private func doneTapped() {
        loginWindow?.close() // o delegate cuida do resto — um caminho só para os dois botões
    }

    /// Fechar a janela (botão vermelho ou "Concluir") conta como concluir. Não conferimos a
    /// sessão aqui: o flag só abre a porta para o ciclo tentar, e é o próprio fetch — com a
    /// recuperação por reload — que decide se ela vale. Marcar `true` e deixar o polling
    /// confirmar erra menos que exigir um fetch síncrono no clique, que compete com a
    /// navegação que o próprio login acabou de disparar.
    private func finishLogin() {
        guard let onDone else { return }
        self.onDone = nil
        loginWindow?.delegate = nil
        loginWindow = nil
        attachToHostWindow()
        MiMoLog.session.notice("login: janela fechada — sessão marcada para o ciclo validar")
        DispatchQueue.main.async { onDone() }
    }

    private func attachToHostWindow() {
        guard loginWindow == nil else { return } // durante o login a view mora na janela visível
        guard let content = hostWindow.contentView else { return }
        if webView.superview !== content {
            webView.removeFromSuperview()
            webView.frame = content.bounds
            webView.autoresizingMask = [.width, .height]
            content.addSubview(webView)
        }
        // `orderFrontRegardless` não rouba foco nem aparece (alpha 0, fora de qualquer tela),
        // mas é o que faz o WebKit tratar a view como visível.
        hostWindow.orderFrontRegardless()
    }

    // MARK: - Fetch

    func fetchUsageJSON() async throws -> Data {
        if loginWindow != nil {
            // Navegar agora atropelaria o que o dono está digitando na janela de login.
            MiMoLog.session.debug("fetch: adiado, janela de login aberta")
            throw MiMoConsoleError.sessionRecovering
        }
        // Single-flight: o "Atualizar" manual e o ciclo periódico chegavam juntos aqui e cada
        // um mandava a MESMA web view navegar, cancelando a navegação do outro (-999,
        // NSURLErrorCancelled) — duas recuperações se matando em vez de uma funcionando.
        if let inFlight {
            MiMoLog.session.debug("fetch: entrando na carona de um fetch em andamento")
            return try await inFlight.value
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { throw MiMoConsoleError.noData }
            defer { self.inFlight = nil }
            let recovery = MiMoSessionRecovery(
                fetch: { [weak self] in try await self?.rawFetch() ?? Data() },
                reload: { [weak self] in try await self?.reloadConsole() }
            )
            return try await recovery.fetchWithRecovery()
        }
        inFlight = task
        // `Task` não herda cancelamento: se quem pediu desistir, a recuperação segue até o
        // fim e o próximo pedido reaproveita o resultado em vez de recomeçar a cadeia.
        return try await task.value
    }

    private func rawFetch() async throws -> Data {
        try await ensureConsoleLoaded()
        let location = MiMoConsoleHost.location(of: webView.url)
        MiMoLog.session.debug("fetch: web view em \(Self.label(location), privacy: .public)")
        guard location == .console else {
            // Fora do host do console nem pedimos — a recuperação transforma isso num reload,
            // que é exatamente a cadeia do SSO rodando de novo.
            throw MiMoConsoleError.notLoggedIn
        }
        // A SPA pode ainda estar bootando logo depois de um load; um laço curto de acomodação.
        // Julgar o corpo (e recuperar via reload) é papel da `MiMoSessionRecovery`.
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            if let body = try await probeUsage() { return body }
        }
        throw MiMoConsoleError.noData
    }

    /// Um único GET, sempre na URL ABSOLUTA do console. Relativo (`/api/v1/tokenPlan/usage`)
    /// resolvia contra a página carregada no instante do fetch: no meio da cadeia do SSO isso
    /// batia em `account.xiaomi.com` e voltava HTML que nunca foi o uso do plano.
    private func probeUsage() async throws -> Data? {
        let js = """
        const r = await fetch(url, { credentials: 'include' });
        return await r.text();
        """
        let result = try await webView.callAsyncJavaScript(
            js, arguments: ["url": MiMoConsoleHost.usageURL.absoluteString],
            in: nil, contentWorld: .page
        )
        guard let text = result as? String else { return nil }
        return Data(text.utf8)
    }

    private func reloadConsole() async throws {
        everLoaded = false
        MiMoLog.session.notice("reload: recarregando o console para refazer a cadeia do SSO")
        try await ensureConsoleLoaded()
        try await waitForConsoleSession()
    }

    /// O re-login NÃO termina no primeiro `didFinish`. Ele é uma cadeia de redirects em JS:
    /// console → `account.xiaomi.com/pass/serviceLogin` → `/sts` (que grava o cookie) →
    /// volta para `platform.xiaomimimo.com`. O `sleep` fixo de 2s que existia aqui só
    /// acertava com rede boa; fora disso o fetch seguinte pegava a página do SSO e o 401 era
    /// declarado definitivo — a origem do "desconecta toda hora". Agora esperamos a
    /// CONDIÇÃO: host do console de volta E uma sondagem que não é 401.
    private func waitForConsoleSession() async throws {
        let deadline = Date().addingTimeInterval(Self.sessionWaitTimeout)
        var probes = 0
        while Date() < deadline {
            let location = MiMoConsoleHost.location(of: webView.url)
            if location == .console {
                probes += 1
                if let body = try? await probeUsage(),
                   MiMoResponseClassifier.classify(body) != .unauthorized {
                    MiMoLog.session.notice("espera: sessão do console de volta (\(probes, privacy: .public) sondagens)")
                    return
                }
            } else if location == .login, await isShowingLoginForm() {
                // Não é redirect em trânsito: é formulário na cara. Aí sim é re-login de verdade.
                MiMoLog.session.error("espera: SSO parou num formulário de login")
                throw MiMoConsoleError.notLoggedIn
            }
            try? await Task.sleep(nanoseconds: Self.probeInterval)
        }
        // Sem veredito: deixamos o fetch seguinte julgar. Lentidão não é logout.
        MiMoLog.session.error("espera: \(Int(Self.sessionWaitTimeout), privacy: .public)s sem sessão de console, host=\(Self.label(MiMoConsoleHost.location(of: self.webView.url)), privacy: .public)")
    }

    /// Distingue "parado no SSO pedindo credenciais" de "atravessando o SSO": as páginas
    /// intermediárias (`/sts?ticket=…`) são redirecionadores sem UI nenhuma.
    private func isShowingLoginForm() async -> Bool {
        let js = """
        return !!(document.querySelector('input[type=password]')
            || document.querySelector('form[action*="serviceLogin"]')
            || document.querySelector('.login-content, #login-wrap, .qrcode-login, .sns-login'));
        """
        let value = try? await webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .page)
        return (value as? Bool) ?? false
    }

    private func ensureConsoleLoaded() async throws {
        attachToHostWindow()
        if everLoaded, MiMoConsoleHost.location(of: webView.url) == .console { return }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            loadWaiters.append(c)
            MiMoLog.session.debug("load: abrindo o painel do plano")
            webView.load(URLRequest(url: MiMoConsoleHost.planManageURL))
        }
    }

    private func resume(_ result: Result<Void, Error>) {
        let ws = loadWaiters; loadWaiters = []
        for w in ws { switch result { case .success: w.resume(); case .failure(let e): w.resume(throwing: e) } }
    }

    private static func label(_ location: MiMoConsoleLocation) -> String {
        switch location {
        case .console: return "console"
        case .login: return "sso-xiaomi"
        case .unknown: return "desconhecido"
        }
    }
}

extension MiMoWebSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        everLoaded = true
        MiMoLog.session.debug("nav: didFinish em \(Self.label(MiMoConsoleHost.location(of: webView.url)), privacy: .public)")
        resume(.success(()))
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MiMoLog.session.error("nav: didFail código \((error as NSError).code, privacy: .public)")
        resume(.failure(error))
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MiMoLog.session.error("nav: didFailProvisional código \((error as NSError).code, privacy: .public)")
        resume(.failure(error))
    }
}

extension MiMoWebSession: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { finishLogin() }
}
