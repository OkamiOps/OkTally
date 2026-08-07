// Sources/OkTally/UI/QuotaDisplayFormatter.swift
import Foundation

enum QuotaDisplayFormatter {
    static func valueText(for shape: QuotaShape) -> String {
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
