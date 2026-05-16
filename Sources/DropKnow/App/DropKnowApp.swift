import SwiftUI

@main
struct DropKnowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("落知", id: "main") {
            ContentView()
                .dropTheme(.anthropic)
                .environmentObject(store)
                .frame(minWidth: 1040, minHeight: 720)
        }
        .defaultSize(width: 1280, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("导入最近 7 天文件") {
                    Task { await store.importRecentFiles(showToast: true) }
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("重新解析所选文件") {
                    Task { await store.reparseSelection() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("补齐缺失索引") {
                    Task { await store.rebuildSemanticIndex() }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("落知", systemImage: "tray.and.arrow.down.fill") {
            MenuBarPanel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .dropTheme(.anthropic)
                .environmentObject(store)
                .frame(width: 640, height: 520)
        }
    }
}
