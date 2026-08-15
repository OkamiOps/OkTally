// Sources/OkTally/UI/Notch/NotchIslandPanel.swift
import SwiftUI
import AppKit

/// A janela da ilha flutuante: a pílula no topo da tela primária quando não existe
/// recorte físico em tela nenhuma.
///
/// ## Por que uma janela NOSSA, e não o estilo `floating` do `DynamicNotchKit`
///
/// O pacote tem um `DynamicNotchStyle.floating` e a primeira leitura sugere que ele
/// resolveria tudo. Ele não resolve — e o motivo está escrito na documentação dele, em uma
/// linha fácil de passar batido: *"When using the `floating` style, this framework does
/// not support compact mode. Calling `compact(on:)` on these devices will automatically
/// hide the window."* No código é literal: `_compact` começa com
/// `if effectiveStyle(for: screen).isFloating { await hide(); return }`, e a
/// `NotchlessView` desenha SÓ o conteúdo expandido — em qualquer estado que não seja
/// `.expanded` ela se desloca para fora da tela.
///
/// Ou seja: em `floating` o pacote entrega um painel que ou está aberto ou não existe. O
/// pedido é o contrário — uma pílula discreta o dia inteiro, que só cresce no hover. Além
/// disso a `NotchlessView` monta o fundo com `VisualEffectView(material: .popover)`, que é
/// vidro; o painel deste app é preto sólido por decisão explícita do dono.
///
/// O que APROVEITAMOS do pacote, então, é o desenho da janela em si — e é pouco: um
/// `NSPanel` `.borderless` + `.nonactivatingPanel`, `level` alto e
/// `canJoinAllSpaces`+`stationary`. São ~15 linhas replicadas aqui de propósito, e em
/// troca esta janela não tem o observador interno que recria tudo em `NSScreen.screens[0]`
/// (ver `NotchHUDController.reanchor()`), não tem estado escondido e não some quando pedimos
/// para ela ficar compacta.
///
/// O conteúdo, esse sim, é 100% compartilhado com o modo notch: `NotchIslandView` monta as
/// mesmas `NotchWing`, a mesma `NotchBottomRule` e a mesma `NotchExpandedView`.
@MainActor
final class NotchIslandPanel {
    /// Estado da ilha em forma observável.
    ///
    /// Trocar o `rootView` do `NSHostingView` também mudaria a tela, mas mataria a
    /// animação: `withAnimation` precisa de uma mudança que o SwiftUI reconheça como sua,
    /// e uma raiz substituída por fora não é. Com um `@Published` a transição
    /// fechado↔expandido é a mesma mola do modo notch.
    @MainActor
    final class State: ObservableObject {
        @Published var isExpanded = false
    }

    private let appModel: AppModel
    /// Clique na pílula. O controller é quem sabe abrir o popover (e onde ancorá-lo).
    private let onOpen: (NSScreen) -> Void

    private let state = State()
    private var panel: NSPanel?
    private var host: NSHostingView<NotchIslandContainer>?
    private var screen: NSScreen?
    private var collapseTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?

    /// Folga entre a barra de menu e o topo da pílula. `visibleFrame.maxY` já desconta a
    /// barra, então a ilha nunca cobre menu nenhum — ela flutua logo abaixo.
    private static let topGap: CGFloat = 6

    /// Respiro em volta da pílula, dentro da janela, para a sombra caber.
    ///
    /// `fittingSize` mede o LAYOUT e a sombra não faz parte dele: sem esta margem a
    /// janela nasceria do tamanho exato da pílula e cortaria a sombra rente à borda,
    /// deixando um halo quadrado. Não é altura de conteúdo — é moldura da janela.
    private static let shadowMargin: CGFloat = 16

    /// Mesmos tempos do modo notch (`NotchHUDController.hoverChanged`), pelo mesmo motivo:
    /// o cursor cruza o topo da tela o dia inteiro indo para outro lugar, e fechar no
    /// primeiro pixel de saída faria a pílula piscar em cada travessia.
    private static let collapseDelay: Duration = .milliseconds(220)

    /// Duração da mola de fechar. A janela só encolhe DEPOIS disso — encolher junto
    /// cortaria a lista enquanto ela ainda está desaparecendo.
    private static let shrinkDelay: Duration = .milliseconds(360)

    init(appModel: AppModel, onOpen: @escaping (NSScreen) -> Void) {
        self.appModel = appModel
        self.onOpen = onOpen
    }

    var isVisible: Bool { panel != nil }

    /// Onde o popover deve se pendurar: a borda de baixo da pílula, em coordenadas de
    /// tela. `nil` quando a ilha não está na tela.
    var anchorBottomY: CGFloat? {
        guard let panel else { return nil }
        return panel.frame.minY + Self.shadowMargin
    }

    /// Mostra (ou remaneja) a ilha nesta tela. Idempotente: chamar de novo com a mesma
    /// tela só reposiciona.
    func show(on screen: NSScreen) {
        self.screen = screen
        if panel == nil { build() }
        layout()
        panel?.orderFrontRegardless()
    }

    func close() {
        collapseTask?.cancel()
        collapseTask = nil
        resizeTask?.cancel()
        resizeTask = nil
        panel?.orderOut(nil)
        panel = nil
        host = nil
        screen = nil
        state.isExpanded = false
    }

    // MARK: - Janela

    private func build() {
        let host = NSHostingView(rootView: NotchIslandContainer(
            appModel: appModel,
            state: state,
            margin: Self.shadowMargin,
            onOpen: { [weak self] in self?.openRequested() },
            onHover: { [weak self] in self?.hoverChanged($0) }
        ))
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // A sombra é desenhada pelo SwiftUI, seguindo a curva da pílula. A do AppKit
        // seguiria o retângulo da janela — que é transparente — e viraria um borrão
        // quadrado em volta do nada.
        panel.hasShadow = false
        // Mesmo degrau do painel do notch: o popover, que nasce logo abaixo, fica um
        // acima (ver `NotchPopoverPanel`).
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.panel = panel
        self.host = host
    }

    /// Reconcilia tamanho e posição da janela com o que o conteúdo pede AGORA.
    ///
    /// `fittingSize` é a medida do SwiftUI já resolvida — nenhuma altura é cravada aqui,
    /// nem podia ser: a lista expandida tem de uma a cinco linhas.
    private func layout() {
        guard let panel, let host, let screen else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            // A borda de cima da PÍLULA (e não da janela) é o que encosta na folga: a
            // margem da sombra tem de sair da conta.
            y: screen.visibleFrame.maxY - Self.topGap - size.height + Self.shadowMargin
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        host.frame = NSRect(origin: .zero, size: size)
    }

    // MARK: - Hover e clique

    /// Hover é o único gesto que abre — igual ao modo notch.
    ///
    /// A janela CRESCE antes da animação e só ENCOLHE depois dela. Cortar isso pelo meio
    /// apararia a lista contra a borda da janela justamente enquanto ela entra ou sai.
    private func hoverChanged(_ hovering: Bool) {
        collapseTask?.cancel()
        resizeTask?.cancel()
        guard hovering != state.isExpanded else { return }
        if hovering {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                state.isExpanded = true
            }
            layout()
            // Segunda medição um giro depois. `layoutSubtreeIfNeeded` costuma bastar para
            // esvaziar a atualização pendente do SwiftUI, mas não é contratual: se ela
            // ficar para o próximo ciclo, a primeira medida ainda é a da pílula fechada e
            // a lista nasceria aparada. Medir de novo é barato; nascer cortado, não.
            resizeTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                self?.layout()
            }
        } else {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: Self.collapseDelay)
                guard !Task.isCancelled, let self else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                    self.state.isExpanded = false
                }
                self.resizeTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.shrinkDelay)
                    guard !Task.isCancelled else { return }
                    self?.layout()
                }
            }
        }
    }

    private func openRequested() {
        guard let screen else { return }
        onOpen(screen)
    }
}

/// A casca que o `NSHostingView` hospeda: a ilha mais a margem da sombra.
///
/// Separada da `NotchIslandView` porque a margem é assunto da JANELA (é o que impede a
/// sombra de ser cortada), não do desenho da pílula — e a `NotchIslandView` também é usada
/// pelo harness de PNG, onde janela nenhuma existe.
struct NotchIslandContainer: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var state: NotchIslandPanel.State
    let margin: CGFloat
    let onOpen: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        NotchIslandView(
            appModel: appModel,
            isExpanded: state.isExpanded,
            onOpen: onOpen,
            onHover: onHover
        )
        .padding(margin)
        .fixedSize()
    }
}
