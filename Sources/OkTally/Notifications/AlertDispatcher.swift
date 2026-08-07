// Sources/OkTally/Notifications/AlertDispatcher.swift
struct AlertDispatcher {
    let sender: NotificationSending

    func dispatch(_ events: [AlertEvent]) async {
        for event in events {
            let (title, body) = AlertNotificationFormatter.format(event)
            await sender.send(title: title, body: body)
        }
    }
}
