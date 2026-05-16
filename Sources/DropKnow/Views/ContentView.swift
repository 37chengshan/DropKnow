import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @SceneStorage("selectedSection") private var selectedSectionRaw = AppSection.recent.rawValue

    private var selectedSection: Binding<AppSection> {
        Binding(
            get: { AppSection(rawValue: selectedSectionRaw) ?? .recent },
            set: { selectedSectionRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let prompt = store.historicalImportPrompt {
                HistoricalImportBanner(prompt: prompt)
            }

            NavigationSplitView {
                SidebarView(selection: selectedSection)
            } detail: {
                Group {
                    switch selectedSection.wrappedValue {
                    case .recent:
                        RecentDownloadsView()
                    case .queue:
                        QueuePage(selectedSection: selectedSection)
                    case .reminders:
                        ImportantRemindersView { file in
                            store.selectedFileID = file.id
                            selectedSection.wrappedValue = .recent
                        }
                    case .search:
                        SearchPage(selectedSection: selectedSection)
                    case .subscription:
                        SubscriptionPage()
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar { mainToolbar }
        .alert(
            "落知",
            isPresented: Binding(
                get: { store.alertMessage != nil },
                set: {
                    if !$0 {
                        store.alertMessage = nil
                        store.alertKind = nil
                    }
                }
            )
        ) {
            if store.shouldOfferCalendarSettings {
                Button("打开日历权限设置") {
                    store.openCalendarPrivacySettings()
                }
            }
            if store.shouldOfferProviderSettings {
                Button("打开设置") {
                    store.openProviderSettings()
                }
                Button("打开配置位置") {
                    store.openProviderConfigLocation()
                }
            }
            Button("好", role: .cancel) {
                store.alertMessage = nil
                store.alertKind = nil
            }
        } message: {
            Text(store.alertMessage ?? "")
        }
        .task(id: store.pendingNavigation?.id) {
            guard let request = store.pendingNavigation else { return }
            selectedSection.wrappedValue = request.section
            store.consumePendingNavigation()
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                store.chooseDirectory()
            } label: {
                Label("授权目录", systemImage: "folder.badge.plus")
            }

            Button {
                Task { await store.importRecentFiles(showToast: true) }
            } label: {
                Label("导入最近文件", systemImage: "arrow.clockwise")
            }
            .disabled(store.isImporting)
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        }

        ToolbarItemGroup {
            Button {
                store.openSelectedFile()
            } label: {
                Label("打开原文件", systemImage: "doc")
            }
            .disabled(store.selectedFile == nil)

            Button {
                Task { await store.reparseSelection() }
            } label: {
                Label("重新解析", systemImage: "wand.and.sparkles")
            }
            .disabled(store.selectedFile == nil)
        }
    }
}

private struct HistoricalImportBanner: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let prompt: HistoricalImportPromptState

    private var title: String {
        prompt.loadStatus == .corruptedState ? "已进入保护模式" : "发现历史文件"
    }

    private var message: String {
        if prompt.loadStatus == .corruptedState {
            return "状态文件损坏后已暂停历史文件自动处理。当前发现 \(prompt.totalHistoricalCount) 个历史文件，其中最近 \(prompt.recentDays) 天内有 \(prompt.recentCandidateCount) 个可导入。"
        }
        return "当前监听目录里发现 \(prompt.totalHistoricalCount) 个历史文件，其中最近 \(prompt.recentDays) 天内有 \(prompt.recentCandidateCount) 个可导入。为避免首次启动静默全量解析，历史文件需要你手动确认。"
    }

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(palette.accentOrange)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: 12)

            Button("稍后处理") {
                store.dismissHistoricalImportPrompt()
            }
            .dropSecondaryActionStyle()

            Button("导入最近\(prompt.recentDays)天") {
                Task { await store.importRecentFiles(showToast: true) }
            }
            .dropProminentActionStyle()
            .disabled(store.isImporting || prompt.recentCandidateCount == 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [palette.accentOrange.opacity(0.14), palette.accentGreen.opacity(0.08)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
