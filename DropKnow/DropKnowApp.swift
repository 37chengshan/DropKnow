//
//  DropKnowApp.swift
//  DropKnow
//
//  Created by YuFei Chi on 2026/4/19.
//

import SwiftUI

@main
struct DropKnowApp: App {
    private let container: DropKnowV1Container

    init() {
        container = DropKnowV1Container()
    }

    var body: some Scene {
        WindowGroup("DropKnow") {
            DropKnowMainWindowView(container: container)
        }
        .defaultSize(width: 960, height: 640)

        Window("快速搜索", id: "quick-panel") {
            QuickPanelSceneView(container: container)
        }
        .defaultSize(width: 480, height: 320)
        .windowResizability(.contentSize)

        Settings {
            SettingsSceneView()
        }
    }
}
