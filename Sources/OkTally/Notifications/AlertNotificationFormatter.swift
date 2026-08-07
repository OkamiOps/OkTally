// Sources/OkTally/Notifications/AlertNotificationFormatter.swift
import Foundation

enum AlertNotificationFormatter {
    static func format(_ event: AlertEvent) -> (title: String, body: String) {
        let title = "\(event.providerDisplayName) — \(event.windowLabel)"
        var body: String
        if let percent = event.currentPercent {
            body = "\(Int(percent.rounded()))% da janela \(event.windowLabel)"
            if let resetAt = event.resetAt {
                body += " — reseta \(relativeDateString(resetAt))"
            }
        } else if let remaining = event.currentRemaining {
            body = "Saldo restante: \(remaining)"
        } else {
            body = ""
        }
        return (title, body)
    }

    private static func relativeDateString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
