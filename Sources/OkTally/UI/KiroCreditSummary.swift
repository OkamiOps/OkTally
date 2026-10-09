import SwiftUI

struct KiroCreditSummary: View {
    let snapshot: ProviderSnapshot?

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                if let plan = snapshot.planLabel {
                    Text(LF("Plano: %@", plan)).fontWeight(.semibold)
                }
                ForEach(snapshot.quotas, id: \.label) { quota in
                    if case .periodicCounter(let used, let limit, _) = quota.shape {
                        Text("\(WindowLabelCatalog.displayLabel(quota.label)): " +
                             LF("%@ de %@ créditos restantes", format(max(0, limit - used)), format(limit)))
                            .textSelection(.enabled)
                    }
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
