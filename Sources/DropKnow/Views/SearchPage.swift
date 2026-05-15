import SwiftUI

struct SearchPage: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selectedSection: AppSection
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isInputFocused: Bool

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            HeaderStrip(title: "AI 问答", subtitle: "普通问题直接回答；涉及下载文件、通知、时间和待办时会附带可联动文件卡片")

            if store.providerStatus.mode != .remoteReady {
                ProviderStatusBanner()
                    .padding(.horizontal)
                    .padding(.bottom, 10)
            }

            if let error = store.searchErrorMessage, !error.isEmpty {
                HStack(spacing: 10) {
                    Label("检索失败：\(error)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(palette.danger)
                        .lineLimit(2)
                    Spacer()
                    Button("重试") {
                        store.retryLastSearch()
                    }
                    .font(.caption)
                    .buttonStyle(DropSecondaryButtonStyle())
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }

            VStack(spacing: 0) {
                ChatWorkingStatusBar(isWorking: store.isChatWorking)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if store.chatMessages.count <= 1, !store.isSearching {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("开始提问")
                                        .font(.headline)
                                    Text("输入问题后点「发送」或回车。快速连续触发时会自动取消/丢弃旧请求，只保留最新一次结果。")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                            }

                            ForEach(store.chatMessages) { message in
                                ChatBubble(message: message, selectedSection: $selectedSection)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: store.chatMessages.count) {
                        if let last = store.chatMessages.last?.id {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            .dropWorkingBorderBeam(isActive: store.isChatWorking, cornerRadius: 16)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TextField("问通用问题，或问文件里的内容、时间、待办、证据来源...", text: $store.searchQuery, axis: .vertical)
                        .textFieldStyle(DropTextFieldStyle())
                        .focused($isInputFocused)
                        .dropFieldChrome(isFocused: isInputFocused)
                        .lineLimit(1...4)
                        .onSubmit {
                            store.submitSearch()
                        }

                    Button {
                        store.submitSearch()
                    } label: {
                        Label("发送", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(DropPrimaryButtonStyle())
                    .disabled(store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        Task { await store.rebuildSemanticIndex() }
                    } label: {
                        Label("补齐索引", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(store.isRebuildingIndex)
                    .buttonStyle(DropSecondaryButtonStyle())
                }

                if let warning = store.searchQuotaWarning, !warning.isEmpty {
                    HStack(spacing: 10) {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(palette.warning)
                        Spacer()
                        Button("提升额度") {
                            if let trigger = store.activeUpgradeTrigger {
                                store.openUpgradePage(trigger: trigger)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(DropSecondaryButtonStyle())
                    }
                }
            }
            .padding()
        }
        .onDisappear {
            store.cancelSearch()
        }
    }
}

private struct ChatWorkingStatusBar: View {
    @EnvironmentObject private var store: AppStore
    var isWorking: Bool

    var body: some View {
        if isWorking {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在检索文件并整理证据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") {
                    store.cancelSearch()
                }
                .font(.caption)
                .buttonStyle(DropSecondaryButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .transition(.opacity)
        }
    }
}

private struct ProviderStatusBanner: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        let palette = theme.palette(for: colorScheme)
        switch store.providerStatus.mode {
        case .remoteReady: return palette.success
        case .localFallback: return palette.warning
        case .unavailable: return palette.danger
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: store.providerStatus.mode == .unavailable ? "xmark.octagon.fill" : "bolt.trianglebadge.exclamationmark.fill")
                .foregroundStyle(tint)
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(store.providerStatus.headline)
                    .font(.callout.weight(.semibold))
                if let detail = store.providerStatus.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Button("打开设置") {
                store.openProviderSettings()
            }
            .font(.caption)
            .buttonStyle(DropSecondaryButtonStyle())

            Button("配置位置") {
                store.openProviderConfigLocation()
            }
            .font(.caption)
            .buttonStyle(DropSecondaryButtonStyle())
        }
        .padding(12)
        .dropGlass(cornerRadius: 14)
    }
}

private struct ChatBubble: View {
    @EnvironmentObject private var store: AppStore
    var message: ChatMessage
    @Binding var selectedSection: AppSection
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        HStack {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: .leading, spacing: 10) {
                MarkdownText(message.text)

                if let result = message.result {
                    HStack(spacing: 8) {
                        StatusPill(text: result.engine, systemImage: "internaldrive")
                    }

                    if let warning = result.warning, !warning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        WarningSection(message: warning)
                    }

                    if result.diagnostics.emptyIndex {
                        WarningSection(message: "当前索引为空，请先导入文件或补齐索引。")
                    }

                    if !result.hits.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("证据来源")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(result.hits) { hit in
                                EvidenceHitCard(hit: hit, selectedSection: $selectedSection)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: message.role == .user ? 520 : .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(message.role == .user ? palette.accentOrange.opacity(0.14) : palette.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.border, lineWidth: theme.metrics.borderWidth)
            )

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }
}

private struct EvidenceHitCard: View {
    @EnvironmentObject private var store: AppStore
    var hit: SearchHit
    @Binding var selectedSection: AppSection
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        Button {
            if store.navigateToSearchHit(hit) {
                selectedSection = .recent
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(palette.accentOrange)
                        .font(.system(size: 16, weight: .semibold))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(hit.fileName)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        Text(hit.filePath)
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    StatusPill(text: String(format: "%.3f", hit.score), systemImage: "scope")
                }

                Text(store.searchSnippet(for: hit))
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(4)

                if let matchReason = hit.matchReason,
                   !matchReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(matchReason, systemImage: "text.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.right.fill")
                        .font(.caption2)
                    Text("打开详情并定位到证据片段")
                        .font(.caption)
                }
                .foregroundStyle(palette.accentOrange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dropGlass(cornerRadius: 10, interactive: true)
        .buttonStyle(.plain)
    }
}

private struct MarkdownText: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .font(.body)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
