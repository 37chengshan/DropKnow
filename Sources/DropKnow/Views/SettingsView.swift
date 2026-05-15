import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dropTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        Form {
            Section("基础设置") {
                Toggle("自动解析新文件", isOn: $store.settings.autoParseNewFiles)
                    .toggleStyle(DropToggleStyle())
                if store.isInitialImportWindowFixed {
                    LabeledContent("首次导入范围", value: "最近 \(store.effectiveImportRecentDays) 天")
                    Text(store.initialImportWindowMessage)
                        .font(theme.typography.body(.caption))
                        .foregroundStyle(palette.textSecondary)
                } else {
                    Stepper("首次导入最近 \(store.settings.importRecentDays) 天", value: $store.settings.importRecentDays, in: 1...30)
                }
                Toggle("敏感文件始终询问", isOn: $store.settings.sensitiveAlwaysAsk)
                    .toggleStyle(DropToggleStyle())
            }

            Section("目录设置") {
                ForEach(store.settings.watchDirectories, id: \.self) { directory in
                    HStack {
                        Label(directory, systemImage: "folder")
                            .lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            store.removeDirectory(directory)
                        } label: {
                            Label("移除", systemImage: "minus.circle")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(DropSecondaryButtonStyle())
                    }
                }

                Button {
                    store.chooseDirectory()
                } label: {
                    Label("添加授权目录", systemImage: "folder.badge.plus")
                }
                .buttonStyle(DropSecondaryButtonStyle())

                if !store.planCapabilities.canManageMultipleWatchDirectories {
                    HStack {
                        Text(store.watchDirectoryLimitMessage)
                            .font(theme.typography.body(.caption))
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        Button("查看订阅版") {
                            store.openUpgradePage(trigger: .directoryLimit)
                        }
                        .font(theme.typography.body(.caption))
                        .buttonStyle(DropSecondaryButtonStyle())
                    }
                }
            }

            Section("套餐与额度") {
                LabeledContent("当前套餐", value: store.currentPlanName)
                LabeledContent("解析", value: quotaText(store.quotaSnapshot.parse))
                LabeledContent("问答", value: quotaText(store.quotaSnapshot.chat))
                LabeledContent("高级搜索", value: quotaText(store.quotaSnapshot.search))
                Button {
                    store.openUpgradePage(trigger: .settings)
                } label: {
                    Label("查看订阅版", systemImage: "sparkles.rectangle.stack")
                }
                .buttonStyle(DropPrimaryButtonStyle())
            }

            Section("功能边界") {
                LabeledContent("监听目录", value: store.planCapabilities.canManageMultipleWatchDirectories ? "多目录" : "1 个目录")
                LabeledContent("首次导入", value: "最近 \(store.effectiveImportRecentDays) 天")
                LabeledContent("日历写入", value: store.canUseCalendarWrite ? "已启用" : "免费版不可用")
                if !store.canUseCalendarWrite {
                    HStack {
                        Text(store.calendarWriteDisabledMessage)
                            .font(theme.typography.body(.caption))
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        Button("升级解锁") {
                            store.openUpgradePage(trigger: .calendar)
                        }
                        .font(theme.typography.body(.caption))
                        .buttonStyle(DropSecondaryButtonStyle())
                    }
                }
            }

            Section("后台处理") {
                LabeledContent("解析队列", value: summaryText(store.parseQueueSummary))
                LabeledContent("索引队列", value: summaryText(store.indexQueueSummary))
                if store.hasFailedJobs {
                    Button {
                        Task { await store.retryFailedJobs() }
                    } label: {
                        Label("重试失败任务", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(DropSecondaryButtonStyle())
                }
            }

            Section("RAG") {
                LabeledContent("向量库", value: "zvec")
                LabeledContent("索引目录", value: store.ragStoreURL.path)
                LabeledContent("索引文件数", value: "\(store.ragDiagnostics.indexedFileCount)")
                LabeledContent("Chunk 数", value: "\(store.ragDiagnostics.chunkCount)")
                LabeledContent("活跃修订数", value: "\(store.ragDiagnostics.activeRevisionCount)")
                LabeledContent("索引状态", value: store.ragDiagnostics.emptyIndex ? "空索引" : "已有索引")
                if let error = store.lastRAGErrorMessage, !error.isEmpty {
                    Text(error)
                        .font(theme.typography.body(.caption))
                        .foregroundStyle(palette.danger)
                }
                Button {
                    Task { await store.refreshRAGDiagnostics() }
                } label: {
                    Label("刷新 RAG 诊断", systemImage: "arrow.clockwise")
                }
                .buttonStyle(DropSecondaryButtonStyle())
            }

            Section("Provider") {
                LabeledContent("Provider 状态", value: store.providerStatus.headline)
                if let detail = store.providerStatus.detail {
                    Text(detail)
                        .font(theme.typography.body(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
                LabeledContent("配置来源", value: store.providerConfigurationSource.rawValue)
                LabeledContent("配置文件", value: store.providerConfigURL.path)
                HStack {
                    Text("环境变量：DASHSCOPE_API_KEY")
                        .font(theme.typography.body(.caption))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Button("打开配置位置") {
                        store.openProviderConfigLocation()
                    }
                    .font(theme.typography.body(.caption))
                    .buttonStyle(DropSecondaryButtonStyle())
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("设置")
        .task {
            await store.refreshRAGDiagnostics()
        }
        .onChange(of: store.settings) { _, _ in
            store.persistSettings()
        }
    }

    private func quotaText(_ counter: QuotaCounter) -> String {
        "已用 \(counter.used) / 上限 \(counter.limit) / 剩余 \(counter.remaining)"
    }

    private func summaryText(_ summary: ProcessingQueueSummary) -> String {
        "排队 \(summary.queued) / 运行 \(summary.running) / 失败 \(summary.failed)"
    }
}
