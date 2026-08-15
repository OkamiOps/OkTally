// Sources/OkTally/UI/ProviderPaneScaffold.swift
import SwiftUI

/// Estado do provider, exibido como pill em vez do ponto minúsculo de antes.
enum ProviderPaneStatus {
    case connected(String)
    case needsAttention(String)
    case notConfigured(String)

    var text: String {
        switch self {
        case .connected(let t), .needsAttention(let t), .notConfigured(let t): return t
        }
    }

    /// Só o PONTO da cápsula usa esta cor sobre o gradiente — ver `HeroStatusPill`.
    var tint: Color {
        switch self {
        case .connected: return Color(hex: 0x35D07F)
        case .needsAttention: return Theme.Brand.heatOrange
        case .notConfigured: return Color(white: 0.72)
        }
    }
}

/// Casca comum dos dez painéis de provider.
///
/// Antes: `Form` agrupado com TRÊS seções visualmente idênticas — cabeçalho, "Conexão" e
/// detalhes —, o cabeçalho sendo apenas mais um card cinza com um quadrado de cor a 16%.
/// Nada dominava, nada dizia de qual provedor era a tela senão o texto.
///
/// Agora o cabeçalho sai do `Form` e vira faixa de destaque na COR DE IDENTIDADE do
/// provedor, sangrando no topo do painel: abrir o painel do Claude pinta a tela de
/// terracota, o do Codex de verde-azulado. O `Form` agrupado continua abaixo com as
/// seções de conexão e detalhe — o idioma nativo de Ajustes não muda, ele passa a ter um
/// topo.
struct ProviderPaneScaffold<Connection: View, Details: View>: View {
    let providerId: String
    /// Cota atual, quando existe. É o que transforma o cabeçalho num bloco com CONTEÚDO
    /// em vez de um retângulo colorido com um nome: a tela de Preferências passa a
    /// responder "e como está esta conta agora?" sem obrigar a ir para a Visão geral.
    var snapshot: ProviderSnapshot?
    /// Mensagem do último erro deste provedor, quando existe. Ela só aparecia no popover;
    /// aqui, na tela onde se RESOLVE o problema, o usuário via apenas um ponto laranja na
    /// sidebar e nenhuma explicação do que fazer.
    var problem: String?
    let name: String
    let status: ProviderPaneStatus
    @ViewBuilder var connection: Connection
    @ViewBuilder var details: Details

    private var identity: Color { ProviderPalette.color(for: providerId) }

    /// A janela mais apertada do provedor — a mesma regra de "herói" do resto do app.
    private var tightest: QuotaWindow? {
        guard let quotas = snapshot?.quotas, !quotas.isEmpty else { return nil }
        return quotas.min {
            (QuotaPresentation.remainingFraction($0.shape) ?? 2) <
            (QuotaPresentation.remainingFraction($1.shape) ?? 2)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHero(tint: identity) {
                HStack(spacing: Theme.Space.md) {
                    // Chip em off-white com o glifo na cor do provedor: chip colorido
                    // sobre gradiente da mesma cor vira mancha (mesma regra do herói do
                    // popover).
                    Text(ProviderPalette.glyph(forId: providerId))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(identity)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.onHero))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(name)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Theme.onHero)
                        HeroStatusPill(text: status.text, dot: status.tint)
                        if let problem {
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.onHero.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } trailing: {
                if let window = tightest {
                    VStack(alignment: .trailing, spacing: 1) {
                        SectionHeader(WindowLabelCatalog.displayLabel(window.label), onHero: true)
                        Text(QuotaPresentation.remainingValueText(window.shape))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.onHero)
                            .lineLimit(1)
                        if QuotaPresentation.remainingFraction(window.shape) != nil {
                            Text(L("restante"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.onHero.opacity(0.8))
                        }
                    }
                }
            }
            Form {
                // O detalhe virou RODAPÉ da seção de conexão, não uma segunda seção. Como
                // seção ele era um cartão cinza do mesmo tamanho e da mesma cor do de
                // cima, contendo uma frase de legenda — dois objetos idênticos onde há um
                // assunto só. Como rodapé ele é texto secundário sob o card, que é o
                // idioma nativo de Ajustes do macOS para exatamente este papel.
                //
                // Cursor, Copilot e Antigravity não têm detalhe algum
                // (`details: EmptyView()`); o `if` evita o rodapé vazio.
                Section {
                    connection
                } header: {
                    Text(L("Conexão"))
                } footer: {
                    if Details.self != EmptyView.self {
                        details
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

/// Campo com auto-save: grava no Enter e ao perder o foco. O botão "Salvar" saiu de todos
/// os painéis, então a guarda que ele dava de graça (campo vazio não apaga nada) passou a
/// viver no `FieldCommit`, chamado dentro de `onCommit`.
struct AutoSaveField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    let onCommit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.roundedBorder)
        // Dentro do `Form` o título do campo vira rótulo visível e apareceria duplicado
        // ao lado do placeholder.
        .labelsHidden()
        .focused($focused)
        .onSubmit(onCommit)
        .onChange(of: focused) { _, isFocused in
            if !isFocused { onCommit() }
        }
        // Trocar de painel pela sidebar destrói o campo sem garantia de que o `@FocusState`
        // emita `false` antes: sem isto, digitar a chave e clicar direto no próximo
        // provedor perderia a edição sem aviso. É seguro repetir o commit porque
        // `sanitized` recusa vazio e inalterado.
        .onDisappear(perform: onCommit)
    }
}
