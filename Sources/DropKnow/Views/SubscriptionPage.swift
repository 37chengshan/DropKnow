import SwiftUI

struct SubscriptionPage: View {
    @EnvironmentObject private var store: AppStore

    private var trigger: UpgradeTrigger {
        store.activeUpgradeTrigger ?? .settings
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeaderStrip(
                    title: "升级订阅版",
                    subtitle: "把重点文件提醒、DDL/考试日历、搜索问答和多目录监听接成真正的效率闭环"
                )

                ValueHighlightCard(trigger: trigger)

                DetailSection(title: "为什么升级", systemImage: "sparkles") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("重点文件更容易被看到，减少错过通知和 DDL 的风险", systemImage: "checkmark.circle.fill")
                        Label("高置信度时间可直接写入系统日历，形成从下载到行动的闭环", systemImage: "calendar.badge.plus")
                        Label("更高的问答与搜索额度，适合频繁回查要求、时间和证据来源", systemImage: "magnifyingglass")
                        Label("支持更多目录监听，适合 Downloads 之外还有课程/实习/竞赛资料目录的场景", systemImage: "folder.badge.plus")
                    }
                    .font(.callout)
                }

                PlanComparisonCard(store: store)

                DetailSection(title: "升级入口", systemImage: "arrow.up.forward.app") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("当前先提供订阅介绍和升级 CTA，真实购买闭环会在后续版本接入。")
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button {
                                store.openUpgradeCTA()
                            } label: {
                                Label("立即升级", systemImage: "arrow.up.forward.app.fill")
                            }
                            .dropProminentActionStyle()

                            Text("如果购买页尚未开放，按钮会先跳转到升级说明入口。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }
}

private struct ValueHighlightCard: View {
    var trigger: UpgradeTrigger

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(trigger.title)
                .font(.title3.weight(.semibold))
            Text(trigger.summary)
                .foregroundStyle(.secondary)
            StatusPill(text: "订阅版价值闭环", systemImage: "bolt.fill", prominent: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dropGlass(cornerRadius: 18)
    }
}

private struct PlanComparisonCard: View {
    @ObservedObject var store: AppStore

    var body: some View {
        DetailSection(title: "权益对比", systemImage: "rectangle.split.2x1") {
            VStack(spacing: 10) {
                planRow(
                    title: "监听目录",
                    free: "1 个目录",
                    pro: "Downloads + 更多自定义目录"
                )
                planRow(
                    title: "解析额度",
                    free: "\(store.quotaSnapshot.parse.limit) / 天",
                    pro: "更高额度"
                )
                planRow(
                    title: "问答额度",
                    free: "\(store.quotaSnapshot.chat.limit) / 天",
                    pro: "更高额度"
                )
                planRow(
                    title: "高级搜索",
                    free: "\(store.quotaSnapshot.search.limit) / 天",
                    pro: "更高额度"
                )
                planRow(
                    title: "日历能力",
                    free: "仅展示候选",
                    pro: "高置信度候选可加入系统日历"
                )
            }
        }
    }

    private func planRow(title: String, free: String, pro: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .frame(width: 90, alignment: .leading)
                .font(.callout.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                Label("免费版：\(free)", systemImage: "circle")
                    .foregroundStyle(.secondary)
                Label("订阅版：\(pro)", systemImage: "checkmark.circle.fill")
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .dropInsetMaterial(cornerRadius: 12)
    }
}
