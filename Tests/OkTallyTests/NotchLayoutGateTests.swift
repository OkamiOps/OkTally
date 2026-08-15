// Tests/OkTallyTests/NotchLayoutGateTests.swift
import XCTest
@testable import OkTally

/// O contrato que impede o crash de 2026-08-15: **nenhum layout de janela acontece de
/// dentro de outro**, e vários pedidos no mesmo quadro viram um único `setFrame`.
///
/// O crash em si não é reproduzível aqui — ele depende do AppKit estar no meio do próprio
/// display cycle, com o contador interno de repetições do passe de constraints estourando
/// (duas tentativas de harness sintético, uma forçando `updateConstraintsIfNeeded()` e
/// outra mexendo na janela de dentro de um `updateConstraints` sobrescrito, sobreviveram
/// alegremente). O que É testável, e é onde mora a correção, é a máquina de estados que
/// decide quando o `setFrame` pode acontecer.
final class NotchLayoutGateTests: XCTestCase {
    // MARK: - Coalescência

    /// Um pedido em repouso agenda um giro de runloop.
    func test_pedidoEmRepouso_agendaUmGiro() {
        var gate = NotchLayoutGate()
        XCTAssertTrue(gate.request())
        XCTAssertTrue(gate.isScheduled)
    }

    /// O caso do arrasto: dezenas de pedidos no mesmo quadro têm de virar UM `setFrame`.
    /// Se cada um agendasse o seu, a pílula andaria em degraus e o AppKit veria uma
    /// enxurrada de mudanças de frame por quadro.
    func test_muitosPedidosNoMesmoQuadro_agendamUmGiroSo() {
        var gate = NotchLayoutGate()
        var giros = 0
        for _ in 0 ..< 30 where gate.request() { giros += 1 }
        XCTAssertEqual(giros, 1)
    }

    /// E os 30 pedidos são atendidos por uma aplicação só.
    func test_muitosPedidos_umaAplicacaoSo() {
        var gate = NotchLayoutGate()
        for _ in 0 ..< 30 { _ = gate.request() }
        XCTAssertNotNil(gate.begin())
        XCTAssertFalse(gate.end())
        XCTAssertNil(gate.begin())
    }

    // MARK: - Animação

    /// Só o ímã do centro anima. Coalescer um pedido animado com um comum não pode comer
    /// a animação: sem ela o dono não vê que a pílula grudou no meio.
    func test_animadoGanhaNaMesmaLeva() {
        var gate = NotchLayoutGate()
        _ = gate.request(animated: false)
        _ = gate.request(animated: true)
        _ = gate.request(animated: false)
        XCTAssertEqual(gate.begin(), true)
    }

    /// E o "animado" não vaza para o giro seguinte: o arrasto que vier depois do ímã é
    /// instantâneo de novo.
    func test_animadoNaoVazaParaOProximoGiro() {
        var gate = NotchLayoutGate()
        _ = gate.request(animated: true)
        XCTAssertEqual(gate.begin(), true)
        _ = gate.end()
        _ = gate.request(animated: false)
        XCTAssertEqual(gate.begin(), false)
    }

    // MARK: - Reentrância (o crash)

    /// O coração da correção: um pedido que chegue DURANTE a aplicação não abre um
    /// segundo layout por dentro do primeiro. Ele espera.
    func test_pedidoDuranteAAplicacao_naoReentra() {
        var gate = NotchLayoutGate()
        _ = gate.request()
        XCTAssertNotNil(gate.begin())
        XCTAssertTrue(gate.isApplying)

        // Isto é o SwiftUI reagindo à janela que acabou de mexer, ainda dentro do passe.
        XCTAssertFalse(gate.request(), "um pedido durante a aplicação não pode agendar por si")
        XCTAssertNil(gate.begin(), "e muito menos começar um layout aninhado")
    }

    /// Mas ele também não pode ser PERDIDO: o `end()` é quem manda reagendar.
    func test_pedidoDuranteAAplicacao_saiNoGiroSeguinte() {
        var gate = NotchLayoutGate()
        _ = gate.request()
        _ = gate.begin()
        _ = gate.request(animated: true)
        XCTAssertTrue(gate.end(), "o pedido represado tem de pedir um novo giro")
        XCTAssertEqual(gate.begin(), true, "e chegar com a animação que pediu")
    }

    /// Sem pedido novo, `end()` não fica reagendando à toa — senão a ilha giraria o
    /// runloop para sempre sem nada para fazer.
    func test_fimSemPedidoNovo_naoReagenda() {
        var gate = NotchLayoutGate()
        _ = gate.request()
        _ = gate.begin()
        XCTAssertFalse(gate.end())
        XCTAssertFalse(gate.isScheduled)
    }

    /// Giro órfão (o pedido já foi atendido por um giro anterior): não faz nada.
    func test_giroSemPedido_naoAplica() {
        var gate = NotchLayoutGate()
        XCTAssertNil(gate.begin())
        XCTAssertFalse(gate.isApplying)
    }

    /// Um ciclo completo não deixa estado preso — o próximo hover encontra a porteira
    /// como a encontrou da primeira vez.
    func test_cicloCompleto_naoDeixaEstadoPreso() {
        var gate = NotchLayoutGate()
        _ = gate.request()
        _ = gate.begin()
        _ = gate.end()
        XCTAssertFalse(gate.isApplying)
        XCTAssertFalse(gate.isScheduled)
        XCTAssertTrue(gate.request(), "a porteira volta a aceitar agendamento")
    }

    // MARK: - Fechar

    /// A ilha fechou (trocou de tela, preferência desligada) com pedido pendente: nada do
    /// que foi pedido antes vale, e nenhum giro pendurado pode aplicar layout numa janela
    /// que não existe mais.
    func test_reset_descartaPedidoPendente() {
        var gate = NotchLayoutGate()
        _ = gate.request(animated: true)
        gate.reset()
        XCTAssertFalse(gate.isScheduled)
        XCTAssertNil(gate.begin())
    }

    /// Reset no meio de uma aplicação também limpa o `isApplying` — senão a porteira
    /// ficaria fechada para sempre e a ilha nunca mais se posicionaria.
    func test_reset_duranteAAplicacao_naoTravaAPorteira() {
        var gate = NotchLayoutGate()
        _ = gate.request()
        _ = gate.begin()
        gate.reset()
        XCTAssertFalse(gate.isApplying)
        XCTAssertTrue(gate.request())
    }
}
