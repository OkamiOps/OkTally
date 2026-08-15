// Tests/OkTallyTests/NotchScreenSelectionTests.swift
import XCTest
@testable import OkTally

/// A escolha da tela do painel do notch. É onde mora o bug do "plugo o monitor externo e
/// perco meu notch": a tela certa é a que tem RECORTE, nunca a principal.
final class NotchScreenSelectionTests: XCTestCase {
    private func screen(_ id: Int, notch: Bool, primary: Bool = false) -> NotchScreenDescriptor {
        .init(id: id, hasNotch: notch, isPrimary: primary)
    }

    /// MacBook sozinho: a única tela, e ela tem notch.
    func test_onlyBuiltIn_isChosen() {
        let chosen = NotchScreenSelection.select(from: [screen(0, notch: true, primary: true)])
        XCTAssertEqual(chosen?.id, 0)
    }

    /// Tampa aberta + monitor externo: o painel continua no MacBook. O externo não tem
    /// recorte e não pode roubar o painel só por estar na lista.
    func test_builtInPlusExternal_staysOnBuiltIn() {
        let chosen = NotchScreenSelection.select(from: [
            screen(0, notch: true, primary: true),
            screen(1, notch: false)
        ])
        XCTAssertEqual(chosen?.id, 0)
    }

    /// O caso que quebrava: o macOS promove o monitor externo a tela PRINCIPAL (índice 0)
    /// e o pacote recriava a janela nele. A escolha ignora "principal" de propósito.
    func test_externalAsPrimary_stillPicksTheNotchedScreen() {
        let chosen = NotchScreenSelection.select(from: [
            screen(0, notch: false, primary: true),
            screen(1, notch: true)
        ])
        XCTAssertEqual(chosen?.id, 1)
        XCTAssertEqual(chosen?.isPrimary, false)
    }

    /// Clamshell: tampa fechada, a embutida some da lista. Sem tela com notch não há
    /// painel — e isso é uma resposta legítima, não um erro.
    func test_onlyExternal_choosesNothing() {
        XCTAssertNil(NotchScreenSelection.select(from: [screen(0, notch: false, primary: true)]))
    }

    /// Lista vazia (a que o AppKit devolve por um instante durante a reconfiguração):
    /// nil, sem estourar índice.
    func test_noScreens_choosesNothing() {
        XCTAssertNil(NotchScreenSelection.select(from: []))
    }

    /// Duas telas com recorte não existem no hardware da Apple, mas a lista pode piscar
    /// duplicada durante uma reconfiguração. A escolha tem de ser determinística: a
    /// primeira. Um critério instável faria o painel pular de tela sozinho.
    func test_twoNotchedScreens_picksTheFirst_deterministically() {
        let chosen = NotchScreenSelection.select(from: [
            screen(0, notch: true),
            screen(1, notch: true, primary: true)
        ])
        XCTAssertEqual(chosen?.id, 0)
    }
}
