// Sources/OkTally/UI/Notch/NotchHUDController.swift
import SwiftUI
import AppKit
import Combine
import DynamicNotchKit

/// Liga (ou não) o painel do notch ao ciclo de vida do app.
///
/// ## Por que `DynamicNotchKit` e não um `NSPanel` na mão
///
/// O macOS não tem API de Dynamic Island; o padrão real é uma janela flutuante
/// (`.borderless` + `.nonactivatingPanel`, `level` alto, `canJoinAllSpaces`+`stationary`)
/// colada ao notch. `DynamicNotchKit` já é exatamente isso, e ainda traz o que dá
/// trabalho e é fácil de errar: a geometria do notch por `auxiliaryTopLeftArea`/
/// `auxiliaryTopRightArea`, a `NotchShape` com os cantos inferiores em "asa" (que é o
/// desenho que faz o painel passar por extensão do notch em vez de retângulo colado
/// nele), o preto opaco por baixo, as transições fechado↔expandido com
/// `matchedGeometryEffect`, e o re-registro em `didChangeScreenParameters`. Compilou
/// limpo no alvo macOS 26 na primeira tentativa. Escrever tudo isso à mão seria refazer
/// pior o que já existe — ver `.superpowers/notch-hud-report.md`.
///
/// O que o pacote NÃO faz e mora aqui: expandir no hover (ele só publica `isHovering`),
/// abrir o popover no clique, e a decisão de nem existir quando a tela não tem notch —
/// o `.auto` do pacote cairia num painel FLUTUANTE no meio da tela, que não é o pedido.
@MainActor
final class NotchHUDController {
    private let appModel: AppModel
    /// Lido a cada avaliação (e não capturado uma vez) para o `Toggle` das Preferências
    /// valer sem reiniciar o app.
    private let isEnabled: () -> Bool

    private var notch: DynamicNotch<NotchExpandedView, NotchCompactLeading, NotchCompactTrailing>?
    private var hoverObserver: AnyCancellable?
    private var screenObserver: AnyCancellable?
    private var collapseTask: Task<Void, Never>?
    private var screenChangeTask: Task<Void, Never>?
    private let popover: NotchPopoverPanel

    init(appModel: AppModel, isEnabled: @escaping () -> Bool) {
        self.appModel = appModel
        self.isEnabled = isEnabled
        self.popover = NotchPopoverPanel(appModel: appModel)
    }

    /// A tela onde o painel pode existir: a embutida, e só ela.
    ///
    /// `safeAreaInsets.top > 0` é o sinal de que há recorte; as duas áreas auxiliares são
    /// exigidas junto porque é delas que sai a LARGURA do notch — sem elas o pacote
    /// chutaria 300pt e o painel nasceria desalinhado. Monitor externo, MacBook de tampa
    /// fechada ou espelhamento: nada disso passa no teste, e aí não há painel nenhum —
    /// a barra de menu continua sozinha, que é o comportamento pedido.
    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first {
            $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil
        }
    }

    /// Começa a observar telas e mostra o painel se houver notch. Idempotente: chamar de
    /// novo depois de mudar a preferência é a forma de aplicar a mudança.
    func start() {
        if screenObserver == nil {
            screenObserver = NotificationCenter.default
                .publisher(for: NSApplication.didChangeScreenParametersNotification)
                .sink { [weak self] _ in self?.handleScreenChange() }
        }
        refresh()
    }

    /// Reconfiguração de telas: derruba a janela e reconstrói do zero.
    ///
    /// Isto é mais bruto do que um `compact(on:)` novo, e de propósito — o
    /// `DynamicNotchKit` observa `didChangeScreenParameters` por conta própria e recria a
    /// janela em `NSScreen.screens[0]`, que NÃO é necessariamente a tela com notch (com um
    /// monitor externo como principal, é ele). Além disso `compact(on:)` sai cedo quando o
    /// estado já é `.compact`, então ele nem chegaria a perceber que a janela ficou na tela
    /// errada. Fechar e refazer é o único caminho que não depende de detalhe interno do
    /// pacote.
    ///
    /// O atraso existe porque o observador do pacote é uma sequência assíncrona: ele roda
    /// DEPOIS dos observadores síncronos. Sem esperar, arrumaríamos a janela antes de o
    /// pacote a estragar.
    private func handleScreenChange() {
        screenChangeTask?.cancel()
        let notch = self.notch
        screenChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            if let notch {
                await notch.hide()
                // `hide()` sai cedo quando o estado já é `.hidden` e deixa de destruir a
                // janela — inclusive uma que o pacote tenha acabado de recriar sozinho.
                // `windowController` é público justamente para isto.
                notch.windowController?.close()
            }
            self?.notch = nil
            self?.hoverObserver = nil
            self?.refresh()
        }
    }

    /// Reavalia do zero: preferência desligada ou tela sem notch → o painel deixa de
    /// existir (a janela é destruída, não escondida). Caso contrário, painel fechado.
    func refresh() {
        guard isEnabled(), let screen = Self.notchScreen() else {
            teardown()
            return
        }
        let notch = notch ?? makeNotch()
        Task { await notch.compact(on: screen) }
    }

    private func teardown() {
        collapseTask?.cancel()
        popover.close()
        guard let notch else { return }
        self.notch = nil
        hoverObserver = nil
        Task {
            await notch.hide()
            notch.windowController?.close()
        }
    }

    private func makeNotch() -> DynamicNotch<NotchExpandedView, NotchCompactLeading, NotchCompactTrailing> {
        let notch = DynamicNotch(
            // Sem `hapticFeedback`: o painel abre toda vez que o cursor cruza o topo da
            // tela indo para outra coisa, e um tec no trackpad a cada travessia é
            // sabotagem. `keepVisible` também fica de fora — quem decide fechar aqui é o
            // `hoverChanged`, não o pacote.
            hoverBehavior: [.increaseShadow],
            // `.notch` fixo, nunca `.auto`: sem notch este controller nem chega aqui.
            // 22pt embaixo é o raio de "asa" que o dono pediu — o painel termina em duas
            // curvas largas, como se o próprio notch tivesse crescido.
            style: .notch(topCornerRadius: 12, bottomCornerRadius: 22),
            expanded: { [appModel] in
                NotchExpandedView(appModel: appModel, onOpen: { [weak self] in self?.openPopover() })
            },
            compactLeading: { NotchCompactLeading() },
            compactTrailing: { [appModel] in NotchCompactTrailing(appModel: appModel) }
        )
        notch.transitionConfiguration = .init(
            openingAnimation: .bouncy(duration: 0.4),
            conversionAnimation: .spring(response: 0.34, dampingFraction: 0.78),
            // Sem isto, ir de fechado para expandido passa por um "esconde e reabre" com
            // 0,25s de painel apagado no meio — o pulo que a mola deveria evitar.
            skipIntermediateHides: true
        )
        hoverObserver = notch.$isHovering
            .removeDuplicates()
            .sink { [weak self] hovering in
                Task { @MainActor in self?.hoverChanged(hovering) }
            }
        self.notch = notch
        return notch
    }

    /// Hover é o único gesto que abre o painel. O pacote publica `isHovering` mas não
    /// muda de estado sozinho, então a política é nossa.
    ///
    /// A demora ao SAIR existe porque o cursor atravessa o topo da tela o tempo todo para
    /// chegar na barra de menu: fechar no primeiro pixel de saída faria o painel piscar em
    /// cada travessia. 220ms é curto o bastante para não parecer preso e longo o bastante
    /// para aguentar o vaivém de quem está mirando numa linha.
    private func hoverChanged(_ hovering: Bool) {
        collapseTask?.cancel()
        guard let notch, let screen = Self.notchScreen() else { return }
        if hovering {
            Task { await notch.expand(on: screen) }
        } else {
            collapseTask = Task {
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                await notch.compact(on: screen)
            }
        }
    }

    private func openPopover() {
        guard let screen = Self.notchScreen() else { return }
        popover.toggle(on: screen)
    }
}
