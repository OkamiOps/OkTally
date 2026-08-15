// Tests/OkTallyTests/UsageColorScaleTests.swift
import XCTest
@testable import OkTally

/// A escala de cor é o que o dono lê no lugar do número. Se ela lavar no meio, ordenar
/// errado ou quebrar com um valor digitado torto, o app volta a ser "tudo azul" — que é
/// exatamente o defeito que ela existe para consertar.
final class UsageColorScaleTests: XCTestCase {

    private let cyan = UsageRGB(hex: 0x00B8F5)
    private let yellow = UsageRGB(hex: 0xFFCE3A)

    // MARK: - O caminho azul → amarelo

    /// O teste central: no MEIO da migração azul→amarelo a cor tem que continuar sendo
    /// uma cor. Interpolando em sRGB ali sai um cinza-esverdeado lavado — e é o meio da
    /// escala, o pior lugar possível para a cor parar de significar algo.
    func test_azulParaAmarelo_naoPassaPorCinza() {
        let hsbMid = UsageColorScale.mix(cyan, yellow, 0.5)
        let rgbMid = UsageRGB(red: (cyan.red + yellow.red) / 2,
                              green: (cyan.green + yellow.green) / 2,
                              blue: (cyan.blue + yellow.blue) / 2)

        XCTAssertGreaterThan(hsbMid.hsb.saturation, 0.7,
                             "o ponto médio azul→amarelo tem que continuar saturado")
        XCTAssertLessThan(rgbMid.hsb.saturation, 0.45,
                          "premissa do teste: em sRGB o mesmo ponto lava — se isto falhar, a justificativa do espaço HSB mudou")
        XCTAssertGreaterThan(hsbMid.hsb.saturation, rgbMid.hsb.saturation * 1.5)
    }

    /// Nenhum ponto da escala padrão é lavado — varredura de 0 a 100.
    func test_escalaPadrao_nuncaLava() {
        for percent in stride(from: 0.0, through: 100.0, by: 1.0) {
            let color = UsageColorScale.standard.color(atPercent: percent)
            XCTAssertGreaterThan(color.hsb.saturation, 0.5, "cor lavada em \(percent)%")
            XCTAssertGreaterThan(color.hsb.brightness, 0.5, "cor apagada em \(percent)%")
        }
    }

    // MARK: - Migração contínua

    /// A escala do dono, nos pontos que ele citou: 94% verde, 74% ainda do lado verde,
    /// 49% amarelo, 26% laranja, 8% vermelho. E, principalmente: nenhum par vizinho tem
    /// a MESMA cor — a migração é contínua, não são cinco faixas chapadas.
    func test_migracaoContinua_semFaixasChapadas() {
        let scale = UsageColorScale.standard
        var previous = scale.color(atPercent: 0)
        for percent in stride(from: 1.0, through: 100.0, by: 1.0) {
            let color = scale.color(atPercent: percent)
            if percent < 86 && percent > 7 {
                XCTAssertNotEqual(color, previous, "degrau chapado em \(percent)%")
            }
            previous = color
        }
    }

    /// 75% está ENTRE o verde e o azul (o dono: "em 75% já está migrando"), e não é
    /// nenhum dos dois.
    func test_setentaECinco_estaEntreVerdeEAzul() {
        let scale = UsageColorScale.standard
        let green = scale.color(atPercent: 85).hsb.hue
        let blue = scale.color(atPercent: 60).hsb.hue
        let hue = scale.color(atPercent: 75).hsb.hue
        XCTAssertTrue((min(green, blue)...max(green, blue)).contains(hue))
        XCTAssertNotEqual(scale.color(atPercent: 75), scale.color(atPercent: 85))
        XCTAssertNotEqual(scale.color(atPercent: 75), scale.color(atPercent: 60))
    }

    /// Fora das pontas a cor GRAMPEIA na parada extrema, em vez de extrapolar para um
    /// tom que ninguém escolheu.
    func test_forasDasPontas_grampeia() {
        let scale = UsageColorScale.standard
        XCTAssertEqual(scale.color(atPercent: 100), scale.color(atPercent: 92))
        XCTAssertEqual(scale.color(atPercent: 0), scale.color(atPercent: 3))
        XCTAssertEqual(scale.color(atPercent: -40), scale.color(atPercent: 0))
        XCTAssertEqual(scale.color(atPercent: 900), scale.color(atPercent: 100))
        XCTAssertEqual(scale.color(atRemaining: .nan), scale.color(atPercent: 0))
    }

    // MARK: - Normalização

    func test_normalizacao_ordenaEGrampeia() {
        let scale = UsageColorScale(stops: [
            UsageColorStop(percent: 130, hex: 0x00FF00),
            UsageColorStop(percent: -20, hex: 0xFF0000),
            UsageColorStop(percent: 50, hex: 0x0000FF)
        ])
        XCTAssertEqual(scale.stops.map(\.percent), [0, 50, 100])
        XCTAssertEqual(scale.stops.first?.color, UsageRGB(hex: 0xFF0000))
        XCTAssertEqual(scale.stops.last?.color, UsageRGB(hex: 0x00FF00))
    }

    /// Duas paradas no mesmo percentual não podem dividir por zero — o degrau ali é uma
    /// escolha legítima de quem as colocou juntas.
    func test_paradasCoincidentes_naoQuebram() {
        let scale = UsageColorScale(stops: [
            UsageColorStop(percent: 50, hex: 0xFF0000),
            UsageColorStop(percent: 50, hex: 0x00FF00)
        ])
        // No ponto exato vale a parada de BAIXO (a primeira que alcança o valor); acima
        // dele, a de cima. O que importa é não haver divisão por zero nem NaN.
        XCTAssertEqual(scale.color(atPercent: 50), UsageRGB(hex: 0xFF0000))
        XCTAssertEqual(scale.color(atPercent: 20), UsageRGB(hex: 0xFF0000))
        XCTAssertEqual(scale.color(atPercent: 80), UsageRGB(hex: 0x00FF00))
    }

    // MARK: - Edição

    func test_removerNaoDesceAbaixoDoMinimo() {
        var scale = UsageColorScale(stops: [
            UsageColorStop(percent: 10, hex: 0xFF0000),
            UsageColorStop(percent: 90, hex: 0x00FF00)
        ])
        let id = scale.stops[0].id
        scale = scale.removing(id: id)
        XCTAssertEqual(scale.stops.count, 2, "duas paradas é o piso: remover não pode zerar a escala")
    }

    func test_removerRetiraAParadaQuandoSobra() {
        let scale = UsageColorScale.standard
        let removed = scale.removing(id: scale.stops[2].id)
        XCTAssertEqual(removed.stops.count, scale.stops.count - 1)
        XCTAssertFalse(removed.stops.contains { $0.id == scale.stops[2].id })
    }

    /// Adicionar dá um ponto de controle novo sem RASGAR o degradê: a parada nova nasce
    /// exatamente com a cor que o ponto já tinha, e as paradas antigas ficam intactas.
    /// (Os dois trechos vizinhos são reamostrados — a suavização é por trecho — então o
    /// meio do caminho muda de tom; o que não pode mudar é a cor das paradas.)
    func test_adicionar_nasceComACorQueOPontoJaTinha() {
        let scale = UsageColorScale.standard
        let bigger = scale.addingStop()
        XCTAssertEqual(bigger.stops.count, scale.stops.count + 1)
        let novo = try? XCTUnwrap(bigger.stops.first { stop in !scale.stops.contains { $0.id == stop.id } })
        let parada = try? XCTUnwrap(novo)
        guard let parada else { return XCTFail("nenhuma parada nova") }
        XCTAssertEqual(parada.color.hexString, scale.color(atPercent: parada.percent).hexString)
        // Maior vão da escala padrão (60→85): a parada nasce no meio dele.
        XCTAssertEqual(parada.percent, 72.5, accuracy: 0.001)
        // Pelo hex: a ida-e-volta por HSB devolve diferenças de 1e-16 que não existem em
        // nenhum pixel desenhado.
        for old in scale.stops {
            XCTAssertEqual(bigger.color(atPercent: old.percent).hexString, old.color.hexString)
        }
    }

    func test_trocarPercentualReordena() {
        let scale = UsageColorScale.standard
        let moved = scale.replacingPercent(id: scale.stops[0].id, percent: 99)
        XCTAssertEqual(moved.stops.last?.id, scale.stops[0].id)
    }

    // MARK: - Persistência

    func test_codificacaoIdaEVolta() {
        let scale = UsageColorScale.standard
        let decoded = UsageColorScale(encoded: scale.encoded)
        XCTAssertEqual(decoded, scale)
        XCTAssertEqual(scale.encoded, "7:F5384A,23:FF9D00,40:FFCE3A,60:00B8F5,85:35D07F")
    }

    func test_decodificacaoRecusaLixo() {
        XCTAssertNil(UsageColorScale(encoded: nil))
        XCTAssertNil(UsageColorScale(encoded: ""))
        XCTAssertNil(UsageColorScale(encoded: "banana"))
        XCTAssertNil(UsageColorScale(encoded: "50:ZZZZZZ,80:FFFFFF"), "hex inválido derruba a parada e sobra uma só")
        XCTAssertNil(UsageColorScale(encoded: "50:FF0000"), "uma parada só não é escala")
        XCTAssertEqual(UsageColorScale(encoded: "50:FF0000,80:00FF00")?.stops.count, 2)
    }

    func test_percentualFracionarioSobreviveAoDisco() {
        let scale = UsageColorScale(stops: [
            UsageColorStop(percent: 12.5, hex: 0xFF0000),
            UsageColorStop(percent: 87.5, hex: 0x00FF00)
        ])
        XCTAssertEqual(UsageColorScale(encoded: scale.encoded)?.stops.map(\.percent), [12.5, 87.5])
    }

    func test_storeDevolveOPadraoQuandoODiscoEstaVazioOuPodre() {
        let raw = FakeKeyValueStore()
        let store = PreferencesStore(store: raw, secretStore: FakeSecretStore())
        XCTAssertEqual(store.usageColorScale, .standard)
        raw.set("nada disso", forKey: "usageColorScale")
        XCTAssertEqual(store.usageColorScale, .standard)

        let custom = UsageColorScale(stops: [
            UsageColorStop(percent: 20, hex: 0x112233),
            UsageColorStop(percent: 80, hex: 0x445566)
        ])
        store.usageColorScale = custom
        XCTAssertEqual(store.usageColorScale, custom)
    }

    // MARK: - Contraste

    /// O amarelo e o verde da escala são CLAROS: como fundo do herói (texto off-white em
    /// cima) e como número sobre a barra de menu clara eles precisam ser escurecidos, e o
    /// escurecimento não pode virar outra cor.
    func test_escurecimentoAtingeOContrasteSemTrocarOMatiz() {
        let lightBar = UsageRGB(red: 0.95, green: 0.95, blue: 0.95)
        for hex: UInt32 in [0xFFCE3A, 0x35D07F, 0x00B8F5, 0xFF9D00, 0xF5384A] {
            let base = UsageRGB(hex: hex)
            let fixed = base.darkened(againstBackground: lightBar, minRatio: 4.5)
            XCTAssertGreaterThanOrEqual(fixed.contrastRatio(with: lightBar), 4.4,
                                        "\(base.hexString) continua ilegível na barra clara")
            XCTAssertEqual(fixed.hsb.hue, base.hsb.hue, accuracy: 0.01, "o matiz mudou — deixou de ser a mesma cor")
        }
    }

    func test_fundoEscuroNaoEscurece() {
        let base = UsageRGB(hex: 0xFFCE3A)
        XCTAssertEqual(base.darkened(againstBackground: UsageRGB(hex: 0x0C0D0F)), base)
    }

    /// Conversões de ida e volta: é por elas que o `ColorPicker` do sistema vira uma
    /// parada gravável.
    func test_rgbHsbIdaEVolta() {
        for hex: UInt32 in [0x000000, 0xFFFFFF, 0x808080, 0xFFCE3A, 0x00B8F5, 0x35D07F, 0xF5384A] {
            let base = UsageRGB(hex: hex)
            let round = UsageRGB(hsb: base.hsb)
            XCTAssertEqual(round.red, base.red, accuracy: 0.005, "\(base.hexString)")
            XCTAssertEqual(round.green, base.green, accuracy: 0.005)
            XCTAssertEqual(round.blue, base.blue, accuracy: 0.005)
            XCTAssertEqual(UsageRGB(hexString: base.hexString), base)
        }
    }

    // MARK: - O ponto único do app

    /// `QuotaPresentation.color` é o ponto único: trocar a escala tem que trocar a cor
    /// que o app inteiro pinta.
    func test_pontoUnicoSegueOHolder() {
        defer { UsageColorScaleHolder.reset() }
        let flat = UsageColorScale(stops: [
            UsageColorStop(percent: 0, hex: 0xFF00FF),
            UsageColorStop(percent: 100, hex: 0xFF00FF)
        ])
        UsageColorScaleHolder.current = flat
        // Comparação pelo hex: a ida-e-volta por HSB devolve 0,9999999 no lugar de 1, e
        // o que precisa ser igual é a COR desenhada, não o `Double`.
        XCTAssertEqual(UsageColorScaleHolder.current.color(atRemaining: 0.42).hexString, "FF00FF")
        UsageColorScaleHolder.reset()
        XCTAssertEqual(UsageColorScaleHolder.current, .standard)
    }
}
