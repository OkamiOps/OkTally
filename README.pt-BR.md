<div align="center">

# OkTally

**Todas as suas cotas de assinaturas de IA para código, na barra de menu do macOS — antes de você bater no teto.**

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black?style=flat)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat)](LICENSE)
[![Release](https://img.shields.io/github/v/release/OkamiOps/OkTally?style=flat)](https://github.com/OkamiOps/OkTally/releases)
[![Tests](https://img.shields.io/badge/tests-180%20passing-brightgreen?style=flat)](#desenvolvimento)

[English](README.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | **Português (BR)**

<br />

<img src="docs/assets/menubar.png" width="260" alt="OkTally menu bar label showing multiple pinned quota windows" />

<br />
<br />

<img src="docs/assets/popover.png" width="400" alt="OkTally popover dashboard with hero gauge and provider cards" />

<sub>As capturas usam dados de demonstração.</sub>

</div>

---

## Por que o OkTally

As ferramentas de IA por assinatura não avisam. A janela de 5 horas do Claude Code fecha no meio de um refactor, o limite semanal cai numa quinta-feira, e o primeiro sinal de problema é uma mensagem de "você atingiu seu limite". Enquanto isso, a cota que você *tem* sobrando em outra assinatura fica sem uso, porque nada avisa que ela está ali.

OkTally é um app nativo de barra de menu do macOS que mantém todas essas cotas visíveis num piscar de olhos — uma faixa colorida na barra de menu, um popover com o panorama completo, e uma notificação antes de acabar, não depois.

## Funcionalidades

**Barra de menu colorida, com quantos pins você quiser.** Fixe (pin) quantas janelas de cota quiser. Cada uma aparece como um glifo do provedor na cor de identidade dele, seguido da porcentagem restante, colorida conforme a proximidade do limite — verde acima de 30%, âmbar em 30% ou menos, vermelho em 10% ou menos:

```
C 78 · X 86 · ▹ 26
```

Se você não fixar nada, o OkTally mostra automaticamente a janela mais próxima do limite. O label é desenhado como uma imagem real (não-template), então as cores se mantêm na barra de menu em vez de serem achatadas para monocromático.

**Um popover que responde a pergunta primeiro.** Um medidor em destaque aponta a janela mais próxima de acabar, com uma contagem regressiva até o reset. Abaixo, uma grade de duas colunas com cards de provedor: um medidor em anel por provedor, depois uma linha por janela com porcentagem restante e horário de reset. Provedores com erro ou ainda não configurados ficam recolhidos em linhas discretas no final, fora do caminho.

**Preferências que parecem com Ajustes do Sistema.** Uma barra lateral lista cada provedor com um indicador de status ao vivo, um painel por provedor, além de um painel Geral para reordenar e remover pins da barra de menu.

**Notificações antes do limite.** Um motor de alertas por transição de borda dispara uma notificação do macOS no momento em que um limiar é ultrapassado — uma vez por transição, não uma vez por consulta.

## Provedores

| Provedor | Autenticação | O que você vê |
| --- | --- | --- |
| **Claude Code** | OAuth, ou importação com um clique do seu login existente da CLI do Claude Code | Janelas de 5h + semanal |
| **Codex** | OAuth | Janelas semanais |
| **SuperGrok** | Código de dispositivo OAuth | Janelas do plano |
| **Cursor** | Automática — lê a sessão local do app Cursor | Saldo + porcentagem de uso |
| **OpenRouter** | Chave de API | Saldo de crédito |
| **MiniMax** | Chave de API (região global ou China) | Janelas de 5h + semanal |
| **OpenCode** | Chave de API | Uso do plano |
| **MiMo** | Sessão web no app (autorrecuperável) ou estimativa manual | Plano mensal |

**Sessão MiMo autorrecuperável.** A sessão do console da Xiaomi vive numa web view persistente dentro do app. Quando o cookie STS de curta duração expira, o OkTally recarrega o console de forma transparente e tenta novamente — você só precisa fazer login de novo se a sessão SSO subjacente da Xiaomi realmente cair.

## Instalação

### DMG (recomendado)

1. Baixe o `OkTally-1.0.0.dmg` na [página de Releases](https://github.com/OkamiOps/OkTally/releases).
2. Abra o arquivo e arraste **OkTally** para Applications.
3. O app não é notarizado: no primeiro lançamento, clique com o botão direito (Ctrl-clique) em `OkTally.app` → **Abrir** → **Abrir**.

### Compilar a partir do código-fonte

Requer o Xcode Command Line Tools com Swift 5.9 ou mais recente.

```bash
git clone https://github.com/OkamiOps/OkTally.git
cd OkTally
bash Scripts/build_app.sh    # compila .build/OkTally.app
```

Extras opcionais:

```bash
bash Scripts/install_launch_agent.sh   # iniciar o OkTally no login
bash Scripts/make_dmg.sh               # empacotar um DMG de arrastar-e-instalar
```

> **Recomendado ao compilar a partir do código-fonte:** crie um certificado de assinatura de código autoassinado chamado `OkTally Dev` (Keychain Access → Certificate Assistant → Create a Certificate… → Self-Signed Root, Code Signing). Assinaturas ad-hoc mudam a identidade do app a cada build, o que invalida as ACLs do Keychain e força você a fazer login novamente. O `build_app.sh` detecta o certificado automaticamente quando ele existe.

## Primeiros passos

1. Clique no item do OkTally na barra de menu e abra **Preferências**.
2. Conecte cada provedor que você usa — login OAuth, chave de API ou o login web do MiMo.
3. De volta ao popover, fixe as janelas que interessam a você com o ícone de pin.
4. Reordene ou remova pins em **Preferências → Geral**.

## Desenvolvimento

```bash
swift test    # 180 testes unitários
```

Cada provedor é um plugin que segue um único protocolo `UsageProvider` e normaliza seus dados em um modelo `QuotaShape` — janela rolante, contador periódico, saldo de crédito, medido ou estimado — para que a interface nunca precise tratar um fornecedor como caso especial. Um scheduler consulta os provedores em intervalos configuráveis por provedor, e a lógica de apresentação vive em modelos puros como o `MenuBarLabelModel`, o que mantém a renderização do label e do dashboard totalmente testável sem um app em execução. Documentos de design ficam em `docs/superpowers/`.

## Privacidade

Tudo roda localmente no seu Mac.

- Tokens OAuth e chaves de API ficam armazenados no **macOS Keychain**, nunca em texto puro.
- O histórico de uso vive em um banco de dados **SQLite** local.
- Sem telemetria, sem analytics, sem servidores externos — o OkTally conversa apenas com as APIs dos próprios provedores.

## Licença

[MIT](LICENSE) © OkamiOps
</content>
</invoke>
