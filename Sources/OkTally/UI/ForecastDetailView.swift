import SwiftUI

/// Detailed forecast for one provider. Window selection is deliberately local to this
/// screen: inspecting another renewable limit must not change the popover preference.
struct ForecastDetailView: View {
    let providerId: String
    let forecasts: [UsageForecast]
    let now: Date

    @State private var selectedWindowLabel: String?

    init(providerId: String, forecasts: [UsageForecast], now: Date = Date()) {
        self.providerId = providerId
        self.forecasts = forecasts
        self.now = now
    }

    private var selectedForecast: UsageForecast? {
        if let selectedWindowLabel,
           let selected = forecasts.first(where: { $0.id.windowLabel == selectedWindowLabel }) {
            return selected
        }
        return forecasts.first
    }

    var body: some View {
        if let forecast = selectedForecast {
            let presentation = UsageForecastPresentation(forecast: forecast, now: now)
            DashboardCard(padding: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    header(forecast: forecast)
                    Text(presentation.headline)
                        .font(Theme.Font.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForecastChartView(
                        forecast: forecast,
                        providerColor: ProviderPalette.color(for: providerId),
                        now: now
                    )
                    metricGrid(forecast: forecast)
                }
            }
        }
    }

    private func header(forecast: UsageForecast) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(L("Previsão de consumo"))
                Text(L("Estimativa pelas últimas 24 horas"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: Theme.Space.sm)
            if forecasts.count > 1 {
                Picker(L("Janela"), selection: selectionBinding(fallback: forecast.id.windowLabel)) {
                    ForEach(forecasts, id: \.id) { option in
                        Text(WindowLabelCatalog.displayLabel(option.id.windowLabel))
                            .tag(option.id.windowLabel)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            } else {
                Text(WindowLabelCatalog.displayLabel(forecast.id.windowLabel))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func selectionBinding(fallback: String) -> Binding<String> {
        Binding(
            get: {
                guard let selectedWindowLabel,
                      forecasts.contains(where: { $0.id.windowLabel == selectedWindowLabel }) else {
                    return fallback
                }
                return selectedWindowLabel
            },
            set: { selectedWindowLabel = $0 }
        )
    }

    private func metricGrid(forecast: UsageForecast) -> some View {
        let metrics = ForecastDetailMetrics(forecast: forecast).items
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)],
            alignment: .leading,
            spacing: Theme.Space.md
        ) {
            ForEach(metrics, id: \.label) { metric in
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.label)
                        .font(Theme.Font.label)
                        .foregroundStyle(.secondary)
                    Text(metric.value)
                        .font(Theme.Font.body.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(2)
                }
            }
        }
    }
}

struct ForecastDetailMetric: Equatable {
    let label: String
    let value: String
}

struct ForecastDetailMetrics: Equatable {
    let forecast: UsageForecast

    var items: [ForecastDetailMetric] {
        var result: [ForecastDetailMetric] = [
            ForecastDetailMetric(
                label: L("Esgotamento previsto"),
                value: exhaustionValue
            )
        ]

        if let resetAt = forecast.resetAt {
            result.append(ForecastDetailMetric(label: L("Renovação"), value: Self.dateText(resetAt)))
        }

        if let gap = forecast.gap {
            result.append(ForecastDetailMetric(
                label: gap > 0 ? L("Falta projetada") : L("Folga projetada"),
                value: UsageForecastPresentation.durationText(abs(gap))
            ))
        }

        result.append(ForecastDetailMetric(
            label: L("Ritmo observado"),
            value: forecast.ratePerDay.map { LF("%@%%/dia", UsageForecastPresentation.decimal($0)) }
                ?? L("Ainda sem ritmo confiável")
        ))
        result.append(ForecastDetailMetric(
            label: L("Ritmo seguro"),
            value: forecast.safeRatePerDay.map { LF("até %@%%/dia", UsageForecastPresentation.decimal($0)) }
                ?? L("Indisponível")
        ))

        return result
    }

    private var exhaustionValue: String {
        if let exhaustionAt = forecast.exhaustionAt { return Self.dateText(exhaustionAt) }
        switch forecast.state {
        case .collecting:
            return L("Ainda coletando histórico")
        case .unavailable:
            return L("Indisponível")
        case .noExhaustion, .slowDown, .onPace, .canAccelerate:
            return L("Sem esgotamento previsto")
        }
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
