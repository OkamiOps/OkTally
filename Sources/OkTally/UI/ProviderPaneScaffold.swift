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
struct ProviderPaneScaffold<Connection: View, Details: View, Account: View>: View {
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
    /// Seção "Conta" (e-mail, apelido, remover). Vazia nos painéis que não a têm.
    @ViewBuilder var account: Account

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
            hero
            ScrollView {
                VStack(spacing: Theme.Space.lg) {
                    PreferencePanel(title: L("Conexão"), systemImage: "link", tint: identity) {
                        connection
                    } footer: {
                        if Details.self != EmptyView.self {
                            details
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if Account.self != EmptyView.self {
                        PreferencePanel(title: L("Conta"), systemImage: "person.crop.circle", tint: identity) {
                            account
                        } footer: {
                            EmptyView()
                        }
                    }
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.pageBackground)
        }
        .frame(minHeight: 0, maxHeight: .infinity)
    }

    /// Hero de assinatura. Não é só uma faixa colorida: mostra identidade, estado e a
    /// quota mais apertada num anel, então a tela de configuração responde de cara
    /// "esta conta está conectada e quanto ainda resta".
    private var hero: some View {
        HStack(spacing: Theme.Space.lg) {
            Text(ProviderPalette.glyph(forId: providerId))
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(identity)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.onHero))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.12)))
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Theme.onHero)
                    .lineLimit(1)
                HStack(spacing: Theme.Space.sm) {
                    HeroStatusPill(text: status.text, dot: status.tint)
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.onHero.opacity(0.92))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: Theme.Space.lg)
            if let window = tightest {
                HStack(spacing: Theme.Space.md) {
                    VStack(alignment: .trailing, spacing: 2) {
                        SectionHeader(WindowLabelCatalog.displayLabel(window.label), onHero: true)
                        Text(QuotaPresentation.remainingValueText(window.shape))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.onHero)
                        if let reset = QuotaPresentation.resetCompactText(window.shape) {
                            Text(reset)
                                .font(.system(size: 9, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.onHero.opacity(0.72))
                        }
                    }
                    quotaRing(window)
                }
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroFill(identity))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.28)).frame(height: 1)
        }
    }

    private func quotaRing(_ window: QuotaWindow) -> some View {
        let fraction = QuotaPresentation.remainingFraction(window.shape) ?? 0
        return ZStack {
            Circle()
                .stroke(Color.black.opacity(0.24), lineWidth: 5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.onHero, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 46, height: 46)
    }

}

extension ProviderPaneScaffold where Account == EmptyView {
    init(providerId: String, snapshot: ProviderSnapshot? = nil, problem: String? = nil, name: String,
         status: ProviderPaneStatus,
         @ViewBuilder connection: () -> Connection, @ViewBuilder details: () -> Details) {
        self.init(providerId: providerId, snapshot: snapshot, problem: problem, name: name, status: status,
                  connection: connection, details: details, account: { EmptyView() })
    }
}

/// Painel de configuração usado pelos providers. Substitui o `Form` nativo empilhado:
/// os controles continuam nativos, mas ganham um container com título, ícone e hierarquia
/// clara em vez de blocos cinzas indistintos.
private struct PreferencePanel<Content: View, Footer: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.onHero)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                content
            }
            if Footer.self != EmptyView.self {
                footer
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// Campo com auto-save: grava no Enter e ao perder o foco. O botão "Salvar" saiu de todos
/// os painéis, então a guarda que ele dava de graça (campo vazio não apaga nada) passou a
/// viver no `FieldCommit`, chamado dentro de `onCommit`.
///
/// O placeholder usa `prompt:`, não `TextField(titleKey:text:)`/`SecureField(titleKey:text:)`
/// — a `titleKey` some quando o campo perde o rótulo (`.labelsHidden()`, obrigatório dentro
/// de `Form`) e o campo fica uma caixa vazia sem nenhuma pista do que digitar ali. O
/// `Text(placeholder)` em `.secondary` explícito garante contraste contra a superfície
/// quase preta do app, em vez de depender do cinza padrão do sistema.
struct AutoSaveField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    let onCommit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(.secondary))
            } else {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.secondary))
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
