// Tests/OkTallyTests/AlertDispatcherTests.swift
import XCTest
@testable import OkTally

final class FakeNotificationSender: NotificationSending {
    private(set) var sentMessages: [(title: String, body: String)] = []
    func send(title: String, body: String) async {
        sentMessages.append((title, body))
    }
}

final class AlertDispatcherTests: XCTestCase {
    func test_dispatch_sendsOneNotificationPerEvent() async {
        let sender = FakeNotificationSender()
        let dispatcher = AlertDispatcher(sender: sender)
        let events = [
            AlertEvent(providerId: "claude", providerDisplayName: "Claude Code", windowLabel: "5h", threshold: .percentage(0.7), currentPercent: 71, currentRemaining: nil, resetAt: nil),
            AlertEvent(providerId: "claude", providerDisplayName: "Claude Code", windowLabel: "weekly", threshold: .percentage(0.9), currentPercent: 91, currentRemaining: nil, resetAt: nil)
        ]
        await dispatcher.dispatch(events)
        XCTAssertEqual(sender.sentMessages.count, 2)
        XCTAssertEqual(sender.sentMessages[0].title, "Claude Code — 5h")
        XCTAssertEqual(sender.sentMessages[1].title, "Claude Code — weekly")
    }

    func test_dispatch_withNoEvents_sendsNothing() async {
        let sender = FakeNotificationSender()
        let dispatcher = AlertDispatcher(sender: sender)
        await dispatcher.dispatch([])
        XCTAssertTrue(sender.sentMessages.isEmpty)
    }
}
