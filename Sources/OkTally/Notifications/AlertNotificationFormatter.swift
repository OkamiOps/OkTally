// Sources/OkTally/Notifications/AlertNotificationFormatter.swift
import Foundation

enum AlertNotificationFormatter {
    static func format(_ event: AlertEvent) -> (title: String, body: String) {
        let title = "\(event.providerDisplayName) — \(event.windowLabel)"
        var body: String
        if let percent = event.currentPercent {
            body = LF("%d%% da janela %@", Int(percent.rounded()), event.windowLabel)
            if let resetAt = event.resetAt {
                body += LF(" — reseta %@", relativeDateString(resetAt))
            }
        } else if let remaining = event.currentRemaining {
            body = LF("Saldo restante: %@", "\(remaining)")
        } else {
            body = ""
        }
        if event.isEstimated {
            body = L("Estimado: ") + body
        }
        return (title, body)
    }

    private static func relativeDateString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
