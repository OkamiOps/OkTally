// Sources/OkTally/Core/QuotaShape.swift
import Foundation

enum QuotaShape: Equatable {
    case rollingWindow(used: Double, limit: Double, windowStart: Date, resetAt: Date)
    case periodicCounter(used: Double, limit: Double, resetAt: Date)
    case creditBalance(remaining: Decimal, currency: String)
    case meteredOnly(costAccrued: Decimal)

    var usedPercent: Double? {
        switch self {
        case .rollingWindow(let used, let limit, _, _):
            guard limit > 0 else { return nil }
            return min(used / limit, 1.0) * 100
        case .periodicCounter(let used, let limit, _):
            guard limit > 0 else { return nil }
            return min(used / limit, 1.0) * 100
        case .creditBalance, .meteredOnly:
            return nil
        }
    }

    var resetAt: Date? {
        switch self {
        case .rollingWindow(_, _, _, let resetAt): return resetAt
        case .periodicCounter(_, _, let resetAt): return resetAt
        case .creditBalance, .meteredOnly: return nil
        }
    }
}

extension QuotaShape: Codable {
    private enum Kind: String, Codable {
        case rollingWindow, periodicCounter, creditBalance, meteredOnly
    }

    private enum CodingKeys: String, CodingKey {
        case kind, used, limit, windowStart, resetAt, remaining, currency, costAccrued
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .rollingWindow:
            self = .rollingWindow(
                used: try container.decode(Double.self, forKey: .used),
                limit: try container.decode(Double.self, forKey: .limit),
                windowStart: try container.decode(Date.self, forKey: .windowStart),
                resetAt: try container.decode(Date.self, forKey: .resetAt)
            )
        case .periodicCounter:
            self = .periodicCounter(
                used: try container.decode(Double.self, forKey: .used),
                limit: try container.decode(Double.self, forKey: .limit),
                resetAt: try container.decode(Date.self, forKey: .resetAt)
            )
        case .creditBalance:
            self = .creditBalance(
                remaining: try container.decode(Decimal.self, forKey: .remaining),
                currency: try container.decode(String.self, forKey: .currency)
            )
        case .meteredOnly:
            self = .meteredOnly(costAccrued: try container.decode(Decimal.self, forKey: .costAccrued))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rollingWindow(let used, let limit, let windowStart, let resetAt):
            try container.encode(Kind.rollingWindow, forKey: .kind)
            try container.encode(used, forKey: .used)
            try container.encode(limit, forKey: .limit)
            try container.encode(windowStart, forKey: .windowStart)
            try container.encode(resetAt, forKey: .resetAt)
        case .periodicCounter(let used, let limit, let resetAt):
            try container.encode(Kind.periodicCounter, forKey: .kind)
            try container.encode(used, forKey: .used)
            try container.encode(limit, forKey: .limit)
            try container.encode(resetAt, forKey: .resetAt)
        case .creditBalance(let remaining, let currency):
            try container.encode(Kind.creditBalance, forKey: .kind)
            try container.encode(remaining, forKey: .remaining)
            try container.encode(currency, forKey: .currency)
        case .meteredOnly(let costAccrued):
            try container.encode(Kind.meteredOnly, forKey: .kind)
            try container.encode(costAccrued, forKey: .costAccrued)
        }
    }
}
