// Sources/OkTally/UI/Notch/NotchLayoutGate.swift

/// Quem decide QUANDO a janela da ilha pode ser mexida — e nada além disso.
///
/// ## O acidente que este tipo existe para impedir
///
/// O AppKit roda o passe de constraints de uma janela dentro do display cycle
/// (`NSDisplayCycleObserverInvoke` → `-[NSWindow updateConstraintsIfNeeded]` →
/// `-[NSHostingView updateConstraints]`). Mexer no frame da JANELA lá de dentro faz o
/// `NSHostingView` descobrir que a transformada dele envelheceu, pedir outra atualização
/// (`requestUpdate` → `setNeedsUpdateConstraints:`) e a janela ser remarcada como
/// precisando de um passe **enquanto ainda está no passe**. O AppKit não perdoa isso:
/// `-[NSWindow _postWindowNeedsUpdateConstraints]` levanta uma `NSException`, e num app
/// de barra de menu ela chega em `+[NSApplication _crashOnException:]` e mata o processo
/// inteiro por causa de um painel decorativo. Foi o crash de 2026-08-15.
///
/// A regra que fecha o buraco é simples de dizer e fácil de furar sem querer: **nenhum
/// callback do SwiftUI mexe na janela na hora; todo mundo agenda para o próximo giro do
/// runloop.** Este tipo é essa regra em forma de máquina de estados — sem `AppKit`, sem
/// `@MainActor`, sem janela nenhuma — para que ela possa ser testada de verdade em vez de
/// ser conferida no olho a cada build.
///
/// Ele também COALESCE: hover, arrasto e o remedir de 50ms disparam vários pedidos por
/// quadro, e todos têm de virar um único `setFrame`. Um pedido animado dentro da mesma
/// leva ganha — só o ímã do centro anima, e perder essa animação seria perder o único
/// feedback de que a pílula grudou no meio.
struct NotchLayoutGate {
    /// Verdadeiro enquanto o layout está sendo APLICADO. Um pedido que chegue agora não
    /// pode virar recursão: ele fica pendurado e sai no giro seguinte.
    private(set) var isApplying = false
    /// Verdadeiro quando já existe um giro de runloop agendado. É o que impede N pedidos
    /// no mesmo quadro de virarem N `setFrame`.
    private(set) var isScheduled = false

    private var hasPending = false
    private var pendingAnimated = false

    /// Alguém quer layout.
    /// - Returns: `true` se o chamador precisa AGENDAR um giro de runloop; `false` quando
    ///   um giro já está a caminho (ou vai ser reagendado por `end()`).
    mutating func request(animated: Bool = false) -> Bool {
        hasPending = true
        pendingAnimated = pendingAnimated || animated
        guard !isScheduled, !isApplying else { return false }
        isScheduled = true
        return true
    }

    /// O giro chegou.
    /// - Returns: o `animated` a usar, ou `nil` quando não há nada a aplicar (o pedido já
    ///   foi atendido, ou a ilha fechou no meio do caminho).
    mutating func begin() -> Bool? {
        isScheduled = false
        guard hasPending, !isApplying else { return nil }
        hasPending = false
        isApplying = true
        let animated = pendingAnimated
        pendingAnimated = false
        return animated
    }

    /// Terminou de aplicar.
    /// - Returns: `true` se um pedido novo chegou DURANTE a aplicação e é preciso agendar
    ///   outro giro. (Chegar um pedido aí é normal: aplicar o layout mexe no conteúdo, e
    ///   o conteúdo às vezes pede outro tamanho.)
    mutating func end() -> Bool {
        isApplying = false
        guard hasPending, !isScheduled else { return false }
        isScheduled = true
        return true
    }

    /// A ilha fechou: nada do que foi pedido antes vale mais.
    mutating func reset() {
        self = NotchLayoutGate()
    }
}
