import Foundation
#if canImport(XCTest)
import XCTest
#if canImport(SwiftUI)
import SwiftUI
#if canImport(DropKnow)
@testable import DropKnow
#endif

final class UISmokeTests: XCTestCase {
    @MainActor
    func testScenesCanBeInstantiated() {
        let container = DropKnowV1Container()
        let appModel = DropKnowAppModel(container: container)
        _ = MenuBarSceneView(container: container)
        _ = QuickPanelSceneView(container: container)
        _ = SettingsSceneView(model: appModel)
        _ = DocumentDetailSceneView(document_id: "doc_fake", container: container)
        XCTAssertTrue(true)
    }
}
#endif
#endif
