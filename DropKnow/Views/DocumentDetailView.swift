import SwiftUI

public struct DocumentDetailView: View {
    @State private var viewModel: DocumentDetailViewModel
    @State private var showRiskSheet: Bool = false

    private let document_id: String

    public init(document_id: String, viewModel: DocumentDetailViewModel) {
        self.document_id = document_id
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        content
            .task {
                await viewModel.load(document_id: document_id)
            }
            .sheet(isPresented: $showRiskSheet) {
                RiskGateSheet(
                    risk_text: "该文档包含敏感信息，请确认后继续处理。",
                    on_confirm: { showRiskSheet = false },
                    on_cancel: { showRiskSheet = false }
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("加载详情...")
        case .empty:
            Text("文档不存在")
        case .processing(let document_id, let file_name):
            processingView(document_id: document_id, file_name: file_name)
        case .partialSuccess(let data, let message):
            detailContent(data: data, inlineNotice: message)
        case .blocked(let reason):
            detailStateScaffold(title: "文档被阻断", message: reason)
        case .failed(let message):
            detailStateScaffold(title: "处理失败", message: message)
        case .waitingUserConfirmation(let data):
            detailContent(data: data, inlineNotice: "需要用户确认后才会继续处理。")
                .onAppear {
                    showRiskSheet = true
                }
        case .ready(let data):
            detailContent(data: data, inlineNotice: nil)
        }
    }

    private func detailStateScaffold(title: String, message: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader(title: "状态说明", subtitle: title)
                inlineBanner(text: message, color: .orange)
                summaryPlaceholder
                actionSection(documentID: document_id, filePath: nil)
                evidencePlaceholder
                eventPlaceholder
            }
            .padding(16)
        }
    }

    private func processingView(document_id: String, file_name: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader(title: file_name, subtitle: "文档详情")
                inlineBanner(text: "文档正在处理中，请稍后刷新查看完整内容。", color: .blue)
                summaryPlaceholder
                actionSection(documentID: document_id, filePath: nil)
                evidencePlaceholder
                eventPlaceholder
            }
            .padding(16)
        }
    }

    private func detailContent(data: DocumentDetailViewModel.DocumentDetailData, inlineNotice: String?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader(title: data.file_name, subtitle: "文档详情")

                if let inlineNotice {
                    inlineBanner(text: inlineNotice, color: .yellow)
                }

                summaryHero(data: data)

                actionSection(documentID: data.document_id, filePath: data.file_path)

                VStack(alignment: .leading, spacing: 8) {
                    Text("证据片段")
                        .font(.headline)
                    EvidenceSnippetList(snippets: data.events.map { $0.evidence_snippet })
                }

                eventSection(data: data)
            }
            .padding(16)
        }
    }

    private func detailHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryHero(data: DocumentDetailViewModel.DocumentDetailData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("一句话摘要")
                .font(.headline)
            SummaryCard(
                file_name: data.file_name,
                summary: data.summary ?? "暂无摘要",
                action_required: data.action_required
            )
        }
    }

    private func actionSection(documentID: String, filePath: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("操作")
                .font(.headline)
            HStack(spacing: 10) {
                Button("刷新详情") {
                    Task {
                        await viewModel.viewDetail(document_id: documentID)
                    }
                }
                .buttonStyle(.bordered)

                Button("打开原文件") {
                    guard let filePath else { return }
                    viewModel.openOriginalFile(path: filePath)
                }
                .buttonStyle(.bordered)

                Button("重新解析") {
                    Task {
                        await viewModel.retryParse(document_id: documentID)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func eventSection(data: DocumentDetailViewModel.DocumentDetailData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("事件候选")
                .font(.headline)

            if data.events.isEmpty {
                Text("未识别到明确事件")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(data.events, id: \.id) { event in
                    VStack(alignment: .leading, spacing: 8) {
                        ImportantEventCard(
                            title: event.title,
                            time_text: event.raw_time_text,
                            file_name: data.file_name,
                            evidence: event.evidence_snippet,
                            high_priority: event.calendar_status == .added
                        )
                        HStack(spacing: 10) {
                            Button("加入日历") {
                                Task {
                                    await viewModel.addToCalendar(event_id: event.id, document_id: data.document_id)
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("忽略") {
                                Task {
                                    await viewModel.ignore(event_id: event.id, document_id: data.document_id)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private func inlineBanner(text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.primary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var summaryPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("一句话摘要")
                .font(.headline)
            Text("当前状态下暂无可展示摘要。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var evidencePlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("证据片段")
                .font(.headline)
            Text("暂无可展示证据。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var eventPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("事件候选")
                .font(.headline)
            Text("当前状态下未提供事件候选。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
