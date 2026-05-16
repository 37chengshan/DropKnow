import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    var onOpenFile: ((UUID, FileDetailSectionAnchor?) -> Void)?

    private var recentNotificationDates: [String: Date] = [:]
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private override init() {
        super.init()
    }

    func requestAuthorization() {
        guard let center = configuredCenter() else { return }
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func notifyParsedFile(_ descriptor: ParsedFileNotificationDescriptor) {
        let dedupeKey = "file-\(descriptor.fileID.uuidString)"
        guard shouldSend(dedupeKey: dedupeKey) else { return }
        send(
            id: dedupeKey,
            title: descriptor.title,
            subtitle: descriptor.subtitle,
            body: descriptor.body,
            userInfo: [
                "fileID": descriptor.fileID.uuidString,
                "anchor": descriptor.anchor.rawValue
            ]
        )
    }

    func notifySensitiveGate(_ file: DropFile) {
        send(
            id: "sensitive-\(file.id.uuidString)",
            title: "落知需要确认",
            subtitle: file.fileName,
            body: "该文件疑似包含敏感信息，确认后才会解析并写入语义索引。"
        )
    }

    func notifyCalendarAdded(title: String) {
        send(
            id: "calendar-\(UUID().uuidString)",
            title: "已加入日历",
            subtitle: title,
            body: "事件已写入系统日历。"
        )
    }

    func notifyIndexRebuilt(count: Int) {
        send(
            id: "rag-rebuild-\(UUID().uuidString)",
            title: "语义索引已重建",
            subtitle: "\(count) 个文件",
            body: "落知已使用真实 embedding 重新写入 zvec。"
        )
    }

    private func send(id: String, title: String, subtitle: String, body: String, userInfo: [AnyHashable: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        guard let center = configuredCenter() else { return }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }

    private func shouldSend(dedupeKey: String, now: Date = Date()) -> Bool {
        if let lastSentAt = recentNotificationDates[dedupeKey],
           now.timeIntervalSince(lastSentAt) < 900 {
            return false
        }
        recentNotificationDates[dedupeKey] = now
        return true
    }

    private func configuredCenter() -> UNUserNotificationCenter? {
        guard !isRunningTests else { return nil }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let fileIDRaw = userInfo["fileID"] as? String,
              let fileID = UUID(uuidString: fileIDRaw) else {
            return
        }
        let anchor = (userInfo["anchor"] as? String).flatMap(FileDetailSectionAnchor.init(rawValue:))
        onOpenFile?(fileID, anchor)
    }
}
