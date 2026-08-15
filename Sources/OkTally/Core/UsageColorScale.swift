// Sources/OkTally/Core/UsageColorScale.swift
import Foundation

/// Uma cor sRGB fora do SwiftUI. O cálculo da escala é lógica pura — precisa rodar na
/// suíte sem `Color`, que não deixa ler os componentes de volta sem passar pelo AppKit.
struct UsageRGB: Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = UsageRGB.clamp(red)
        self.green = UsageRGB.clamp(green)
        self.blue = UsageRGB.clamp(blue)
    }

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// `nil` para qualquer coisa que não sejam 6 dígitos hexadecimais — a persistência
    /// não pode confiar no que está em disco (o dono pode editar o `defaults` na mão).
    init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(hex: value)
    }

    var hexString: String {
        String(format: "%02X%02X%02X",
               Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    private static func clamp(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(1, max(0, v))
    }
}

// MARK: - HSB

/// Matiz (0…1, dando a volta), saturação e brilho. É o espaço em que a escala interpola —
/// ver `UsageColorScale.mix`.
struct UsageHSB: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double
}

extension UsageRGB {
    var hsb: UsageHSB {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let delta = maxC - minC
        var hue: Double = 0
        if delta > 0 {
            if maxC == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return UsageHSB(hue: hue,
                        saturation: maxC == 0 ? 0 : delta / maxC,
                        brightness: maxC)
    }

    init(hsb: UsageHSB) {
        let h = (hsb.hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let s = min(1, max(0, hsb.saturation))
        let v = min(1, max(0, hsb.brightness))
        let c = v * s
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double)
        switch Int(h) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        self.init(red: r + m, green: g + m, blue: b + m)
    }

    /// A mesma cor com o brilho multiplicado. Matiz e saturação intactos — é assim que um
    /// tom fica legível sem virar outra cor.
    func scalingBrightness(_ factor: Double) -> UsageRGB {
        var components = hsb
        components.brightness *= factor
        return UsageRGB(hsb: components)
    }
}

// MARK: - Contraste

extension UsageRGB {
    /// Luminância relativa da WCAG.
    var relativeLuminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    func contrastRatio(with other: UsageRGB) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Escurece (só o brilho) até a luminância cair para `target`, no máximo.
    ///
    /// Existe porque a escala tem tons CLAROS (o amarelo e o verde) que o app precisa
    /// desenhar em dois contextos onde claro é problema: como FUNDO do card-herói, com
    /// texto off-white em cima, e como número sobre a barra de menu clara. Escurecer o
    /// tom preserva a informação (o matiz continua sendo "amarelo"), enquanto trocar a
    /// tinta do texto ou dessaturar destruiria justamente o que a escala codifica.
    func darkened(toLuminanceAtMost target: Double) -> UsageRGB {
        guard relativeLuminance > target, target > 0 else { return self }
        // Busca binária no fator de brilho: a relação brilho→luminância não é linear
        // (gama 2.4) e uma fórmula fechada erraria para cores de matiz saturado.
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            let candidate = scalingBrightness(mid)
            if candidate.relativeLuminance > target { high = mid } else { low = mid }
        }
        return scalingBrightness(low)
    }
    /// Escurece até ter pelo menos `minRatio` de contraste contra um fundo CLARO.
    /// Sobre fundo escuro devolve a cor intacta — lá o problema não existe.
    func darkened(againstBackground background: UsageRGB, minRatio: Double = 4.5) -> UsageRGB {
        let backgroundLuminance = background.relativeLuminance
        guard backgroundLuminance > relativeLuminance else { return self }
        let target = (backgroundLuminance + 0.05) / minRatio - 0.05
        return darkened(toLuminanceAtMost: target)
    }
}

// MARK: - Escala

/// Uma parada da escala: "neste percentual RESTANTE a cor é exatamente esta".
///
/// Entre duas paradas a cor é interpolada — o degradê contínuo que o dono pediu ("uma
/// migração de cor... nada muito brusco"). O percentual é o que RESTA, não o usado: é o
/// número que o app inteiro imprime.
struct UsageColorStop: Identifiable, Equatable {
    /// Identidade estável para o `ForEach` da tela de Preferências. Fora da igualdade de
    /// propósito: duas escalas com as mesmas paradas são a mesma escala, e a suíte
    /// compara valores, não instâncias.
    let id: UUID
    var percent: Double
    var color: UsageRGB

    init(id: UUID = UUID(), percent: Double, color: UsageRGB) {
        self.id = id
        self.percent = percent
        self.color = color
    }

    init(id: UUID = UUID(), percent: Double, hex: UInt32) {
        self.init(id: id, percent: percent, color: UsageRGB(hex: hex))
    }

    static func == (lhs: UsageColorStop, rhs: UsageColorStop) -> Bool {
        lhs.percent == rhs.percent && lhs.color == rhs.color
    }
}

/// A escala de cor do uso: a cor É a informação.
///
/// ## Por que um degradê e não cinco faixas
///
/// O app pintava tudo de ciano com folga e só trocava de cor em dois degraus (30% e 10%).
/// Como quase toda cota está folgada quase sempre, a tela era monocromática e o dono —
/// que é visual e tem TDAH — não extraía estado nenhum de relance: "está tudo sempre azul
/// nos usage". A escala resolve isso fazendo a cor variar CONTINUAMENTE com o valor: 94%
/// é verde, 74% é um verde-ciano, 55% já está virando amarelo, 26% é laranja. Não existe
/// mais um platô de cor onde valores diferentes se parecem.
///
/// ## Por que HSB com o menor arco de matiz
///
/// Interpolar em sRGB entre o azul e o amarelo passa por um cinza-esverdeado lavado (a
/// média dos dois canais opostos), e é exatamente o meio da escala — o pior lugar
/// possível para a cor deixar de significar algo. O mesmo vale para Oklab: azul e amarelo
/// ficam em lados opostos do eixo `b`, então a mistura cruza o eixo neutro com croma
/// perto de zero.
///
/// Interpolando em HSB pelo MENOR arco de matiz a mistura nunca entra no centro do
/// círculo: azul (195°) → amarelo (46°) desce pelo verde, com saturação alta o caminho
/// todo. `UsageColorScaleTests` mede isso — a saturação no ponto médio azul→amarelo fica
/// acima de 0,7 em HSB e abaixo de 0,4 em sRGB.
///
/// ## Por que a travessia é suavizada (e não linear)
///
/// O preço do arco é que azul→amarelo são 149° de matiz, e uma rampa LINEAR passa a maior
/// parte do percurso no verde: no primeiro corte, 47% restante — que pela escala do dono
/// é amarelo — saía verde, ou seja, a cor dizia "tranquilo" bem no meio da escala. Verde
/// ali não é só feio, é informação errada.
///
/// A travessia usa `smootherstep`: cada parada SEGURA a sua cor perto do próprio ponto e
/// a migração acontece no meio do caminho entre duas paradas. Continua contínua (nenhum
/// degrau, que é o que o dono recusou), mas o trecho ambíguo fica onde ele deve ficar —
/// na fronteira entre duas faixas, não dentro de uma delas.
struct UsageColorScale: Equatable {
    /// Paradas em ordem CRESCENTE de percentual restante. `normalized` garante a ordem;
    /// nada mais no tipo depende de o chamador ter ordenado.
    private(set) var stops: [UsageColorStop]

    init(stops: [UsageColorStop]) {
        self.stops = UsageColorScale.normalized(stops)
    }

    /// A escala ditada pelo dono: 100–71 verde, 70–51 azul, 50–31 amarelo, 30–16 laranja,
    /// 15–0 vermelho.
    ///
    /// As paradas ficam perto do CENTRO de cada faixa, não nas fronteiras, e é isso que
    /// produz o comportamento que ele descreveu: em 75% a cor já está migrando de verde
    /// para azul (85 → 60), em 55% de azul para amarelo (60 → 40). Fronteiras como
    /// paradas dariam faixas chapadas com o degradê espremido nas bordas — o oposto do
    /// pedido.
    ///
    /// Os tons saem da paleta escura do app: o azul é o Volt Cyan da marca, o laranja é o
    /// Heat Orange, e verde/amarelo/vermelho são vivos mas com brilho abaixo do neon puro,
    /// para não vibrarem contra a base quase preta.
    static let standard = UsageColorScale(stops: [
        UsageColorStop(percent: 7, hex: 0xF5384A),   // vermelho
        UsageColorStop(percent: 23, hex: 0xFF9D00),  // Heat Orange (marca)
        UsageColorStop(percent: 40, hex: 0xFFCE3A),  // amarelo
        UsageColorStop(percent: 60, hex: 0x00B8F5),  // Volt Cyan (marca)
        UsageColorStop(percent: 85, hex: 0x35D07F)   // verde
    ])

    /// Ordena e grampeia. Percentual fora de 0–100 vira 0 ou 100 e paradas fora de ordem
    /// são reordenadas: nada do que o dono digitar pode quebrar o lookup.
    static func normalized(_ stops: [UsageColorStop]) -> [UsageColorStop] {
        stops
            .map { stop in
                var fixed = stop
                fixed.percent = stop.percent.isFinite ? min(100, max(0, stop.percent)) : 0
                return fixed
            }
            .enumerated()
            // Ordenação estável: duas paradas no mesmo percentual mantêm a ordem em que
            // foram digitadas, senão o `ForEach` da tela embaralharia sozinho enquanto o
            // dono digita "5" antes de terminar de digitar "50".
            .sorted { $0.element.percent == $1.element.percent ? $0.offset < $1.offset : $0.element.percent < $1.element.percent }
            .map(\.element)
    }

    /// A cor no percentual restante pedido (0–100).
    func color(atPercent percent: Double) -> UsageRGB {
        guard let first = stops.first, let last = stops.last else { return UsageRGB(hex: 0x00B8F5) }
        let p = percent.isFinite ? min(100, max(0, percent)) : 0
        if p <= first.percent { return first.color }
        if p >= last.percent { return last.color }
        for index in 1..<stops.count {
            let lower = stops[index - 1], upper = stops[index]
            guard p <= upper.percent else { continue }
            let span = upper.percent - lower.percent
            // Duas paradas no mesmo ponto: o degrau é o que o dono pediu explicitamente
            // ao colocá-las juntas, e dividir por zero aqui pintaria NaN.
            guard span > 0 else { return upper.color }
            return UsageColorScale.mix(lower.color, upper.color, (p - lower.percent) / span)
        }
        return last.color
    }

    /// Mesma coisa a partir da fração 0…1 que o app carrega.
    func color(atRemaining fraction: Double) -> UsageRGB {
        color(atPercent: (fraction.isFinite ? fraction : 0) * 100)
    }

    /// Mistura em HSB pelo menor arco de matiz. Ver a nota do tipo.
    static func mix(_ a: UsageRGB, _ b: UsageRGB, _ t: Double) -> UsageRGB {
        let x = a.hsb, y = b.hsb
        // Cinza não tem matiz: pegar o zero que a conversão devolve arrastaria a mistura
        // para o vermelho. Quem tem cor manda no matiz dos dois.
        let hueA = x.saturation < 0.02 ? y.hue : x.hue
        let hueB = y.saturation < 0.02 ? x.hue : y.hue
        var delta = hueB - hueA
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        let clamped = eased(min(1, max(0, t)), hueArc: abs(delta))
        return UsageRGB(hsb: UsageHSB(
            hue: hueA + delta * clamped,
            saturation: x.saturation + (y.saturation - x.saturation) * clamped,
            brightness: x.brightness + (y.brightness - x.brightness) * clamped
        ))
    }

    /// A travessia, com a suavização proporcional ao ARCO DE MATIZ do trecho.
    ///
    /// Trecho curto (verde→azul são 46°) atravessa quase linear: em 74% a cor é o
    /// azul-esverdeado do meio do caminho, que é exatamente a migração pedida. Trecho
    /// longo (azul→amarelo são 149°) atravessa mais rápido, porque numa rampa linear ele
    /// passaria a MAIOR PARTE do percurso no verde — e verde em 47% restante diz
    /// "tranquilo" no meio da escala, que é informação errada.
    ///
    /// Sobra um ponto irredutível: por volta de 50% a cor cruza o verde. Ir do azul ao
    /// amarelo sem passar pelo verde só é possível passando pelo centro do círculo, ou
    /// seja, pelo cinza — o "cinza lamacento" que esta escala existe para evitar. Entre
    /// as duas, o verde de passagem é a escolha, espremido na fronteira 50/51 que separa
    /// as duas faixas.
    private static func eased(_ t: Double, hueArc: Double) -> Double {
        // Um passo de suavização a cada 90° de arco, até três.
        let passes = 1 + min(2, Int(hueArc / 0.25))
        var value = t
        for _ in 0..<passes { value = smootherstep(value) }
        return value
    }

    // MARK: - Edição

    /// Mínimo de paradas para a escala continuar sendo uma escala. Com uma só não há
    /// nada para interpolar — a tela pararia de codificar informação em cor.
    static let minimumStops = 2

    func replacingPercent(id: UUID, percent: Double) -> UsageColorScale {
        UsageColorScale(stops: stops.map { $0.id == id ? UsageColorStop(id: $0.id, percent: percent, color: $0.color) : $0 })
    }

    func replacingColor(id: UUID, color: UsageRGB) -> UsageColorScale {
        UsageColorScale(stops: stops.map { $0.id == id ? UsageColorStop(id: $0.id, percent: $0.percent, color: color) : $0 })
    }

    /// Remove a parada, a menos que isso deixe a escala abaixo do mínimo — aí devolve a
    /// escala intacta (a tela também desabilita o botão, mas a regra mora aqui, onde é
    /// testável).
    func removing(id: UUID) -> UsageColorScale {
        guard stops.count > UsageColorScale.minimumStops, stops.contains(where: { $0.id == id }) else { return self }
        return UsageColorScale(stops: stops.filter { $0.id != id })
    }

    /// Insere uma parada no MAIOR vão, com a cor que o degradê já tem naquele ponto.
    ///
    /// Ou seja: adicionar não RASGA o degradê — a cor naquele ponto continua a mesma, e
    /// o dono ganha um ponto de controle onde faltava. Uma parada nova em preto (ou com
    /// cor arbitrária no meio da escala) obrigaria a consertar o estrago antes de fazer o
    /// ajuste que se queria.
    ///
    /// Os dois trechos vizinhos são reamostrados (a suavização de `eased` é POR trecho,
    /// então dois trechos curtos não desenham exatamente a mesma curva que um longo). A
    /// diferença é de tom no meio do caminho, nunca de cor nas paradas.
    func addingStop() -> UsageColorScale {
        guard stops.count >= 2 else {
            return UsageColorScale(stops: stops + [UsageColorStop(percent: 50, color: color(atPercent: 50))])
        }
        var widestIndex = 1
        var widest = -1.0
        for index in 1..<stops.count {
            let span = stops[index].percent - stops[index - 1].percent
            if span > widest { widest = span; widestIndex = index }
        }
        let midpoint = (stops[widestIndex].percent + stops[widestIndex - 1].percent) / 2
        return UsageColorScale(stops: stops + [UsageColorStop(percent: midpoint, color: color(atPercent: midpoint))])
    }

    /// `t³(6t² − 15t + 10)` — a curva em S com derivada zero nas duas pontas. Ver a nota
    /// do tipo: é ela que mantém cada faixa reconhecível sem criar degrau.
    static func smootherstep(_ t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }

    // MARK: - Persistência

    /// `"7:F5384A,23:FF9D00,…"` — percentual e hex por parada, na ordem normalizada.
    /// Formato estável e legível: o dono pode conferir (e consertar) com `defaults read`.
    var encoded: String {
        stops.map { "\(Self.formatted($0.percent)):\($0.color.hexString)" }.joined(separator: ",")
    }

    /// `nil` quando não há nada gravado ou o que está lá não dá pelo menos DUAS paradas
    /// válidas — uma escala com menos que isso não interpola nada, e o padrão é uma
    /// resposta melhor do que uma cor chapada.
    init?(encoded: String?) {
        guard let encoded, !encoded.isEmpty else { return nil }
        let parsed: [UsageColorStop] = encoded.split(separator: ",").compactMap { piece in
            let parts = piece.split(separator: ":")
            guard parts.count == 2,
                  let percent = Double(parts[0]), percent.isFinite,
                  let color = UsageRGB(hexString: String(parts[1]))
            else { return nil }
            return UsageColorStop(percent: percent, color: color)
        }
        guard parsed.count >= 2 else { return nil }
        self.init(stops: parsed)
    }

    private static func formatted(_ percent: Double) -> String {
        percent == percent.rounded() ? String(Int(percent)) : String(format: "%.2f", percent)
    }
}

// MARK: - Injeção

/// Onde a escala corrente mora para quem não tem acesso ao `AppModel`.
///
/// `QuotaPresentation` é um enum estático consultado de dentro de dezenas de views, do
/// `ImageRenderer` da barra de menu e do painel do notch — passar a escala por parâmetro
/// significaria reescrever a assinatura de tudo que pinta um percentual. A escala é uma
/// preferência global e de leitura constante, então ela vive num holder global.
///
/// Quem ESCREVE é um só: `AppModel.usageColorScale` (carregado do `PreferencesStore` no
/// início e regravado quando a tela de Preferências edita). Como `AppModel` é
/// `@Published`, a edição ao vivo já repinta toda view que observa o modelo; o holder só
/// existe para o lookup, nunca como fonte de verdade.
///
/// O harness de render usa o mesmo caminho: `reset()` devolve o padrão entre testes, para
/// uma suíte não contaminar a outra.
enum UsageColorScaleHolder {
    static var current: UsageColorScale = .standard

    static func reset() { current = .standard }
}
