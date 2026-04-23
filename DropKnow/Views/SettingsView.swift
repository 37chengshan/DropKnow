import SwiftUI
import EventKit

public struct SettingsView: View {
    @State private var model: DropKnowAppModel

    public init(model: DropKnowAppModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionCard(title: "目录与权限", subtitle: "管理监听目录与授权状态") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.watchRegistrations, id: \.id) { registration in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(registration.display_name)
                                        .font(.headline)
                                    Spacer()
                                    Toggle(
                                        "",
                                        isOn: Binding(
                                            get: { registration.is_active },
                                            set: { newValue in
                                                Task {
                                                    await model.setDirectoryActive(id: registration.id, isActive: newValue)
                                                }
                                            }
                                        )
                                    )
                                    .labelsHidden()
                                }

                                Text(registration.path_hint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if registration.is_default_downloads {
                                    Text("默认推荐目录")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    HStack {
                                        Text("自定义目录")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("移除") {
                                            Task {
                                                await model.removeCustomDirectory()
                                            }
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                        }

                        Button("添加自定义目录") {
                            Task {
                                await model.addCustomDirectory()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                sectionCard(title: "隐私与门禁", subtitle: "高风险文件会暂停并等待确认") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("策略：敏感内容默认要求用户确认后继续。")
                        Text("被门禁阻断时，会在详情页显示原因与下一步操作。")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                sectionCard(title: "日历能力", subtitle: "仅在用户主动触发后写入日历") {
                    CalendarPermissionRow()
                }

                sectionCard(title: "订阅与配额", subtitle: "展示当前能力边界") {
                    VStack(alignment: .leading, spacing: 8) {
                        QuotaBadge(label: "解析额度", used: model.quotaSnapshot.parseUsed, limit: model.quotaSnapshot.parseLimit)
                        QuotaBadge(label: "问答额度", used: model.quotaSnapshot.qaUsed, limit: model.quotaSnapshot.qaLimit)
                        QuotaBadge(label: "搜索额度", used: model.quotaSnapshot.searchUsed, limit: model.quotaSnapshot.searchLimit)
                        Text("免费版默认限制高级问答与部分自动化能力。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("版本")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ProviderStatusSection()

                sectionCard(title: "诊断信息", subtitle: "定位当前系统状态") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(model.watcherStatusText, systemImage: "dot.radiowaves.left.and.right")
                            .font(.footnote)
                        if let message = model.settingsMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func sectionCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ProviderStatusSection: View {
    @State private var sectionState: SectionState = .loading

    var body: some View {
        SettingsSectionCard(title: "Provider 配置", subtitle: "展示当前已加载的 provider 状态") {
            VStack(alignment: .leading, spacing: 8) {
                switch sectionState {
                case .loading:
                    HStack {
                        Text("加载中...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                case .empty:
                    HStack {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("所有 Provider")
                            .font(.footnote)
                        Spacer()
                        Text("未配置")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .rows(let entries):
                    ForEach(entries) { entry in
                        HStack {
                            Circle().fill(entry.color).frame(width: 8, height: 8)
                            Text(entry.label).font(.footnote)
                            Spacer()
                            Text(entry.statusText).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task { await loadProviderStatus() }
    }

    private func loadProviderStatus() async {
        let configs = ProviderConfigLoader.load()
        if configs.isEmpty {
            sectionState = .empty
            return
        }
        var entries: [Entry] = []
        entries.append(entry(for: "摘要服务 (Summary)", config: configs.first { $0.provider_id == "provider_summary_mock" }))
        entries.append(entry(for: "事件抽取 (Event)", config: configs.first { $0.provider_id == "provider_event_mock" }))
        entries.append(entry(for: "问答搜索 (QA)", config: configs.first { $0.provider_id == "provider_search_qa_mock" }))
        sectionState = .rows(entries)
    }

    private func entry(for label: String, config: ProviderConfig?) -> Entry {
        if let config, !config.base_url.isEmpty {
            return Entry(label: label, statusText: "\(config.model_name) @ \(config.base_url)", color: .green)
        } else if config != nil {
            return Entry(label: label, statusText: "Mock 模式", color: .yellow)
        } else {
            return Entry(label: label, statusText: "未配置", color: .orange)
        }
    }
}

private struct Entry: Identifiable {
    let id = UUID()
    let label: String
    let statusText: String
    let color: Color
}

private enum SectionState {
    case loading
    case empty
    case rows([Entry])
}

private struct CalendarPermissionRow: View {
    @State private var authStatus: EKAuthorizationStatus = .notDetermined
    @State private var isRequesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText).font(.footnote)
                Spacer()
                if authStatus == .notDetermined {
                    Button("请求授权") {
                        requestAccess()
                    }
                    .buttonStyle(.borderless)
                    .disabled(isRequesting)
                } else if authStatus == .denied || authStatus == .restricted {
                    Button("打开系统设置") {
                        openSystemSettings()
                    }
                    .buttonStyle(.borderless)
                }
            }
            Text("当前行为：不做静默自动入历。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("如遇权限缺失或不可入历，将在详情页给出可解释状态。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            await loadAuthorizationStatus()
        }
    }

    private var statusText: String {
        switch authStatus {
        case .authorized: return "已授权"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        case .notDetermined: return "未决定"
        case .fullAccess: return "完全访问"
        case .writeOnly: return "仅写入"
        @unknown default: return "未知"
        }
    }

    private var statusColor: Color {
        switch authStatus {
        case .authorized, .fullAccess: return .green
        case .writeOnly: return .yellow
        case .denied, .restricted: return .red
        case .notDetermined: return .orange
        @unknown default: return .gray
        }
    }

    private func loadAuthorizationStatus() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        await MainActor.run {
            authStatus = status
        }
    }

    private func requestAccess() {
        isRequesting = true
        let store = EKEventStore()
        if #available(macOS 14.0, *) {
            store.requestWriteOnlyAccessToEvents { granted, _ in
                Task { @MainActor in
                    authStatus = granted ? .writeOnly : .denied
                    isRequesting = false
                }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                Task { @MainActor in
                    authStatus = granted ? .authorized : .denied
                    isRequesting = false
                }
            }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
