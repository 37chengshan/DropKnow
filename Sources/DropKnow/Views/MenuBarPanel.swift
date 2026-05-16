import SwiftUI

struct MenuBarPanel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("落知")
                .font(.headline)

            if let file = store.files.first {
                Button {
                    store.selectedFileID = file.id
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label(file.fileName, systemImage: file.fileKind.systemImage)
                }
            } else {
                Text("暂无最近文件")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("最近下载", systemImage: "tray.full")
            }

            Button {
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("重要提醒", systemImage: "bell.badge")
            }

            Button {
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("AI 问答", systemImage: "bubble.left.and.text.bubble.right")
            }

            Divider()

            Button {
                store.chooseDirectory()
            } label: {
                Label("授权目录", systemImage: "folder.badge.plus")
            }

            Button {
                Task { await store.importRecentFiles(showToast: true) }
            } label: {
                Label("导入最近 7 天", systemImage: "arrow.clockwise")
            }

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 280, alignment: .leading)
    }
}
