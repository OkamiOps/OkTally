// Sources/OkTally/Core/RefreshStagger.swift
import Foundation

/// Espalha no tempo o primeiro fetch de contas do MESMO tipo. Duas contas do Claude
/// batendo no `/api/oauth/usage` no mesmo segundo dobram a chance de 429; com o atraso
/// elas entram defasadas. Contas únicas (o caso de todo mundo que nunca adicionou uma
/// segunda) começam na hora, exatamente como antes.
///
/// Regra: `offset = índice entre irmãos × min(intervalo / nº de irmãos, 60 s)`.
enum RefreshStagger {
    static let maxStep: TimeInterval = 60

    static func offsets(for entries: [(id: String, interval: TimeInterval)]) -> [String: TimeInterval] {
        var groups: [String: [(id: String, interval: TimeInterval)]] = [:]
        for entry in entries {
            groups[groupKey(entry.id), default: []].append(entry)
        }
        var result: [String: TimeInterval] = [:]
        for siblings in groups.values {
            for (index, entry) in siblings.enumerated() {
                let step = min(entry.interval / Double(siblings.count), maxStep)
                result[entry.id] = Double(index) * step
            }
        }
        return result
    }

    static func offset(of id: String, among entries: [(id: String, interval: TimeInterval)]) -> TimeInterval {
        offsets(for: entries)[id] ?? 0
    }

    private static func groupKey(_ id: String) -> String {
        AccountID.kind(of: id)?.rawValue ?? id
    }
}
