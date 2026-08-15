// Sources/OkTally/Core/AppResources.swift
import Foundation

/// Onde ficam os recursos do target (traduções, símbolo da barra de menu).
///
/// Por que isto existe em vez de `Bundle.module` direto: o acessor que o SwiftPM gera
/// procura o bundle em DOIS lugares só — `Bundle.main.bundleURL/OkTally_OkTally.bundle`
/// (a raiz do `.app`) e um caminho ABSOLUTO dentro do `.build` da máquina que compilou.
/// E a raiz do `.app` é justamente onde o `codesign` não aceita nada: assinar um app com
/// conteúdo solto fora de `Contents/` falha com "unsealed contents present in the bundle
/// root". Ou seja, os dois caminhos do acessor são inviáveis para um app assinado, e o
/// app só vinha funcionando porque caía no caminho absoluto do `.build` — o que significa
/// que copiar o `.app` para outra máquina, ou apagar o `.build`, o derrubava no primeiro
/// texto traduzido.
///
/// Aqui o bundle é procurado primeiro em `Contents/Resources`, que é o lugar canônico e
/// assinável (é para lá que o `Scripts/build_app.sh` copia). Os outros candidatos ficam
/// como rede: raiz do `.app` para builds que ainda sigam a convenção do SwiftPM, e
/// `Bundle.module` por último, para `swift test`/`swift run`, onde o caminho de `.build`
/// é real.
enum AppResources {
    static let bundle: Bundle = {
        let name = "OkTally_OkTally.bundle"
        let candidates = [Bundle.main.resourceURL, Bundle.main.bundleURL]
            .compactMap { $0?.appendingPathComponent(name) }
        for url in candidates {
            if let bundle = Bundle(url: url) { return bundle }
        }
        return .module
    }()
}
