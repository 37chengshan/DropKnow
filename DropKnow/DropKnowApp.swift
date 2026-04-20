//
//  DropKnowApp.swift
//  DropKnow
//
//  Created by YuFei Chi on 2026/4/19.
//

import SwiftUI

#if !SWIFT_PACKAGE
@main
#endif
struct DropKnowApp: App {
    private let container: DropKnowV1Container
    @State private var appModel: DropKnowAppModel

    init() {
        let container = DropKnowV1Container()
        self.container = container
        _appModel = State(initialValue: DropKnowAppModel(container: container))
    }

    var body: some Scene {
        WindowGroup("DropKnow") {
            DropKnowMainWindowView(model: appModel)
        }
        .defaultSize(width: 960, height: 640)

        Window("快速搜索", id: "quick-panel") {
            QuickPanelSceneView(container: container)
        }
        .defaultSize(width: 480, height: 320)
        .windowResizability(.contentSize)

        Settings {
            SettingsSceneView(model: appModel)
        }
    }
}
