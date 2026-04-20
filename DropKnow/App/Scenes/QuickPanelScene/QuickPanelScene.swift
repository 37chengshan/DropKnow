import SwiftUI

public struct QuickPanelSceneView: View {
    @State private var query: String = ""
    @State private var viewModel: SearchViewModel

    public init(container: DropKnowV1Container = DropKnowV1Container()) {
        _viewModel = State(initialValue: container.makeSearchViewModel())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("输入问题，例如：这周有什么截止时间？", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submitQuery()
                    }

                Button("执行") {
                    submitQuery()
                }
                .buttonStyle(.borderedProminent)

                Button("清空") {
                    query = ""
                    viewModel.reset()
                }
                .buttonStyle(.bordered)
            }

            Picker("模式", selection: $viewModel.mode) {
                Text("搜索").tag(QuickMode.search)
                Text("问答").tag(QuickMode.qa)
            }
            .pickerStyle(.segmented)

            Group {
                switch viewModel.state {
                case .idle(let suggestions):
                    suggestionsList(suggestions)
                case .retrieving:
                    loadingView("正在召回本地证据...")
                case .assembling:
                    loadingView("正在组装搜索结果...")
                case .answering:
                    loadingView("正在生成回答...")
                case .searchResults(let items):
                    searchResultList(items)
                case .answer(let data):
                    answerResultView(data)
                case .noResult(let message):
                    infoStateView(title: "未找到结果", message: message)
                case .blocked(let reason, let message):
                    blockedStateView(reason: reason, message: message)
                case .failed(let message):
                    infoStateView(title: "执行失败", message: message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            bottomContextBar
        }
        .padding(12)
        .frame(minWidth: 540, minHeight: 380)
    }

    private func submitQuery() {
        Task {
            await viewModel.run(query)
        }
    }

    private func suggestionsList(_ suggestions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("推荐问题")
                .font(.headline)
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    query = suggestion
                    Task {
                        await viewModel.useSuggestion(suggestion)
                    }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.secondary)
                        Text(suggestion)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadingView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func searchResultList(_ items: [SearchSnapshot.SearchResultItem]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.document_id) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.subtitle)
                            .font(.subheadline)
                        Text("证据：\(item.evidence)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func answerResultView(_ data: SearchViewModel.AnswerData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("回答")
                    .font(.headline)
                Text(data.answer)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !data.citations.isEmpty {
                    Divider()
                    Text("证据来源")
                        .font(.subheadline)
                    ForEach(Array(data.citations.enumerated()), id: \.offset) { _, citation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(citation.file_name)
                                .font(.footnote.weight(.semibold))
                            Text(citation.evidence_snippet)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func infoStateView(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func blockedStateView(reason: SearchBlockReason, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前不可用")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)

            switch reason {
            case .quota_exceeded:
                Text("今日额度已用尽，请明日重试或升级套餐。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .feature_locked:
                Text("该能力仅对订阅版开放。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .empty_index:
                Text("请先导入并完成至少一份文件解析。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .none:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var bottomContextBar: some View {
        HStack {
            Text("模式：\(viewModel.mode == .search ? "搜索" : "问答")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(bottomStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var bottomStatusText: String {
        switch viewModel.state {
        case .idle:
            return "等待输入"
        case .retrieving:
            return "检索中"
        case .assembling:
            return "组装中"
        case .answering:
            return "回答中"
        case .searchResults:
            return "已返回搜索结果"
        case .answer:
            return "已生成回答"
        case .noResult:
            return "无结果"
        case .blocked:
            return "受限"
        case .failed:
            return "失败"
        }
    }
}
