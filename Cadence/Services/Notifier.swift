import Foundation
import UserNotifications

enum Notifier {
    /// `url` rides along in userInfo so tapping the notification can route the canvas —
    /// see NotificationRouter in CadenceApp.swift.
    static func post(title: String, body: String, id: String = UUID().uuidString, url: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let url { content.userInfo = ["url": url] }
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
