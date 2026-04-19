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
        case .processing:
            Text("处理中...")
        case .blocked(let reason):
            VStack(alignment: .leading, spacing: 12) {
                Text("文档被阻断")
                    .font(.headline)
                Text(reason)
                    .foregroundStyle(.secondary)
                Button("重新解析") {
                    Task {
                        await viewModel.retryParse(document_id: document_id)
                    }
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Text("处理失败")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                Button("重新解析") {
                    Task {
                        await viewModel.retryParse(document_id: document_id)
                    }
                }
            }
        case .waitingUserConfirmation(let data):
            detailContent(data: data)
                .onAppear {
                    showRiskSheet = true
                }
        case .ready(let data):
            detailContent(data: data)
        }
    }

    private func detailContent(data: DocumentDetailViewModel.DocumentDetailData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SummaryCard(
                    file_name: data.file_name,
                    summary: data.summary ?? "暂无摘要",
                    action_required: data.action_required
                )

                EvidenceSnippetList(snippets: data.events.map { $0.evidence_snippet })

                HStack(spacing: 10) {
                    Button("查看详情") {
                        Task {
                            await viewModel.viewDetail(document_id: data.document_id)
                        }
                    }
                    Button("打开原文件") {
                        viewModel.openOriginalFile(path: data.file_path)
                    }
                    Button("重新解析") {
                        Task {
                            await viewModel.retryParse(document_id: data.document_id)
                        }
                    }
                }

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
                            Button("忽略") {
                                Task {
                                    await viewModel.ignore(event_id: event.id, document_id: data.document_id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
