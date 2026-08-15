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
/// nele), o preto opaco por baixo e as transições fechado↔expandido com
/// `matchedGeometryEffect`. Compilou limpo no alvo macOS 26 na primeira tentativa. Escrever tudo isso à mão seria refazer
/// pior o que já existe — ver `.superpowers/notch-hud-report.md`.
///
/// O que o pacote NÃO faz e mora aqui: expandir no hover (ele só publica `isHovering`),
/// abrir o popover no clique, e a decisão de nem existir quando a tela não tem notch —
/// o `.auto` do pacote cairia num painel FLUTUANTE no meio da tela, que não é o pedido.
///
/// E há uma coisa que ele faz e que precisa ser DESFEITA: o observador de telas dele
/// recria a janela em `NSScreen.screens[0]`, que ao plugar um monitor externo passa a ser
/// o externo. É daí que vinha o "plugo o monitor e perco meu notch". Quem conserta é
/// `reanchor()` — ver os comentários lá e em `makeNotch()`.
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
    /// Verdadeiro enquanto `reanchor()` está derrubando e refazendo a janela. Durante essa
    /// janela de tempo o hover tem de ficar quieto: `hide()` zera `isHovering`, o nosso
    /// observador acordaria com "saiu" e chamaria `compact(on:)` no meio da reconstrução —
    /// e esse `compact` cancela, lá dentro do pacote, a tarefa que resume a continuação do
    /// `hide()` que estamos esperando. O painel sumiria e a reconstrução ficaria pendurada
    /// para sempre.
    private var isReanchoring = false
    private let popover: NotchPopoverPanel

    init(appModel: AppModel, isEnabled: @escaping () -> Bool) {
        self.appModel = appModel
        self.isEnabled = isEnabled
        self.popover = NotchPopoverPanel(appModel: appModel)
    }

    /// A tela onde o painel pode existir: a que tem notch, e só ela.
    ///
    /// Delega a decisão para `NotchScreenSelection` (pura, testada) e aqui só traduz
    /// `NSScreen` em descritor. `safeAreaInsets.top > 0` é o sinal de que há recorte; as
    /// duas áreas auxiliares são exigidas junto porque é delas que sai a LARGURA do notch
    /// — sem elas o pacote chutaria 300pt e o painel nasceria desalinhado.
    ///
    /// Repare no que NÃO entra na conta: qual é a tela principal. Plugar um monitor
    /// externo costuma promovê-lo a `NSScreen.screens[0]`, e o painel tem de continuar
    /// exatamente onde estava.
    static func notchScreen(_ screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        let descriptors = screens.enumerated().map { index, screen in
            NotchScreenDescriptor(
                id: index,
                hasNotch: screen.safeAreaInsets.top > 0
                    && screen.auxiliaryTopLeftArea != nil
                    && screen.auxiliaryTopRightArea != nil,
                isPrimary: index == 0
            )
        }
        guard let chosen = NotchScreenSelection.select(from: descriptors) else { return nil }
        return screens[chosen.id]
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

    /// Reconfiguração de telas (plugou/desplugou monitor, fechou/abriu a tampa, trocou a
    /// tela principal): re-resolve a tela com notch e re-ancora o painel nela.
    ///
    /// O atraso é um DEBOUNCE, não uma espera esperançosa: o macOS posta várias
    /// `didChangeScreenParameters` durante uma única reconfiguração, e cada notificação
    /// cancela a tarefa anterior — re-ancoramos 300 ms depois da última. De quebra, isso
    /// dá tempo para o observador interno do `DynamicNotchKit` (uma sequência assíncrona,
    /// que roda DEPOIS dos observadores síncronos) fazer a bagunça dele antes de nós.
    private func handleScreenChange() {
        screenChangeTask?.cancel()
        screenChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.reanchor()
        }
    }

    /// Derruba a janela e a refaz na tela certa — ou deixa de existir, se não houver tela
    /// com notch.
    ///
    /// ## Por que não basta um `compact(on:)` novo
    ///
    /// `_compact` sai cedo quando o estado já é `.compact`. Depois que o observador do
    /// pacote sequestra a janela para `NSScreen.screens[0]`, o estado continua `.compact`
    /// e um `compact(on: telaCerta)` seria um no-op: o painel ficaria no monitor externo
    /// (ou em lugar nenhum) para sempre. Por isso passamos SEMPRE por `hide()`, que zera o
    /// estado, e só então reconstruímos.
    ///
    /// ## Por que a segunda passada
    ///
    /// O observador do pacote é assíncrono e não dá garantia de ordem: ele pode acordar
    /// DEPOIS de nós e roubar a janela de volta para `screens[0]`. A verificação confere
    /// em que tela a janela realmente ficou e refaz uma vez se estiver errada.
    private func reanchor() async {
        guard let notch else {
            // Nunca houve painel (app começou sem notch, ou preferência desligada):
            // o caminho normal já resolve, inclusive criando a janela se agora dá.
            refresh()
            return
        }
        collapseTask?.cancel()
        popover.close()
        isReanchoring = true
        defer { isReanchoring = false }

        for attempt in 0 ..< 2 {
            let target = Self.notchScreen()
            await notch.hide()
            // `hide()` sai cedo quando o estado já é `.hidden` e nesse caminho NÃO destrói
            // a janela — inclusive uma que o pacote tenha acabado de recriar sozinho.
            // `windowController` é público justamente para isto.
            notch.windowController?.close()
            notch.windowController = nil
            guard !Task.isCancelled, isEnabled(), let target else { return }
            await notch.compact(on: target)
            guard !Task.isCancelled else { return }
            if attempt == 0 {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                if notch.windowController?.window?.screen === target { return }
            }
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

    /// Destrói a JANELA, não o objeto — ver `makeNotch()`.
    private func teardown() {
        collapseTask?.cancel()
        popover.close()
        guard let notch else { return }
        Task {
            await notch.hide()
            notch.windowController?.close()
            notch.windowController = nil
        }
    }

    /// Cria o `DynamicNotch` UMA vez na vida do controller. A instância nunca é
    /// descartada, mesmo com o painel desligado ou sem tela com notch — só a janela é.
    ///
    /// Isso não é apego: o `init` do pacote dispara uma `Task` infinita
    /// (`observeScreenParameters`) que captura `self` FORTE e, a cada mudança de telas,
    /// chama `initializeWindow(screen: NSScreen.screens.first)`. Uma instância largada não
    /// morre — vira um zumbi que continua abrindo janelas em `screens[0]` para sempre, e a
    /// cada reconfiguração de telas nasceria mais um. Mantendo uma só, todo sequestro de
    /// janela acontece num objeto que ainda temos na mão e que `reanchor()` conserta.
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
            compactLeading: { [appModel] in NotchCompactLeading(appModel: appModel) },
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
        // `isEnabled()` e `isReanchoring` são guardas de vida, não otimizações: o `hide()`
        // do desligamento e o da re-ancoragem zeram `isHovering`, e sem elas este método
        // reabriria a janela que acabou de ser destruída (ou atropelaria a reconstrução).
        guard !isReanchoring, isEnabled(), let notch, let screen = Self.notchScreen() else { return }
        if hovering {
            Task { await notch.expand(on: screen) }
        } else {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled, self?.isReanchoring == false else { return }
                await notch.compact(on: screen)
            }
        }
    }

    private func openPopover() {
        guard let screen = Self.notchScreen() else { return }
        popover.toggle(on: screen)
    }
}
