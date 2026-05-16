import XCTest
@testable import DropKnow

@MainActor
final class AppStoreTests: XCTestCase {
    func testSubmitSearchDebouncesRapidTriggers() async throws {
        let rag = StubRAGService(delayNanoseconds: 0)
        let store = makeStore(rag: rag)
        store.searchQuery = "查文件 考试时间"

        store.submitSearch(debounceNanoseconds: 50_000_000)
        try await Task.sleep(nanoseconds: 10_000_000)
        store.submitSearch(debounceNanoseconds: 50_000_000)
        try await waitUntil(timeoutNanoseconds: 600_000_000) {
            let calls = await rag.searchQueries
            return calls.count == 1 && store.chatMessages.filter { $0.role == .user }.count == 1 && !store.isSearching
        }

        let calls = await rag.searchQueries
        XCTAssertEqual(calls, ["查文件 考试时间"])
        XCTAssertEqual(store.chatMessages.filter { $0.role == .user }.count, 1)
        XCTAssertFalse(store.isSearching)
    }

    func testNewSearchCancelsAndDiscardsInFlightResult() async throws {
        let rag = StubRAGService(delayNanoseconds: 250_000_000)
        let store = makeStore(rag: rag)

        store.searchQuery = "查文件 第一次"
        store.submitSearch(debounceNanoseconds: 0)

        try await waitUntil(timeoutNanoseconds: 600_000_000) {
            store.isSearching
        }

        store.searchQuery = "查文件 第二次"
        store.submitSearch(debounceNanoseconds: 0)
        try await waitUntil(timeoutNanoseconds: 1_500_000_000) {
            store.chatMessages.contains { $0.text == "查文件 第二次" }
                && store.chatMessages.contains { $0.text.contains("answer:查文件 第二次") }
                && !store.chatMessages.contains { $0.text == "查文件 第一次" }
                && !store.chatMessages.contains { $0.text.contains("answer:查文件 第一次") }
                && !store.isSearching
        }

        XCTAssertFalse(store.chatMessages.contains { $0.text == "查文件 第一次" })
        XCTAssertFalse(store.chatMessages.contains { $0.text.contains("answer:查文件 第一次") })
        XCTAssertTrue(store.chatMessages.contains { $0.text == "查文件 第二次" })
        XCTAssertTrue(store.chatMessages.contains { $0.text.contains("answer:查文件 第二次") })
        XCTAssertFalse(store.isSearching)
    }

    func testCancelSearchClearsInFlightUserMessageAndPreventsResult() async throws {
        let rag = StubRAGService(delayNanoseconds: 250_000_000)
        let store = makeStore(rag: rag)

        store.searchQuery = "查文件 取消测试"
        store.submitSearch(debounceNanoseconds: 0)

        for _ in 0..<30 {
            if store.isSearching { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(store.isSearching)
        XCTAssertTrue(store.chatMessages.contains { $0.text == "查文件 取消测试" })

        store.cancelSearch()
        XCTAssertFalse(store.isSearching)
        XCTAssertFalse(store.chatMessages.contains { $0.text == "查文件 取消测试" })

        try await waitUntil(timeoutNanoseconds: 1_200_000_000) {
            !store.chatMessages.contains { $0.text.contains("answer:查文件 取消测试") }
        }
        XCTAssertFalse(store.chatMessages.contains { $0.text.contains("answer:查文件 取消测试") })
    }

    func testFreePlanBlocksSecondWatchDirectoryAndKeepsPersistedSettingsSingleDirectory() throws {
        let workspace = try makeTempDirectory()
        let firstDirectory = workspace.appendingPathComponent("Downloads", isDirectory: true)
        let secondDirectory = workspace.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)

        var settings = DropSettings.defaults()
        settings.currentPlan = "Free"
        settings.watchDirectories = [firstDirectory.path]

        let store = makeStore(settings: settings, environmentBaseURL: workspace)
        let result = store.addWatchDirectoryPath(secondDirectory.path)
        store.persistSettings()

        XCTAssertEqual(result, .blocked(message: store.watchDirectoryLimitMessage))
        XCTAssertEqual(store.settings.watchDirectories, [firstDirectory.path])

        let data = try Data(contentsOf: AppStoreEnvironment.temporary(baseURL: workspace).settingsURL)
        let persisted = try JSONDecoder().decode(DropSettings.self, from: data)
        XCTAssertEqual(persisted.watchDirectories, [firstDirectory.path])
    }

    func testFreePlanBlocksCalendarWritesAtStoreLevel() async {
        let file = makeFile(
            filePath: "/tmp/notice.pdf",
            parsedStatus: .parsed,
            sensitivityStatus: .clear,
            events: [makeEventCandidate()]
        )
        var settings = DropSettings.defaults()
        settings.currentPlan = "Free"

        let store = makeStore(settings: settings, files: [file])
        await store.addEventToCalendar(eventID: file.events[0].id, in: file.id)

        XCTAssertEqual(store.toastMessage, store.calendarWriteDisabledMessage)
        XCTAssertEqual(store.pendingNavigation?.section, .subscription)
        XCTAssertEqual(store.activeUpgradeTrigger, .calendar)
        XCTAssertEqual(store.files.first?.events.first?.calendarStatus, .candidate)
    }

    func testFreePlanInitialImportClampsToSevenDaysAndOnlyEnqueuesRecentFiles() async throws {
        let workspace = try makeTempDirectory()
        let watchDirectory = workspace.appendingPathComponent("Watch", isDirectory: true)
        try FileManager.default.createDirectory(at: watchDirectory, withIntermediateDirectories: true)

        let now = Date()
        let recentFile = watchDirectory.appendingPathComponent("recent.md")
        let oldFile = watchDirectory.appendingPathComponent("old.md")
        try createFile(at: recentFile, modifiedAt: now.addingTimeInterval(-2 * 24 * 3600))
        try createFile(at: oldFile, modifiedAt: now.addingTimeInterval(-9 * 24 * 3600))

        var settings = DropSettings.defaults()
        settings.currentPlan = "Free"
        settings.watchDirectories = [watchDirectory.path]
        settings.importRecentDays = 30

        let store = makeStore(
            settings: settings,
            storedFilesStatus: .missingState,
            environmentBaseURL: workspace,
            sessionStartedAt: now
        )

        XCTAssertEqual(store.effectiveImportRecentDays, 7)
        XCTAssertEqual(store.historicalImportPrompt?.recentDays, 7)
        XCTAssertEqual(store.historicalImportPrompt?.recentCandidateCount, 1)

        await store.importRecentFiles(showToast: false)
        let snapshot = await store.runtimeStateSnapshot()

        XCTAssertEqual(snapshot.parseJobs.count, 1)
        XCTAssertEqual(
            URL(fileURLWithPath: snapshot.parseJobs.first?.filePath ?? "").standardizedFileURL.path,
            recentFile.standardizedFileURL.path
        )
    }

    func testAllowSensitiveFileOnlyApprovesCurrentProcessingAttempt() async {
        let file = makeFile(
            filePath: "/tmp/sensitive/成绩单.pdf",
            parsedStatus: .sensitiveGate,
            sensitivityStatus: .suspected
        )
        let store = makeStore(files: [file])

        await store.allowSensitiveFile(file)
        let snapshot = await store.runtimeStateSnapshot()
        let decision = store.sensitiveRemoteDecision(
            for: file.filePath,
            detectedStatus: .suspected,
            forceAllowSensitive: false
        )

        XCTAssertTrue(store.settings.trustedDirectories.isEmpty)
        XCTAssertEqual(snapshot.parseJobs.count, 1)
        XCTAssertTrue(snapshot.parseJobs.first?.forceAllowSensitive == true)
        XCTAssertEqual(decision, .block(message: store.sensitiveStatusMessage(for: file)))
    }

    func testOneTimeApprovedSensitiveFileRemainsUsableAfterRestore() {
        let approved = makeFile(
            filePath: "/tmp/sensitive/成绩单.pdf",
            parsedStatus: .parsed,
            sensitivityStatus: .approvedOnce,
            snippets: ["身份证号：123456789012345678"]
        )

        let store = makeStore(files: [approved])

        XCTAssertEqual(store.files.first?.parsedStatus, .parsed)
        XCTAssertEqual(store.files.first?.sensitivityStatus, .approvedOnce)
        XCTAssertNotNil(store.files.first?.summary)
        XCTAssertFalse(store.files.first?.snippets.isEmpty ?? true)
    }

    func testProviderStatusBecomesUnavailableWhenRAGUnavailableReasonIsSet() {
        let store = makeStore()
        store.ragUnavailableReason = "Python 环境缺少 zvec：test"

        XCTAssertEqual(store.providerStatus.mode, .unavailable)
        XCTAssertTrue(store.providerStatus.headline.contains("RAG"))
    }

    func testRAGStoreURLUsesInjectedEnvironmentPath() throws {
        let workspace = try makeTempDirectory()
        let environment = AppStoreEnvironment.temporary(baseURL: workspace)
        let store = makeStore(environmentBaseURL: workspace, environment: environment)

        XCTAssertEqual(store.ragStoreURL.standardizedFileURL.path, environment.ragStoreURL.standardizedFileURL.path)
    }

    func testDefaultRAGServiceUsesInjectedEnvironmentPath() throws {
        let workspace = try makeTempDirectory()
        let environment = AppStoreEnvironment.temporary(baseURL: workspace)
        let store = makeStore(environmentBaseURL: workspace, environment: environment, rag: nil)

        XCTAssertEqual(
            store.ragServiceStoreURLForTesting?.standardizedFileURL.path,
            environment.ragStoreURL.standardizedFileURL.path
        )
    }

    func testRebuildSemanticIndexBackfillsLocallyIndexedFileMissingRAGChunks() async throws {
        let workspace = try makeTempDirectory()
        let fileURL = workspace.appendingPathComponent("20250916120002HSTeKa.pdf")
        try createFile(at: fileURL, modifiedAt: Date())
        let file = makeRuntimeIndexedFile(filePath: fileURL.path)
        let rag = StubRAGService(
            delayNanoseconds: 0,
            indexStatuses: [
                RAGIndexFileStatus(
                    fileID: file.id.uuidString,
                    indexed: false,
                    chunkCount: 0,
                    activeRevisionID: file.activeIndexRevision,
                    expectedRevisionID: file.activeIndexRevision
                )
            ]
        )
        let store = makeStore(files: [file], environmentBaseURL: workspace, rag: rag)

        await store.rebuildSemanticIndex()
        let snapshot = await store.runtimeStateSnapshot()

        XCTAssertEqual(snapshot.parseJobs.count, 1)
        XCTAssertEqual(snapshot.parseJobs.first?.fileID, file.id)
        XCTAssertEqual(snapshot.parseJobs.first?.trigger, .manualBackfill)
        XCTAssertEqual(store.toastMessage, "已加入补齐索引队列：1 个文件")
    }

    func testRebuildSemanticIndexSkipsLocallyIndexedFileWhenRAGChunksExist() async throws {
        let workspace = try makeTempDirectory()
        let fileURL = workspace.appendingPathComponent("ready.pdf")
        try createFile(at: fileURL, modifiedAt: Date())
        let file = makeRuntimeIndexedFile(filePath: fileURL.path)
        let rag = StubRAGService(
            delayNanoseconds: 0,
            indexStatuses: [
                RAGIndexFileStatus(
                    fileID: file.id.uuidString,
                    indexed: true,
                    chunkCount: 2,
                    activeRevisionID: file.activeIndexRevision,
                    expectedRevisionID: file.activeIndexRevision
                )
            ]
        )
        let store = makeStore(files: [file], environmentBaseURL: workspace, rag: rag)

        await store.rebuildSemanticIndex()
        let snapshot = await store.runtimeStateSnapshot()

        XCTAssertTrue(snapshot.parseJobs.isEmpty)
        XCTAssertEqual(store.toastMessage, "已加入补齐索引队列：0 个文件")
    }

    func testParseQuotaExhaustionPreventsInitialImportJobs() async throws {
        let workspace = try makeTempDirectory()
        let watchDirectory = workspace.appendingPathComponent("Watch", isDirectory: true)
        try FileManager.default.createDirectory(at: watchDirectory, withIntermediateDirectories: true)
        let recentFile = watchDirectory.appendingPathComponent("recent.md")
        try createFile(at: recentFile, modifiedAt: Date())

        var settings = DropSettings.defaults()
        settings.watchDirectories = [watchDirectory.path]
        settings.dailyParseLimit = 0

        let store = makeStore(
            settings: settings,
            storedFilesStatus: .missingState,
            environmentBaseURL: workspace
        )

        await store.importRecentFiles(showToast: false)
        let snapshot = await store.runtimeStateSnapshot()

        XCTAssertTrue(snapshot.parseJobs.isEmpty)
    }

    func testSearchQuotaExhaustionShowsWarningWithoutRemoteSearch() async {
        var settings = DropSettings.defaults()
        settings.dailySearchLimit = 0
        let store = makeStore(settings: settings, files: [makeFile(filePath: "/tmp/notice.pdf")])
        store.lastRAGErrorMessage = "stale error"
        store.searchQuery = "这份文件有哪些时间节点"

        await store.performSearch()

        XCTAssertEqual(store.searchQuotaWarning, "今日高级搜索额度已用尽")
        XCTAssertEqual(store.searchResult?.engine, "local-fallback")
        XCTAssertEqual(store.searchResult?.queryMode, .localFallback)
        XCTAssertEqual(store.chatMessages.last?.result?.warning, "今日高级搜索额度已用尽")
        XCTAssertEqual(store.chatMessages.last?.result?.queryMode, .localFallback)
        XCTAssertNil(store.lastRAGErrorMessage)
    }

    func testChatQuotaExhaustionReturnsQuotaResultWithoutRemoteChat() async {
        var settings = DropSettings.defaults()
        settings.dailyChatLimit = 0
        let store = makeStore(settings: settings)
        store.searchQuery = "帮我总结一下今天的安排"

        await store.performSearch()

        XCTAssertEqual(store.searchQuotaWarning, "今日问答额度已用尽")
        XCTAssertEqual(store.searchResult?.engine, "quota")
        XCTAssertEqual(store.searchResult?.queryMode, .quotaBlocked)
        XCTAssertEqual(store.chatMessages.last?.result?.warning, "今日问答额度已用尽")
        XCTAssertEqual(store.chatMessages.last?.result?.queryMode, .quotaBlocked)
    }

    func testMissingAPIKeyGenericChatReturnsErrorFallbackQueryMode() async {
        let providerConfig = ProviderConfiguration(apiKey: "", configURL: URL(fileURLWithPath: "/tmp/providers.local.json"))
        let store = makeStore(providerConfigurationLoader: { providerConfig })
        store.lastRAGErrorMessage = "stale error"
        store.searchQuery = "帮我总结一下今天的安排"

        await store.performSearch()

        XCTAssertEqual(store.searchResult?.engine, "local")
        XCTAssertEqual(store.searchResult?.warning, "未配置 API Key")
        XCTAssertEqual(store.searchResult?.queryMode, .errorFallback)
        XCTAssertEqual(store.chatMessages.last?.result?.queryMode, .errorFallback)
        XCTAssertNil(store.lastRAGErrorMessage)
    }

    func testStubRAGChatReturnsGeneralChatQueryMode() async throws {
        let rag = StubRAGService(delayNanoseconds: 0)

        let result = try await rag.chat(query: "帮我总结一下今天的安排")

        XCTAssertEqual(result.queryMode, .generalChat)
    }

    func testFileSearchSuccessKeepsFileSearchQueryModeAndDiagnostics() async {
        let rag = StubRAGService(delayNanoseconds: 0)
        let store = makeStore(files: [makeFile(filePath: "/tmp/notice.pdf")], rag: rag)
        store.searchQuery = "查文件 考试时间"

        await store.performSearch()

        XCTAssertEqual(store.searchResult?.queryMode, .fileSearch)
        XCTAssertEqual(store.searchResult?.diagnostics.topK, 6)
        XCTAssertEqual(store.ragDiagnostics.topK, 6)
        XCTAssertNil(store.lastRAGErrorMessage)
        XCTAssertEqual(store.chatMessages.last?.result?.queryMode, .fileSearch)
    }

    func testFileQuestionWithoutPrefixRoutesToRAGSearch() async throws {
        let rag = StubRAGService(delayNanoseconds: 0)
        let file = makeFile(filePath: "/tmp/schedule/notice.pdf")
        let store = makeStore(files: [file], rag: rag)
        store.searchQuery = "4C 大赛有哪些时间节点"

        await store.performSearch()

        let searchCalls = await rag.searchQueries
        let chatCalls = await rag.chatQueries
        XCTAssertEqual(searchCalls, ["4C 大赛有哪些时间节点"])
        XCTAssertTrue(chatCalls.isEmpty)
        XCTAssertEqual(store.searchResult?.queryMode, .fileSearch)
    }

    func testGenericEnglishMeetingQuestionStaysInChatRoute() async throws {
        let rag = StubRAGService(delayNanoseconds: 0)
        let providerConfig = ProviderConfiguration(apiKey: "test-key", configURL: URL(fileURLWithPath: "/tmp/providers.local.json"))
        let store = makeStore(rag: rag, providerConfigurationLoader: { providerConfig })
        store.searchQuery = "Can we talk about the meeting tomorrow?"

        await store.performSearch()

        let searchCalls = await rag.searchQueries
        let chatCalls = await rag.chatQueries
        XCTAssertTrue(searchCalls.isEmpty)
        XCTAssertEqual(chatCalls, ["Can we talk about the meeting tomorrow?"])
        XCTAssertEqual(store.searchResult?.queryMode, .generalChat)
    }

    func testBindFileIDsByStandardizedPathWhenHitOmitsUUID() async {
        let file = makeFile(filePath: "/tmp/../tmp/course/notice.pdf")
        let hit = SearchHit(
            id: "hit-1",
            fileID: nil,
            fileName: file.fileName,
            filePath: "/tmp/course/./notice.pdf",
            snippet: "时间线索",
            score: 0.91
        )
        let rag = StubRAGService(delayNanoseconds: 0, forcedSearchResult: SearchResult(
            answer: "answer",
            hits: [hit],
            engine: "stub",
            warning: nil,
            queryMode: .fileSearch
        ))
        let store = makeStore(files: [file], rag: rag)
        store.searchQuery = "帮我找这份通知的时间安排"

        await store.performSearch()

        XCTAssertEqual(store.searchResult?.hits.count, 1)
        XCTAssertEqual(store.searchResult?.hits.first?.fileID, file.id)
    }

    func testBindFileIDsDeduplicatesResolvedHitsForSameFile() async {
        let file = makeFile(filePath: "/tmp/course/notice.pdf")
        let duplicatedHits = [
            SearchHit(
                id: "hit-1",
                fileID: nil,
                fileName: file.fileName,
                filePath: "/tmp/course/./notice.pdf",
                snippet: "第一段",
                score: 0.95
            ),
            SearchHit(
                id: "hit-2",
                fileID: nil,
                fileName: file.fileName,
                filePath: "/tmp/../tmp/course/notice.pdf",
                snippet: "第二段",
                score: 0.92
            )
        ]
        let rag = StubRAGService(delayNanoseconds: 0, forcedSearchResult: SearchResult(
            answer: "answer",
            hits: duplicatedHits,
            engine: "stub",
            warning: nil,
            queryMode: .fileSearch
        ))
        let store = makeStore(files: [file], rag: rag)
        store.searchQuery = "这份文件的证据"

        await store.performSearch()

        XCTAssertEqual(store.searchResult?.hits.count, 1)
        XCTAssertEqual(store.searchResult?.hits.first?.fileID, file.id)
    }

    func testNavigateToSearchHitFocusesSnippets() async {
        let file = makeFile(filePath: "/tmp/course/notice.pdf")
        let hit = SearchHit(
            id: "hit-1",
            fileID: nil,
            fileName: file.fileName,
            filePath: "/tmp/course/./notice.pdf",
            snippet: "证据片段",
            score: 0.88,
            chunkIndex: 0,
            revisionID: "rev-hit"
        )
        let store = makeStore(files: [file])

        let didNavigate = store.navigateToSearchHit(hit)

        XCTAssertTrue(didNavigate)
        XCTAssertEqual(store.selectedFileID, file.id)
        XCTAssertEqual(store.pendingNavigation?.section, .recent)
        XCTAssertEqual(store.detailFocusRequest?.anchor, .snippets)
        XCTAssertEqual(store.detailFocusRequest?.evidenceSnippet, "证据片段")
        XCTAssertEqual(store.detailFocusRequest?.chunkIndex, 0)
        XCTAssertEqual(store.detailFocusRequest?.revisionID, "rev-hit")
    }

    func testNavigateToSearchHitResolvesByFilePathWhenIDMissing() {
        let file = makeFile(filePath: "/tmp/path-fallback.txt")
        let store = makeStore(files: [file])
        let hit = SearchHit(id: "chunk-1", fileID: nil, fileName: file.fileName, filePath: file.filePath, snippet: "证据", score: 0.7)

        let didNavigate = store.navigateToSearchHit(hit)

        XCTAssertTrue(didNavigate)
        XCTAssertEqual(store.selectedFileID, file.id)
        XCTAssertEqual(store.detailFocusRequest?.anchor, .snippets)
    }

    func testNavigateToSearchHitShowsToastWhenFileMissing() async {
        let hit = SearchHit(
            id: "missing",
            fileID: nil,
            fileName: "missing.pdf",
            filePath: "/tmp/missing.pdf",
            snippet: "证据片段",
            score: 0.1
        )
        let store = makeStore(files: [])

        let didNavigate = store.navigateToSearchHit(hit)

        XCTAssertFalse(didNavigate)
        XCTAssertEqual(store.toastMessage, "未找到对应文件，无法定位到该搜索结果。")
        XCTAssertNil(store.selectedFileID)
        XCTAssertNil(store.pendingNavigation)
        XCTAssertNil(store.detailFocusRequest)
    }

    func testRefreshRAGDiagnosticsUpdatesStateAndClearsLastError() async {
        let expected = SearchDiagnostics(
            embeddingEngine: "zvec",
            embeddingModel: "dashscope",
            chatModel: "qwen",
            topK: 6,
            chatUsed: false,
            fallbackReason: nil,
            indexedFileCount: 3,
            chunkCount: 12,
            activeRevisionCount: 3,
            emptyIndex: false,
            providerConfigured: true
        )
        let rag = StubRAGService(delayNanoseconds: 0, diagnosticsResult: .success(expected))
        let store = makeStore(rag: rag)
        store.lastRAGErrorMessage = "old error"

        await store.refreshRAGDiagnostics()

        XCTAssertEqual(store.ragDiagnostics, expected)
        XCTAssertNil(store.lastRAGErrorMessage)
    }

    func testRefreshRAGDiagnosticsStoresErrorMessage() async {
        let rag = StubRAGService(delayNanoseconds: 0, diagnosticsResult: .failure(StubRAGError.diagnosticsFailed))
        let store = makeStore(rag: rag)

        await store.refreshRAGDiagnostics()

        XCTAssertEqual(store.lastRAGErrorMessage, StubRAGError.diagnosticsFailed.localizedDescription)
    }

    func testTrustDirectoryAllowsFutureSensitiveFilesInSameDirectory() async {
        let file = makeFile(
            filePath: "/tmp/trusted/成绩单.pdf",
            parsedStatus: .sensitiveGate,
            sensitivityStatus: .suspected
        )
        let store = makeStore(files: [file])

        await store.trustDirectory(for: file)
        let sameDirectoryPath = "/tmp/trusted/下一份成绩单.pdf"
        let decision = store.sensitiveRemoteDecision(
            for: sameDirectoryPath,
            detectedStatus: .suspected,
            forceAllowSensitive: false
        )

        XCTAssertEqual(store.settings.trustedDirectories, ["/tmp/trusted"])
        XCTAssertEqual(decision, .allow(.trustedDirectory))
    }

    func testImportanceExplanationIncludesHighConfidenceSignals() {
        let file = makeFile(
            filePath: "/tmp/exam.pdf",
            parsedStatus: .parsed,
            sensitivityStatus: .clear,
            events: [makeEventCandidate()]
        )
        let store = makeStore(files: [file])

        let explanation = store.importanceExplanation(for: file)

        XCTAssertEqual(explanation?.headline, "为什么这份文件被判重要")
        XCTAssertFalse(explanation?.signals.isEmpty ?? true)
    }

    func testParsedFileNotificationSkipsInitialImportAndLowPriorityFiles() {
        let lowValue = makeFile(filePath: "/tmp/readme.md", priorityLevel: .low, summaryText: "阅读材料")
        let store = makeStore(files: [lowValue])

        XCTAssertNil(store.parsedFileNotification(for: lowValue, trigger: .initialImport))
        XCTAssertNil(store.parsedFileNotification(for: lowValue, trigger: .auto))
    }

    func testParsedFileNotificationForHighConfidenceEventIncludesTimeReason() {
        let file = makeFile(
            filePath: "/tmp/exam.pdf",
            parsedStatus: .parsed,
            sensitivityStatus: .clear,
            events: [makeEventCandidate()]
        )
        let store = makeStore(files: [file])

        let descriptor = store.parsedFileNotification(for: file, trigger: .auto)

        XCTAssertEqual(descriptor?.title, "落知发现关键时间")
        XCTAssertEqual(descriptor?.anchor, .events)
        XCTAssertTrue(descriptor?.body.contains("高置信度时间安排") == true)
    }

    func testOpenUpgradePageRoutesToSubscriptionSection() {
        let store = makeStore()

        store.openUpgradePage(trigger: .calendar)

        XCTAssertEqual(store.activeUpgradeTrigger, .calendar)
        XCTAssertEqual(store.pendingNavigation?.section, .subscription)
    }

    func testNavigateToFileStoresHighlightedReminderEvent() {
        let event = makeEventCandidate()
        let file = makeFile(filePath: "/tmp/exam.pdf", events: [event])
        let store = makeStore(files: [file])

        store.navigateToFile(fileID: file.id, anchor: .calendarReason, eventID: event.id)

        XCTAssertEqual(store.selectedFileID, file.id)
        XCTAssertEqual(store.pendingNavigation?.section, .recent)
        XCTAssertEqual(store.highlightedDetailEventID, event.id)
        XCTAssertEqual(store.detailFocusRequest?.anchor, .calendarReason)
    }

    func testNavigateToFileWithoutEventClearsHighlightedReminderEvent() {
        let event = makeEventCandidate()
        let file = makeFile(filePath: "/tmp/exam.pdf", events: [event])
        let store = makeStore(files: [file])

        store.navigateToFile(fileID: file.id, anchor: .calendarReason, eventID: event.id)
        store.navigateToFile(fileID: file.id, anchor: .summary)

        XCTAssertNil(store.highlightedDetailEventID)
        XCTAssertEqual(store.detailFocusRequest?.anchor, .summary)
    }

    func testCalendarExplanationUsesHighlightedEventWhenProvided() {
        let firstEvent = makeEventCandidate(
            title: "第一次答辩",
            startTime: Date(timeIntervalSince1970: 200),
            evidence: "第一次答辩安排在 5 月 1 日 10:00，地点教室 A",
            confidence: 0.95
        )
        let secondEvent = makeEventCandidate(
            title: "第二次答辩",
            eventType: .meeting,
            startTime: Date(timeIntervalSince1970: 500),
            location: "会议室 B",
            evidence: "第二次答辩安排在 5 月 3 日 15:00，地点会议室 B",
            confidence: 0.88
        )
        let file = makeFile(filePath: "/tmp/schedule.pdf", events: [firstEvent, secondEvent])
        let store = makeStore(files: [file])

        let explanation = store.calendarExplanation(for: file, highlightedEventID: secondEvent.id)

        XCTAssertEqual(explanation?.signals.first?.detail, DateFormatter.dropShort.string(from: secondEvent.startTime!))
        XCTAssertTrue(explanation?.signals.contains(where: { $0.detail.contains("会议通知") }) == true)
        XCTAssertTrue(explanation?.signals.contains(where: { $0.detail.contains("会议室 B") }) == true)
    }

    func testIgnoredSensitiveFileRemainsIgnoredAfterRestore() {
        let ignored = makeFile(
            filePath: "/tmp/private/成绩单.pdf",
            parsedStatus: .ignored,
            sensitivityStatus: .suspected,
            snippets: ["身份证号：123456789012345678"]
        )

        let store = makeStore(files: [ignored])

        XCTAssertEqual(store.files.first?.parsedStatus, .ignored)
        XCTAssertEqual(store.files.first?.sensitivityStatus, .suspected)
    }

    func testIgnoringBlockedSensitiveFileClearsRuntimeBlockedJob() async {
        let file = makeFile(
            filePath: "/tmp/private/成绩单.pdf",
            parsedStatus: .sensitiveGate,
            sensitivityStatus: .suspected
        )
        let blockedJob = ParseJob(
            fileID: file.id,
            fileName: file.fileName,
            filePath: file.filePath,
            trigger: .manualReparse,
            status: .blockedSensitive
        )
        let runtimeState = RuntimeState(
            parseJobs: [blockedJob],
            indexJobs: [],
            dailyUsage: .empty(dayKey: QuotaService.dayKey(for: Date())),
            lastRecoveredAt: nil
        )
        let store = makeStore(files: [file], runtimeState: runtimeState)

        await store.ignoreFile(file)
        let snapshot = await store.runtimeStateSnapshot()

        XCTAssertEqual(store.files.first?.parsedStatus, .ignored)
        XCTAssertTrue(snapshot.parseJobs.isEmpty)
    }

    func testSkippedParseRuntimeRestoresParsedStatus() async throws {
        let workspace = try makeTempDirectory()
        let file = makeFile(filePath: "/tmp/notice.pdf", parsedStatus: .queued, priorityLevel: .low)
        let skippedJob = ParseJob(
            fileID: file.id,
            fileName: file.fileName,
            filePath: file.filePath,
            trigger: .manualReparse,
            status: .skippedUnchanged
        )
        let runtimeState = RuntimeState(
            parseJobs: [skippedJob],
            indexJobs: [],
            dailyUsage: .empty(dayKey: QuotaService.dayKey(for: Date())),
            lastRecoveredAt: nil
        )
        let environment = AppStoreEnvironment.temporary(
            baseURL: workspace,
            startMonitor: false,
            startProcessingOnLaunch: true
        )
        let store = makeStore(
            files: [file],
            runtimeState: runtimeState,
            environmentBaseURL: workspace,
            environment: environment
        )

        for _ in 0..<20 {
            if store.files.first?.parsedStatus == .parsed {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(store.files.first?.parsedStatus, .parsed)
    }

    private func makeStore(
        settings: DropSettings = .defaults(),
        files: [DropFile] = [],
        storedFilesStatus: StoredFilesLoadStatus = .loadedState,
        runtimeState: RuntimeState = .empty,
        environmentBaseURL: URL? = nil,
        environment: AppStoreEnvironment? = nil,
        rag: (any RAGServing)? = nil,
        providerConfigurationLoader: @escaping () -> ProviderConfiguration = { ProviderConfiguration.load() },
        sessionStartedAt: Date = Date()
    ) -> AppStore {
        let baseURL = environmentBaseURL ?? (try! makeTempDirectory())
        let environment = environment ?? AppStoreEnvironment.temporary(baseURL: baseURL)
        return AppStore(
            settings: settings,
            files: files,
            storedFilesStatus: storedFilesStatus,
            runtimeState: runtimeState,
            rag: rag,
            environment: environment,
            providerConfigurationLoader: providerConfigurationLoader,
            sessionStartedAt: sessionStartedAt
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64,
        pollNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
        let didSatisfy = await condition()
        XCTAssertTrue(didSatisfy, "Condition not met before timeout")
    }

    private func makeFile(
        filePath: String,
        parsedStatus: ParseStatus = .parsed,
        sensitivityStatus: SensitivityStatus = .clear,
        events: [EventCandidate] = [],
        snippets: [String] = [],
        priorityLevel: PriorityLevel = .high,
        summaryText: String = "测试摘要"
    ) -> DropFile {
        DropFile(
            fileName: URL(fileURLWithPath: filePath).lastPathComponent,
            filePath: filePath,
            sourceDirectory: URL(fileURLWithPath: filePath).deletingLastPathComponent().path,
            fileKind: .pdf,
            importedAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 100),
            fileSize: 128,
            textLength: 256,
            parsedStatus: parsedStatus,
            sensitivityStatus: sensitivityStatus,
            priorityLevel: priorityLevel,
            summary: FileSummary(
                fileTypeLabel: "通知",
                actionHint: "现在阅读",
                keyTime: nil,
                keyLocation: nil,
                keyPoints: ["测试摘要"],
                oneLineSummary: summaryText
            ),
            events: events,
            snippets: snippets.isEmpty ? ["测试片段"] : snippets,
            errorMessage: nil,
            contentHash: "hash-1",
            fingerprintComputedAt: Date(timeIntervalSince1970: 100),
            parserVersion: "parser-test",
            summaryVersion: "summary-test",
            refineModel: "refine-test",
            embeddingProvider: "dashscope",
            embeddingModel: "embedding-test",
            embeddingDimension: 768,
            indexedContentHash: "hash-1",
            indexedAt: Date(timeIntervalSince1970: 100),
            refinedContentHash: "hash-1",
            refinedAt: Date(timeIntervalSince1970: 100),
            activeIndexRevision: "rev-1"
        )
    }

    private func makeRuntimeIndexedFile(filePath: String) -> DropFile {
        let runtime = ProcessingRuntime.current
        var file = makeFile(filePath: filePath)
        file.parserVersion = runtime.parserVersion
        file.summaryVersion = runtime.summaryVersion
        file.refineModel = runtime.refineModel
        file.embeddingProvider = runtime.embeddingProvider
        file.embeddingModel = runtime.embeddingModel
        file.embeddingDimension = runtime.embeddingDimension
        file.priorityLevel = .normal
        file.refinedContentHash = nil
        file.refinedAt = nil
        return file
    }

    private func makeEventCandidate(
        title: String = "高数考试",
        eventType: EventType = .exam,
        startTime: Date? = Date(timeIntervalSince1970: 200),
        location: String? = "教室 A",
        evidence: String = "高数考试时间为 5 月 1 日 10:00",
        confidence: Double = 0.9
    ) -> EventCandidate {
        EventCandidate(
            eventType: eventType,
            title: title,
            startTime: startTime,
            endTime: nil,
            location: location,
            note: "",
            evidence: evidence,
            confidence: confidence,
            calendarStatus: .candidate
        )
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func createFile(at url: URL, modifiedAt: Date) throws {
        try Data("test".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    }
}

private actor StubRAGService: RAGServing {
    let delayNanoseconds: UInt64
    private(set) var searchQueries: [String] = []
    private(set) var chatQueries: [String] = []
    private let forcedSearchResult: SearchResult?
    private let diagnosticsResult: Result<SearchDiagnostics, Error>
    private let indexStatusesResult: [RAGIndexFileStatus]

    init(
        delayNanoseconds: UInt64,
        forcedSearchResult: SearchResult? = nil,
        diagnosticsResult: Result<SearchDiagnostics, Error> = .success(.empty),
        indexStatuses: [RAGIndexFileStatus] = []
    ) {
        self.delayNanoseconds = delayNanoseconds
        self.forcedSearchResult = forcedSearchResult
        self.diagnosticsResult = diagnosticsResult
        self.indexStatusesResult = indexStatuses
    }

    func indexBatch(files: [RAGBatchIndexFile]) async -> RAGIndexOutcome {
        RAGIndexOutcome(succeeded: true, warning: nil, results: files.map { RAGBatchIndexResult(fileID: $0.fileID, revisionID: $0.revisionID) })
    }

    func indexStatuses(files: [RAGIndexStatusFile]) async throws -> [RAGIndexFileStatus] {
        if !indexStatusesResult.isEmpty {
            return indexStatusesResult
        }
        return files.map {
            RAGIndexFileStatus(
                fileID: $0.fileID,
                indexed: true,
                chunkCount: 1,
                activeRevisionID: $0.expectedRevisionID,
                expectedRevisionID: $0.expectedRevisionID
            )
        }
    }

    func search(query: String, topK: Int) async throws -> SearchResult {
        searchQueries.append(query)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let forcedSearchResult {
            return forcedSearchResult
        }
        return SearchResult(
            answer: "answer:\(query)",
            hits: [],
            engine: "stub",
            warning: nil,
            queryMode: .fileSearch,
            diagnostics: SearchDiagnostics(
                embeddingEngine: "stub",
                embeddingModel: "stub-embedding",
                chatModel: nil,
                topK: topK,
                chatUsed: false,
                fallbackReason: nil,
                indexedFileCount: 1,
                chunkCount: 1,
                activeRevisionCount: 1,
                emptyIndex: false,
                providerConfigured: true
            )
        )
    }

    func chat(query: String) async throws -> SearchResult {
        chatQueries.append(query)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return SearchResult(answer: "answer:\(query)", hits: [], engine: "stub", warning: nil, queryMode: .generalChat)
    }

    func diagnostics() async throws -> SearchDiagnostics {
        switch diagnosticsResult {
        case .success(let diagnostics):
            return diagnostics
        case .failure(let error):
            throw error
        }
    }

    func refine(
        fileName: String,
        text: String,
        summary: FileSummary,
        priority: PriorityLevel,
        events: [EventCandidate]
    ) async -> RAGProcessResponse? {
        nil
    }
}

private enum StubRAGError: LocalizedError {
    case diagnosticsFailed

    var errorDescription: String? {
        switch self {
        case .diagnosticsFailed:
            return "diagnostics failed"
        }
    }
}
