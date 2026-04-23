import SwiftUI

public struct QuickPanelSceneView: View {
    @State private var query: String = ""
    @State private var viewModel: SearchViewModel
    @FocusState private var isInputFocused: Bool
    @State private var selectedIndex: Int?

    public init(container: DropKnowV1Container = DropKnowV1Container()) {
        _viewModel = State(initialValue: container.makeSearchViewModel())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.comfortable) {
            searchBar
            modePicker
            contentArea
            bottomContextBar
        }
        .padding(DesignSpacing.spacious)
        .frame(minWidth: 540, minHeight: 380)
        .onAppear {
            isInputFocused = true
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: DesignSpacing.standard) {
            TextField("输入问题，例如：这周有什么截止时间？", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)

            Button("执行") {
                submitQuery()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)

            Button("清空") {
                query = ""
                viewModel.reset()
                selectedIndex = nil
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("模式", selection: $viewModel.mode) {
            Text("搜索").tag(QuickMode.search)
            Text("问答").tag(QuickMode.qa)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        Group {
            switch viewModel.state {
            case .idle(let suggestions):
                suggestionsList(suggestions)
            case .retrieving:
                feedbackView(.loading(icon: "arrow.clockwise", message: "正在召回本地证据..."))
            case .assembling:
                feedbackView(.loading(icon: "arrow.clockwise", message: "正在组装搜索结果..."))
            case .answering:
                feedbackView(.loading(icon: "arrow.clockwise", message: "正在生成回答..."))
            case .searchResults(let items):
                searchResultList(items)
            case .answer(let data):
                answerResultView(data)
            case .noResult(let message):
                feedbackView(.noResult(message: message, suggestions: viewModel.suggestions))
            case .blocked(let reason, let message):
                feedbackView(.blocked(reason: reason, message: message))
            case .failed(let message):
                feedbackView(.failed(message: message, canRetry: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Suggestions List

    private func suggestionsList(_ suggestions: [String]) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.standard) {
            Text("推荐问题")
                .font(DesignTypography.caption)
                .foregroundStyle(.secondary)
                .help("使用 ↑↓ 键选择，回车确认")

            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                SuggestionRow(
                    text: suggestion,
                    isSelected: selectedIndex == index
                ) {
                    selectSuggestion(suggestion)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectSuggestion(suggestion)
                }
            }
        }
    }

    // MARK: - Search Results

    private func searchResultList(_ items: [SearchSnapshot.SearchResultItem]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignSpacing.standard) {
                ForEach(items, id: \.document_id) { item in
                    SearchResultCard(item: item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Answer Result

    private func answerResultView(_ data: SearchViewModel.AnswerData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.spacious) {
                AnswerCard(answer: data.answer)

                if !data.citations.isEmpty {
                    CitationsSection(citations: data.citations)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Feedback View

    private func feedbackView(_ type: FeedbackType) -> some View {
        VStack(spacing: DesignSpacing.comfortable) {
            if type.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else {
                Image(systemName: type.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(type.iconColor)
            }

            Text(type.title)
                .font(DesignTypography.cardTitle)

            Text(type.message)
                .font(DesignTypography.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let button = type.actionButton {
                button
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(DesignSpacing.extraSpacious)
    }

    // MARK: - Bottom Context Bar

    private var bottomContextBar: some View {
        HStack {
            Text("模式：\(viewModel.mode == .search ? "搜索" : "问答")")
                .font(DesignTypography.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(bottomStatusText)
                .font(DesignTypography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, DesignSpacing.tight)
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
        case .searchResults(let items):
            return "已返回 \(items.count) 条搜索结果"
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

    // MARK: - Actions

    private func submitQuery() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        selectedIndex = nil
        Task {
            await viewModel.run(query)
        }
    }

    private func selectSuggestion(_ suggestion: String) {
        query = suggestion
        Task {
            await viewModel.useSuggestion(suggestion)
        }
    }

    private func moveSelectionUp() {
        let count = viewModel.suggestions.count
        guard count > 0 else { return }
        if selectedIndex == nil {
            selectedIndex = count - 1
        } else {
            selectedIndex = (selectedIndex! - 1 + count) % count
        }
        isInputFocused = false
    }

    private func moveSelectionDown() {
        let count = viewModel.suggestions.count
        guard count > 0 else { return }
        if selectedIndex == nil {
            selectedIndex = 0
        } else {
            selectedIndex = (selectedIndex! + 1) % count
        }
        isInputFocused = false
    }

    private func submitCurrentSelection() {
        if let index = selectedIndex, index < viewModel.suggestions.count {
            selectSuggestion(viewModel.suggestions[index])
        } else {
            submitQuery()
        }
    }
}

// MARK: - Feedback Type

private enum FeedbackType {
    case loading(icon: String, message: String)
    case noResult(message: String, suggestions: [String]?)
    case blocked(reason: SearchBlockReason, message: String)
    case failed(message: String, canRetry: Bool)

    var icon: String {
        switch self {
        case .loading(let icon, _): return icon
        case .noResult: return "magnifyingglass"
        case .blocked: return "lock.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var title: String {
        switch self {
        case .loading: return "处理中"
        case .noResult: return "未找到结果"
        case .blocked: return "当前不可用"
        case .failed: return "执行失败"
        }
    }

    var message: String {
        switch self {
        case .loading(_, let message): return message
        case .noResult(let message, _): return message
        case .blocked(_, let message): return message
        case .failed(let message, _): return message
        }
    }

    var iconColor: Color {
        switch self {
        case .loading: return .secondary
        case .noResult: return .secondary
        case .blocked: return .orange
        case .failed: return .red
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var actionButton: AnyView? {
        switch self {
        case .blocked(let reason, _):
            return AnyView(blockedAction(reason))
        case .failed(_, let canRetry):
            if canRetry {
                return AnyView(Button("重试") { }
                    .buttonStyle(.borderedProminent))
            }
            return nil
        case .noResult(_, let suggestions):
            if let suggestions, !suggestions.isEmpty {
                return AnyView(Button("查看推荐问题") { }
                    .buttonStyle(.bordered))
            }
            return nil
        default:
            return nil
        }
    }

    @ViewBuilder
    private func blockedAction(_ reason: SearchBlockReason) -> some View {
        switch reason {
        case .quota_exceeded:
            Text("今日额度已用尽，请明日重试或升级套餐。")
                .font(DesignTypography.footnote)
                .foregroundStyle(.secondary)
        case .feature_locked:
            Text("该能力仅对订阅版开放。")
                .font(DesignTypography.footnote)
                .foregroundStyle(.secondary)
        case .empty_index:
            Text("请先导入并完成至少一份文件解析。")
                .font(DesignTypography.footnote)
                .foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Suggestion Row

private struct SuggestionRow: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: DesignSpacing.standard) {
            Image(systemName: "sparkles")
                .foregroundStyle(isSelected ? DesignColors.accent : .secondary)
                .font(.system(size: 12))

            Text(text)
                .font(DesignTypography.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)

            if isSelected {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignSpacing.standard)
        .background(
            RoundedRectangle(cornerRadius: DesignCornerRadius.card)
                .fill(isSelected ? DesignColors.accent.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignCornerRadius.card)
                .stroke(isSelected ? DesignColors.accent : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Search Result Card

private struct SearchResultCard: View {
    let item: SearchSnapshot.SearchResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.compact) {
            Text(item.title)
                .font(DesignTypography.cardTitle)

            Text(item.subtitle)
                .font(DesignTypography.cardSubtitle)
                .foregroundStyle(.secondary)

            HStack(spacing: DesignSpacing.tight) {
                Image(systemName: "text.quote")
                    .font(.system(size: 10))
                Text("证据：\(item.evidence)")
                    .font(DesignTypography.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(DesignSpacing.spacious)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignCornerRadius.card)
                .fill(DesignColors.backgroundSecondary)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DesignColors.primary)
                .frame(width: 3)
        }
    }
}

// MARK: - Answer Card

private struct AnswerCard: View {
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.standard) {
            HStack(spacing: DesignSpacing.compact) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignColors.primary)
                Text("回答")
                    .font(DesignTypography.cardTitle)
            }

            Text(answer)
                .font(DesignTypography.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSpacing.spacious)
        .background(
            RoundedRectangle(cornerRadius: DesignCornerRadius.card)
                .fill(DesignColors.backgroundSecondary)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.purple)
                .frame(width: 3)
        }
    }
}

// MARK: - Citations Section

private struct CitationsSection: View {
    let citations: [CitationResponse]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.standard) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                    Text("证据来源 (\(citations.count))")
                        .font(DesignTypography.cardSubtitle)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(Array(citations.enumerated()), id: \.offset) { index, citation in
                    CitationRow(citation: citation, index: index + 1)
                }
            }
        }
        .padding(DesignSpacing.spacious)
        .background(
            RoundedRectangle(cornerRadius: DesignCornerRadius.card)
                .fill(DesignColors.backgroundSecondary)
        )
    }
}

// MARK: - Citation Row

private struct CitationRow: View {
    let citation: CitationResponse
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.tight) {
            HStack(spacing: DesignSpacing.compact) {
                Text("\(index).")
                    .font(DesignTypography.caption)
                    .foregroundStyle(.secondary)
                Text(citation.file_name)
                    .font(DesignTypography.footnote.weight(.semibold))
            }

            Text(citation.evidence_snippet)
                .font(DesignTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, DesignSpacing.compact)
    }
}
