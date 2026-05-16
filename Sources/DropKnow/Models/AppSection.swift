import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case recent = "最近下载"
    case queue = "处理队列"
    case reminders = "重要提醒"
    case search = "AI 问答"
    case subscription = "升级订阅"
    case settings = "设置"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .recent: "tray.full"
        case .reminders: "bell.badge"
        case .search: "bubble.left.and.text.bubble.right"
        case .subscription: "sparkles.rectangle.stack"
        case .queue: "list.bullet.rectangle.portrait"
        case .settings: "gearshape"
        }
    }
}
