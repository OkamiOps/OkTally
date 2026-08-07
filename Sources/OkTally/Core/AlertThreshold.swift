// Sources/OkTally/Core/AlertThreshold.swift
import Foundation

enum AlertThreshold: Codable, Equatable, Hashable {
    case percentage(Double)
    case lowBalance(Decimal)

    static let defaultPercentageThresholds: [AlertThreshold] = [.percentage(0.7), .percentage(0.9), .percentage(1.0)]
    static let defaultLowBalanceThreshold: AlertThreshold = .lowBalance(5.0)
}
