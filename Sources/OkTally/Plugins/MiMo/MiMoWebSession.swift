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

enum MiMoConsoleError: Error, LocalizedError {
    case notLoggedIn
    case noData
    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "Sessão do MiMo expirada — entre novamente."
        case .noData: return "MiMo ainda não retornou o uso — abra o painel do plano e aguarde."
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

    private let webView: WKWebView
    private var window: NSWindow?
    private var onDone: (() -> Void)?
    private var loadWaiters: [CheckedContinuation<Void, Error>] = []
    private var everLoaded = false
    private static let planManageURL = URL(string: "https://platform.xiaomimimo.com/#/console/plan-manage")!

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // persistent: login survives app restarts
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 980, height: 720), configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    func presentLogin(onDone: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let done = NSButton(title: "Concluir", target: self, action: #selector(doneTapped))
        done.bezelStyle = .rounded
        let hint = NSTextField(labelWithString: "Faça login e abra o painel do plano; depois clique em Concluir.")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        let bar = NSStackView(views: [hint, NSView(), done])
        bar.orientation = .horizontal
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        let stack = NSStackView(views: [bar, webView])
        stack.orientation = .vertical; stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 780),
                           styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.title = "Entrar no MiMo"; win.isReleasedWhenClosed = false; win.center()
        let content = NSView(frame: win.frame); content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        win.contentView = content
        window = win; self.onDone = onDone
        win.makeKeyAndOrderFront(nil)
        webView.load(URLRequest(url: Self.planManageURL))
    }

    @objc private func doneTapped() {
        webView.removeFromSuperview()
        window?.orderOut(nil)
        let onDone = self.onDone; self.onDone = nil
        DispatchQueue.main.async { self.window = nil; onDone?() }
    }

    func fetchUsageJSON() async throws -> Data {
        let recovery = MiMoSessionRecovery(
            fetch: { [weak self] in try await self?.rawFetch() ?? Data() },
            reload: { [weak self] in try await self?.reloadConsole() }
        )
        return try await recovery.fetchWithRecovery()
    }

    private func rawFetch() async throws -> Data {
        try await ensureConsoleLoaded()
        let js = """
        const r = await fetch('/api/v1/tokenPlan/usage', { credentials: 'include' });
        return await r.text();
        """
        // The console SPA may still be booting right after a load; give the JS bridge a
        // short settling loop. A 401 body is returned immediately — judging it (and
        // recovering via reload) is `MiMoSessionRecovery`'s job, not this method's.
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            if let s = try await webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .page) as? String {
                return Data(s.utf8)
            }
        }
        throw MiMoConsoleError.noData
    }

    private func reloadConsole() async throws {
        everLoaded = false
        try await ensureConsoleLoaded()
        // The SPA re-establishes the STS cookie via redirects after load; give it a beat
        // before the retried fetch.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }

    private func ensureConsoleLoaded() async throws {
        if everLoaded { return }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            loadWaiters.append(c)
            webView.load(URLRequest(url: Self.planManageURL))
        }
    }

    private func resume(_ result: Result<Void, Error>) {
        let ws = loadWaiters; loadWaiters = []
        for w in ws { switch result { case .success: w.resume(); case .failure(let e): w.resume(throwing: e) } }
    }
}

extension MiMoWebSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { everLoaded = true; resume(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { resume(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { resume(.failure(error)) }
}
