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

    var tint: Color {
        switch self {
        case .connected: return .green
        case .needsAttention: return .orange
        case .notConfigured: return .secondary
        }
    }
}

/// Casca comum dos dez painéis de provider, que antes montavam cabeçalho e botões cada
/// um do seu jeito. O `Form` agrupado rola sozinho, então o detalhe das Preferências não
/// embrulha mais os panes num `ScrollView` (daria rolagem aninhada).
struct ProviderPaneScaffold<Connection: View, Details: View>: View {
    let providerId: String
    let name: String
    let status: ProviderPaneStatus
    @ViewBuilder var connection: Connection
    @ViewBuilder var details: Details

    var body: some View {
        Form {
            Section {
                HStack(spacing: Theme.Space.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(ProviderPalette.color(for: providerId).opacity(0.16))
                            .frame(width: 40, height: 40)
                        Text(ProviderPalette.glyph(forId: providerId))
                            .font(.system(size: 19, weight: .heavy))
                            .foregroundStyle(ProviderPalette.color(for: providerId))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.system(size: 16, weight: .bold))
                        Text(status.text)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(status.tint)
                            .padding(.horizontal, Theme.Space.sm)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(status.tint.opacity(0.15)))
                    }
                    Spacer()
                }
            }
            Section(L("Conexão")) { connection }
            // Cursor, Copilot e Antigravity não têm detalhe algum (`details: EmptyView()`).
            // Sem esta guarda o `Form` agrupado desenhava um cartão vazio no fim da tela.
            if Details.self != EmptyView.self {
                Section { details }
            }
        }
        .formStyle(.grouped)
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
