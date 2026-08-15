// Tests/OkTallyTests/NotchIslandGeometryTests.swift
import XCTest
@testable import OkTally

/// A conta de posição da ilha. É a única parte do painel que PNG nenhum revela — o
/// harness de imagem desenha o conteúdo, não a tela — e é exatamente onde moravam duas das
/// três reclamações do dono: "ficou no meio da tela e não na barra" e "quando ele expande
/// ele se move e depois volta".
final class NotchIslandGeometryTests: XCTestCase {
    /// Um DELL 2560×1440 com a origem em zero. `frame` (e não `visibleFrame`): a conta
    /// parte do topo VERDADEIRO da tela.
    private let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let pill = CGSize(width: 240, height: 34)
    private let hMargin: CGFloat = 16
    private let bMargin: CGFloat = 16

    private func frame(pill: CGSize, fraction: CGFloat, on screen: CGRect? = nil) -> CGRect {
        NotchIslandGeometry.windowFrame(
            screenFrame: screen ?? self.screen,
            pillSize: pill,
            horizontalMargin: hMargin,
            bottomMargin: bMargin,
            fraction: fraction
        )
    }

    // MARK: - O topo é o topo

    /// A reclamação nº 1. Sem fração salva a pílula nasce no centro, e a borda de CIMA da
    /// janela coincide com a borda de cima da tela — nem um ponto de vão.
    func test_padrao_nasceColadaNoTopoENoCentro() {
        let rect = frame(pill: pill, fraction: NotchIslandGeometry.centerFraction)
        XCTAssertEqual(rect.maxY, screen.maxY, accuracy: 0.001)
        XCTAssertEqual(rect.midX, screen.midX, accuracy: 0.001)
        XCTAssertEqual(rect.width, pill.width + hMargin * 2, accuracy: 0.001)
        XCTAssertEqual(rect.height, pill.height + bMargin, accuracy: 0.001)
    }

    /// Uma tela que não começa em zero (o segundo monitor, à direita do primeiro): a
    /// conta é relativa ao retângulo dela, não à origem global.
    func test_telaDeslocada_usaOTopoDelaMesma() {
        let second = CGRect(x: 2560, y: 200, width: 1920, height: 1080)
        let rect = frame(pill: pill, fraction: 0.5, on: second)
        XCTAssertEqual(rect.maxY, second.maxY, accuracy: 0.001)
        XCTAssertEqual(rect.midX, second.midX, accuracy: 0.001)
    }

    // MARK: - Expandir não move o topo

    /// A reclamação nº 2, em números: a pílula expandida é mais alta E mais larga, e
    /// mesmo assim a borda de cima e o centro horizontal não se mexem.
    func test_expandir_mantemTopoECentro() {
        let fechada = frame(pill: pill, fraction: 0.5)
        let aberta = frame(pill: CGSize(width: 360, height: 220), fraction: 0.5)
        XCTAssertEqual(aberta.maxY, fechada.maxY, accuracy: 0.001)
        XCTAssertEqual(aberta.midX, fechada.midX, accuracy: 0.001)
        XCTAssertGreaterThan(fechada.minY, aberta.minY, "a janela tem de crescer para BAIXO")
    }

    /// O mesmo com a pílula fora do centro: expandir a partir de uma posição arrastada
    /// também não pode reposicionar nada.
    func test_expandir_foraDoCentro_mantemTopoECentro() {
        let fechada = frame(pill: pill, fraction: 0.2)
        let aberta = frame(pill: CGSize(width: 360, height: 220), fraction: 0.2)
        XCTAssertEqual(aberta.maxY, fechada.maxY, accuracy: 0.001)
        XCTAssertEqual(aberta.midX, fechada.midX, accuracy: 0.001)
    }

    // MARK: - A fração salva

    /// Fração 0,2 põe o centro da pílula a 20% da largura.
    func test_fracaoSalva_posicionaOCentro() {
        let rect = frame(pill: pill, fraction: 0.2)
        XCTAssertEqual(rect.midX, 512, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, screen.maxY, accuracy: 0.001)
    }

    /// Fração 0 e 1 são as bordas, e a pílula tem de continuar INTEIRA na tela: o centro
    /// para a meia-largura dela de distância da borda.
    func test_fracaoNasBordas_aPilulaNaoVazaDaTela() {
        XCTAssertEqual(frame(pill: pill, fraction: 0).midX, screen.minX + pill.width / 2, accuracy: 0.001)
        XCTAssertEqual(frame(pill: pill, fraction: 1).midX, screen.maxX - pill.width / 2, accuracy: 0.001)
    }

    /// Fração fora da faixa (arquivo de preferências de outra versão, ou editado à mão)
    /// não pode jogar a pílula para fora do mundo.
    func test_fracaoInvalida_caiNaFaixa() {
        XCTAssertEqual(NotchIslandGeometry.clampFraction(-3), 0)
        XCTAssertEqual(NotchIslandGeometry.clampFraction(42), 1)
        XCTAssertEqual(NotchIslandGeometry.clampFraction(.nan), NotchIslandGeometry.centerFraction)
    }

    /// Trocar para uma tela MENOR que a posição salva pressupunha: a fração é relativa, e
    /// a contenção acaba de resolver o resto. Nada nasce fora da tela.
    func test_telaMenorQueASalva_continuaDentro() {
        let pequena = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let rect = frame(pill: pill, fraction: 0.98, on: pequena)
        XCTAssertLessThanOrEqual(rect.midX + pill.width / 2, pequena.maxX)
        XCTAssertGreaterThanOrEqual(rect.midX - pill.width / 2, pequena.minX)
        XCTAssertEqual(rect.maxY, pequena.maxY, accuracy: 0.001)
    }

    /// Caso degenerado: a pílula expandida é mais larga que a tela. Não existe posição que
    /// a contenha, então ela fica centralizada — sobra igual dos dois lados, em vez de
    /// tudo de um lado só.
    func test_pilulaMaisLargaQueATela_ficaCentralizada() {
        let estreita = CGRect(x: 0, y: 0, width: 300, height: 800)
        let rect = frame(pill: CGSize(width: 400, height: 220), fraction: 0.1, on: estreita)
        XCTAssertEqual(rect.midX, estreita.midX, accuracy: 0.001)
    }

    // MARK: - Arrasto: ponto → fração → ponto

    /// Soltar a pílula num ponto e reabrir o app tem de devolver a pílula ao mesmo ponto.
    func test_arrasto_idaEVolta_naoPerdePosicao() {
        let soltouEm: CGFloat = 700
        let fracao = NotchIslandGeometry.fraction(forCenterX: soltouEm, screenFrame: screen)
        let volta = NotchIslandGeometry.clampedCenterX(screenFrame: screen, pillWidth: pill.width, fraction: fracao)
        XCTAssertEqual(volta, soltouEm, accuracy: 0.001)
    }

    /// Arrastar para fora da tela (o cursor sai pela borda) satura em 0 e 1 em vez de
    /// guardar uma fração impossível.
    func test_arrastoParaForaDaTela_satura() {
        XCTAssertEqual(NotchIslandGeometry.fraction(forCenterX: -500, screenFrame: screen), 0)
        XCTAssertEqual(NotchIslandGeometry.fraction(forCenterX: 9000, screenFrame: screen), 1)
    }

    // MARK: - O ímã do centro

    /// Soltar perto do meio gruda no meio exato — acertar 1280,0 na mão é impossível.
    func test_snap_pertoDoCentro_viraCentroExato() {
        let quase = NotchIslandGeometry.fraction(forCenterX: screen.midX + 10, screenFrame: screen)
        XCTAssertEqual(NotchIslandGeometry.snappedFraction(quase, screenFrame: screen),
                       NotchIslandGeometry.centerFraction)
    }

    /// Longe do meio, o ímã não pode roubar a posição escolhida.
    func test_snap_longeDoCentro_respeitaAEscolha() {
        let longe = NotchIslandGeometry.fraction(forCenterX: screen.midX + 300, screenFrame: screen)
        XCTAssertEqual(NotchIslandGeometry.snappedFraction(longe, screenFrame: screen), longe, accuracy: 0.0001)
    }

    /// A tolerância é em PONTOS de tela, não em fração: a mesma distância em pixels vale a
    /// mesma coisa num monitor largo e num estreito.
    func test_snap_toleranciaEmPontos_naoEmFracao() {
        let estreita = CGRect(x: 0, y: 0, width: 800, height: 600)
        let deslocamento = NotchIslandGeometry.centerSnapTolerance + 5
        let larga = NotchIslandGeometry.fraction(forCenterX: screen.midX + deslocamento, screenFrame: screen)
        let curta = NotchIslandGeometry.fraction(forCenterX: estreita.midX + deslocamento, screenFrame: estreita)
        XCTAssertNotEqual(NotchIslandGeometry.snappedFraction(larga, screenFrame: screen),
                          NotchIslandGeometry.centerFraction)
        XCTAssertNotEqual(NotchIslandGeometry.snappedFraction(curta, screenFrame: estreita),
                          NotchIslandGeometry.centerFraction)
    }
}
