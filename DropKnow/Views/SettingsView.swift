import SwiftUI

public struct SettingsView: View {
    @State private var parseUsed: Int = 3
    @State private var parseLimit: Int = 20

    public init() {}

    public var body: some View {
        Form {
            Section("额度") {
                QuotaBadge(label: "解析额度", used: parseUsed, limit: parseLimit)
            }

            Section("监听") {
                Text("当前为 V1 骨架，支持 Downloads 与一个自定义目录。")
            }

            Section("Provider") {
                Text("当前使用 mock provider，可在后续阶段接入真实配置。")
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}
