// Sources/OkTally/UI/Notch/NotchPopoverPanel.swift
import SwiftUI
import AppKit

/// O popover completo do app, ancorado sob o notch.
///
/// POR QUE UMA JANELA PRÓPRIA, e não o popover do `MenuBarExtra`: o `MenuBarExtra` não
/// expõe nenhuma API para ser aberto por código — quem quer isso mexe no `NSStatusItem`
/// escondido atrás dele, que é privado, muda de forma entre versões do macOS e some se a
/// Apple trocar a implementação. Um clique no notch que às vezes não abre nada é pior do
/// que não ter clique. Este painel hospeda a MESMA `PopoverView`, com o mesmo modelo, e
/// não depende de detalhe interno nenhum.
///
/// Ele NÃO ativa o app: a janela é `.nonactivatingPanel` e entra com
/// `orderFrontRegardless()`, então o app da frente não perde o foco — igual ao popover da
/// barra de menu. Como o painel nunca vira key, fechar é responsabilidade de um monitor
/// global de clique: qualquer clique fora dele o dispensa.
@MainActor
final class NotchPopoverPanel {
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var isOpen: Bool { panel?.isVisible == true }

    /// - Parameter below: de que altura (em coordenadas de tela) o popover deve pender.
    ///   `nil` = da barra de menu, que é onde o painel do notch termina. A ilha flutuante
    ///   passa a borda de baixo dela, senão o popover nasceria POR TRÁS da pílula.
    func toggle(on screen: NSScreen, below anchorY: CGFloat? = nil) {
        if isOpen { close() } else { open(on: screen, below: anchorY) }
    }

    func open(on screen: NSScreen, below anchorY: CGFloat? = nil) {
        close()
        let host = NSHostingView(rootView: PopoverView(appModel: appModel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)

        let panel = NSPanel(
            contentRect: host.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        // Um degrau ACIMA do painel do notch (que fica em `.screenSaver`): o popover
        // nasce colado embaixo dele e não pode passar por trás.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.setFrameOrigin(origin(for: host.frame.size, on: screen, below: anchorY))
        panel.orderFrontRegardless()
        self.panel = panel

        // Monitor GLOBAL: recebe cliques que acontecem em outros apps, que é justamente o
        // gesto de "dispensar". Cliques dentro do painel são locais e não passam por aqui,
        // então os botões do popover continuam funcionando.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }

    /// Centralizado no painel e logo abaixo dele. Sem âncora explícita o teto é
    /// `visibleFrame.maxY`, que já desconta a barra de menu — o topo do popover encosta
    /// nela sem cobri-la, que é o certo para o painel colado no notch.
    private func origin(for size: CGSize, on screen: NSScreen, below anchorY: CGFloat?) -> CGPoint {
        CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: (anchorY ?? screen.visibleFrame.maxY) - size.height - Theme.Space.sm
        )
    }
}
