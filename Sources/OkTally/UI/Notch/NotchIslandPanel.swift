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
    private let preferences: PreferencesStore
    /// Clique na pílula. O controller é quem sabe abrir o popover (e onde ancorá-lo).
    private let onOpen: (NSScreen) -> Void

    private let state = State()
    private var panel: NSPanel?
    private var host: NSHostingView<NotchIslandContainer>?
    private var screen: NSScreen?
    private var collapseTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?

    /// Onde o dono largou a pílula NESTA tela, como fração de 0 a 1 da largura. Começa no
    /// centro e é recarregada a cada troca de tela.
    private var fraction: CGFloat = NotchIslandGeometry.centerFraction
    /// Distância entre o cursor e o centro da pílula no instante em que o arrasto começou.
    /// `nil` = não há arrasto em curso.
    private var dragAnchorOffset: CGFloat?

    /// Respiro dos LADOS e de BAIXO da pílula, dentro da janela, para a sombra caber.
    ///
    /// `fittingSize` mede o LAYOUT e a sombra não faz parte dele: sem esta margem a
    /// janela nasceria do tamanho exato da pílula e cortaria a sombra rente à borda,
    /// deixando um halo quadrado. Não é altura de conteúdo — é moldura da janela.
    ///
    /// Em CIMA não há margem nenhuma, e isso é o conserto da reclamação principal: a
    /// pílula encosta na borda de cima da tela, dentro da região vazia da barra de menu,
    /// como um recorte que a tela não tem. Qualquer respiro ali reabriria o vão que fazia
    /// o painel parecer uma janelinha solta sobre a barra de ferramentas do navegador.
    /// Sombra para cima também não existiria: não há nada acima da borda da tela.
    private static let shadowMargin: CGFloat = 16

    /// Mesmos tempos do modo notch (`NotchHUDController.hoverChanged`), pelo mesmo motivo:
    /// o cursor cruza o topo da tela o dia inteiro indo para outro lugar, e fechar no
    /// primeiro pixel de saída faria a pílula piscar em cada travessia.
    private static let collapseDelay: Duration = .milliseconds(220)

    /// Duração da mola de fechar. A janela só encolhe DEPOIS disso — encolher junto
    /// cortaria a lista enquanto ela ainda está desaparecendo.
    private static let shrinkDelay: Duration = .milliseconds(360)

    init(appModel: AppModel, preferences: PreferencesStore, onOpen: @escaping (NSScreen) -> Void) {
        self.appModel = appModel
        self.preferences = preferences
        self.onOpen = onOpen
    }

    var isVisible: Bool { panel != nil }

    /// Onde o popover deve se pendurar: a borda de baixo da pílula, em coordenadas de
    /// tela. `nil` quando a ilha não está na tela.
    var anchorBottomY: CGFloat? {
        guard let panel else { return nil }
        return panel.frame.minY + Self.shadowMargin
    }

    /// Em que X o popover deve se centralizar. Deixou de ser o meio da tela no dia em que
    /// a pílula passou a poder ser arrastada: um popover no centro pendurado numa pílula
    /// encostada na borda seria um balão apontando para o nada.
    var anchorCenterX: CGFloat? { panel?.frame.midX }

    /// Mostra (ou remaneja) a ilha nesta tela. Idempotente: chamar de novo com a mesma
    /// tela só reposiciona.
    func show(on screen: NSScreen) {
        if self.screen !== screen {
            // Cada tela guarda a própria posição: o dono arrasta a pílula para um canto no
            // monitor da esquerda e para outro no da direita.
            fraction = NotchIslandGeometry.clampFraction(
                CGFloat(preferences.islandFraction(screenId: Self.screenId(screen))
                        ?? Double(NotchIslandGeometry.centerFraction))
            )
        }
        self.screen = screen
        if panel == nil { build() }
        layout()
        panel?.orderFrontRegardless()
    }

    /// O identificador do display, para a posição não se confundir entre monitores. O
    /// número do `NSScreen` é estável enquanto a tela estiver plugada, que é exatamente o
    /// tempo em que a posição importa; sem ele (caso que a documentação não promete que
    /// não acontece) todas as telas caem numa chave só, o que é pior mas não quebra.
    private static func screenId(_ screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number.map { "display\($0.uint32Value)" } ?? "display-unknown"
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
        dragAnchorOffset = nil
        state.isExpanded = false
    }

    // MARK: - Janela

    private func build() {
        let host = NSHostingView(rootView: NotchIslandContainer(
            appModel: appModel,
            state: state,
            margin: Self.shadowMargin,
            onOpen: { [weak self] in self?.openRequested() },
            onHover: { [weak self] in self?.hoverChanged($0) },
            onDragChanged: { [weak self] in self?.dragChanged() },
            onDragEnded: { [weak self] in self?.dragEnded() },
            onRecenter: { [weak self] in self?.recenter() }
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
    /// nem podia ser: a lista expandida tem de uma a cinco linhas. A conta de ONDE isso
    /// vai parar não mora aqui: é `NotchIslandGeometry`, que é pura e testada, porque
    /// posição de janela é a única parte deste painel que PNG nenhum revela.
    ///
    /// - Parameter animated: só o ímã do centro anima. Todo o resto (expandir, encolher,
    ///   reancorar) tem de ser instantâneo: animar a JANELA junto com a mola do conteúdo
    ///   daria duas velocidades para a mesma transição.
    private func layout(animated: Bool = false) {
        guard let panel, let host, let screen else { return }
        host.layoutSubtreeIfNeeded()
        let measured = host.fittingSize
        guard measured.width > 0, measured.height > 0 else { return }
        // `fittingSize` mede a janela inteira (pílula + margens da sombra); a geometria
        // raciocina sobre a PÍLULA, que é o que o dono vê e o que precisa caber na tela.
        let pill = CGSize(
            width: measured.width - Self.shadowMargin * 2,
            height: measured.height - Self.shadowMargin
        )
        let frame = NotchIslandGeometry.windowFrame(
            screenFrame: screen.frame,
            pillSize: pill,
            horizontalMargin: Self.shadowMargin,
            bottomMargin: Self.shadowMargin,
            fraction: fraction
        )
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        host.frame = NSRect(origin: .zero, size: frame.size)
    }

    // MARK: - Hover e clique

    /// Hover é o único gesto que abre — igual ao modo notch.
    ///
    /// A janela CRESCE antes da animação e só ENCOLHE depois dela. Cortar isso pelo meio
    /// apararia a lista contra a borda da janela justamente enquanto ela entra ou sai.
    private func hoverChanged(_ hovering: Bool) {
        // Durante o arrasto a janela anda embaixo do cursor e o AppKit dispara
        // entrou/saiu a cada passo. Obedecer a isso faria a pílula abrir e fechar
        // enquanto ela é arrastada — o gesto ficaria impossível de mirar.
        guard dragAnchorOffset == nil else { return }
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

    // MARK: - Arrasto horizontal

    /// O dono está arrastando a pílula pelo topo da tela.
    ///
    /// ## Por que a posição vem do `NSEvent`, e não da translação do gesto
    ///
    /// O gesto do SwiftUI mede a partir da view — e a view mora dentro da janela que este
    /// método MOVE. Assim que a janela acompanha o cursor, a translação volta para perto
    /// de zero e a pílula trava: a conta se morde. `NSEvent.mouseLocation` está em
    /// coordenadas de TELA, que é o único referencial que não anda junto.
    ///
    /// O gesto continua servindo para uma coisa que o `NSEvent` não dá: o limiar de 4pt
    /// que separa um clique de um arrasto.
    private func dragChanged() {
        guard let panel, let screen else { return }
        let mouseX = NSEvent.mouseLocation.x
        if dragAnchorOffset == nil {
            // A pílula não pula para debaixo do cursor: ela mantém a distância que tinha
            // quando o arrasto começou, que é o que faz o gesto parecer que se está
            // segurando a coisa, e não empurrando.
            dragAnchorOffset = panel.frame.midX - mouseX
            collapseTask?.cancel()
            resizeTask?.cancel()
        }
        fraction = NotchIslandGeometry.fraction(
            forCenterX: mouseX + (dragAnchorOffset ?? 0),
            screenFrame: screen.frame
        )
        layout()
    }

    /// Soltou. O ímã do centro decide se a posição escolhida vale como está, e só então
    /// ela é gravada — arrastar sem soltar não pode deixar rastro nas preferências.
    private func dragEnded() {
        defer { dragAnchorOffset = nil }
        guard let screen else { return }
        fraction = NotchIslandGeometry.snappedFraction(fraction, screenFrame: screen.frame)
        persistFraction()
        layout(animated: true)
    }

    /// Duplo clique: de volta ao meio da tela.
    private func recenter() {
        fraction = NotchIslandGeometry.centerFraction
        persistFraction()
        layout(animated: true)
    }

    private func persistFraction() {
        guard let screen else { return }
        preferences.setIslandFraction(Double(fraction), screenId: Self.screenId(screen))
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
    let onDragChanged: () -> Void
    let onDragEnded: () -> Void
    let onRecenter: () -> Void

    var body: some View {
        NotchIslandView(
            appModel: appModel,
            isExpanded: state.isExpanded,
            onOpen: onOpen,
            onHover: onHover,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded,
            onRecenter: onRecenter
        )
        // Margem só dos lados e embaixo. Em cima a pílula encosta na borda da janela,
        // que por sua vez encosta na borda da tela — ver `shadowMargin`.
        .padding(.horizontal, margin)
        .padding(.bottom, margin)
        .fixedSize()
        // ESTA linha é o conserto do "expande, se move e depois volta".
        //
        // A janela muda de tamanho de uma vez (é um `setFrame`), o conteúdo cresce numa
        // mola de 0,34s. Durante esses 0,34s a janela já está alta e a pílula ainda é
        // pequena — e o `NSHostingView` centraliza o que sobra. O resultado é a pílula
        // descendo até o meio de uma janela invisível e voltando: exatamente o pulo que o
        // dono viu. Grudando o conteúdo no TOPO da janela (cuja borda de cima é fixa por
        // construção), a única coisa que se mexe é a borda de baixo, que é o que crescer
        // significa.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
