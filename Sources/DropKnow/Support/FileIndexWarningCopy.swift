enum FileIndexWarningCopy {
    static func message(for file: DropFile) -> String? {
        switch file.ragIndexState {
        case .stale:
            return "文件内容已变化，当前搜索可能仍基于旧版本；重建完成前请先核验原文件。"
        case .failed:
            if file.hasIndexedSnapshot {
                if file.indexedSnapshotMatchesCurrentContent {
                    return "最近一次更新未完成，当前搜索结果可能不完整；请先核验原文件。"
                }
                return "最近一次更新未完成，当前搜索仍可能停留在旧版本；请先核验原文件。"
            }
            return "最近一次处理未完成，当前无法用于完整检索；可重试失败任务或先打开原文件核验。"
        default:
            return nil
        }
    }
}
