// Sources/OkTally/Notifications/NotificationSending.swift
import UserNotifications

protocol NotificationSending {
    func send(title: String, body: String) async
}

final class UNNotificationSender: NotificationSending {
    func requestAuthorizationIfNeeded() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func send(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
