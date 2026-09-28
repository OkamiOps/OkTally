// Sources/OkTally/Plugins/MiMo/MiMoLog.swift
import Foundation
import os

/// Canal único do MiMo no unified logging. A sessão vive dentro de uma `WKWebView` — nada
/// do que dá errado nela aparece no console do Xcode nem em um `print`, então quando o dono
/// reclama de "desconecta toda hora" o `log stream --predicate 'subsystem == "com.oktally.app"'`
/// é a única prova de qual etapa falhou (fetch, 401, reload, espera, host).
///
/// Regra dura: nunca logar corpo de cookie, `passToken`, STS nem a resposta crua — só o
/// veredito (host, classificação, contagem). O log fica em disco e é legível por qualquer
/// processo da máquina.
enum MiMoLog {
    static let session = Logger(subsystem: "com.oktally.app", category: "mimo")
}
