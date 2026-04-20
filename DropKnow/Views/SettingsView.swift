import SwiftUI

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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前行为：不做静默自动入历。")
                        Text("如遇权限缺失或不可入历，将在详情页给出可解释状态。")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                sectionCard(title: "订阅与配额", subtitle: "展示当前能力边界") {
                    VStack(alignment: .leading, spacing: 8) {
                        QuotaBadge(label: "解析额度", used: 3, limit: 20)
                        QuotaBadge(label: "问答额度", used: 0, limit: 10)
                        Text("免费版默认限制高级问答与部分自动化能力。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

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
