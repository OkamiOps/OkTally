// Sources/OkTally/UI/QuotaDisplayFormatter.swift
import Foundation

enum QuotaDisplayFormatter {
    static func valueText(for shape: QuotaShape) -> String {
        if case .estimated(_, let limit, _, _) = shape {
            if let percent = shape.usedPercent {
                return "~\(Int(percent.rounded()))%"
            }
            _ = limit
            return "~ (limite atingido)"
        }
        if let percent = shape.usedPercent {
            return "\(Int(percent.rounded()))%"
        }
        switch shape {
        case .creditBalance(let remaining, let currency):
            return "\(remaining) \(currency)"
        case .meteredOnly(let cost):
            return "$\(cost)"
        default:
            return ""
        }
    }
}
