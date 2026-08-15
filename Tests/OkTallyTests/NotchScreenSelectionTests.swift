// Tests/OkTallyTests/NotchScreenSelectionTests.swift
import XCTest
@testable import OkTally

/// Onde o painel vive. É aqui que moram as duas reclamações do dono: "plugo o monitor
/// externo e perco meu notch" (a tela certa é a que tem RECORTE, nunca a principal) e "de
/// tampa fechada o notch não aparece" (sem recorte o painel não some — ele vira ilha).
final class NotchScreenSelectionTests: XCTestCase {
    private func screen(_ id: Int, notch: Bool, primary: Bool = false) -> NotchScreenDescriptor {
        .init(id: id, hasNotch: notch, isPrimary: primary)
    }

    /// MacBook sozinho: a única tela, e ela tem notch.
    func test_onlyBuiltIn_hugsTheNotch() {
        let chosen = NotchScreenSelection.select(from: [screen(0, notch: true, primary: true)])
        XCTAssertEqual(chosen, .notch(screen(0, notch: true, primary: true)))
    }

    /// Tampa aberta + monitor externo: o painel continua no MacBook. O externo não tem
    /// recorte e não pode roubar o painel só por estar na lista.
    func test_builtInPlusExternal_staysOnBuiltIn() {
        let chosen = NotchScreenSelection.select(from: [
            screen(0, notch: true, primary: true),
            screen(1, notch: false)
        ])
        XCTAssertEqual(chosen, .notch(screen(0, notch: true, primary: true)))
    }

    /// O caso que quebrava: o macOS promove o monitor externo a tela PRINCIPAL (índice 0)
    /// e o pacote recriava a janela nele. "Principal" é ignorado de propósito enquanto
    /// houver recorte em algum lugar.
    func test_externalAsPrimary_stillHugsTheNotchedScreen() {
        let chosen = NotchScreenSelection.select(from: [
            screen(0, notch: false, primary: true),
            screen(1, notch: true)
        ])
        XCTAssertEqual(chosen, .notch(screen(1, notch: true)))
        XCTAssertEqual(chosen?.screen.isPrimary, false)
    }

    /// Clamshell com UM externo: a embutida some da lista e não sobra recorte nenhum. A
    /// resposta que o dono precisa não é "nada" — é a ilha, na tela que sobrou.
    func test_clamshellOneExternal_floatsOnIt() {
        let chosen = NotchScreenSelection.select(from: [screen(0, notch: false, primary: true)])
        XCTAssertEqual(chosen, .floating(screen(0, notch: false, primary: true)))
    }

    /// Clamshell com DOIS externos — a configuração real do dono. A ilha vai para a
    /// PRIMÁRIA, e não para a primeira da lista por acaso: é lá que a barra de menu está.
    func test_clamshellTwoExternals_floatsOnThePrimary() {
        let chosen = NotchScreenSelection.select(from: [
            screen(0, notch: false),
            screen(1, notch: false, primary: true)
        ])
        XCTAssertEqual(chosen, .floating(screen(1, notch: false, primary: true)))
    }

    /// Nenhuma tela marcada como primária (a lista pisca assim durante a reconfiguração):
    /// a ilha cai na primeira em vez de sumir. Ficar sem painel é pior do que ficar numa
    /// tela talvez errada por um instante — a próxima notificação corrige.
    func test_noPrimaryFlag_fallsBackToTheFirstScreen() {
        let chosen = NotchScreenSelection.select(from: [
            screen(0, notch: false),
            screen(1, notch: false)
        ])
        XCTAssertEqual(chosen, .floating(screen(0, notch: false)))
    }

    /// Lista vazia (a que o AppKit devolve por um instante durante a reconfiguração):
    /// nil, sem estourar índice. É o único caso que continua sem painel nenhum.
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
        XCTAssertEqual(chosen?.screen.id, 0)
    }
}
