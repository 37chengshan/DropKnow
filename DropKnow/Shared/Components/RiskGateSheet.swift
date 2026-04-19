import SwiftUI

public struct RiskGateSheet: View {
    public let risk_text: String
    public let on_confirm: () -> Void
    public let on_cancel: () -> Void

    public init(risk_text: String, on_confirm: @escaping () -> Void, on_cancel: @escaping () -> Void) {
        self.risk_text = risk_text
        self.on_confirm = on_confirm
        self.on_cancel = on_cancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("隐私风险提示")
                .font(.title3)
                .bold()
            Text(risk_text)
                .font(.body)
            HStack {
                Button("忽略") { on_cancel() }
                Button("继续") { on_confirm() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 320)
    }
}
