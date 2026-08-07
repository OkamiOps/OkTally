// Sources/OkTally/Core/AlertEvent.swift
import Foundation

struct AlertEvent: Equatable {
    let providerId: String
    let providerDisplayName: String
    let windowLabel: String
    let threshold: AlertThreshold
    let currentPercent: Double?
    let currentRemaining: Decimal?
    let resetAt: Date?
}
