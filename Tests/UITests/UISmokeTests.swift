import Foundation
#if canImport(XCTest)
import XCTest
#if canImport(SwiftUI)
import SwiftUI
#if canImport(DropKnow)
@testable import DropKnow
#endif

final class UISmokeTests: XCTestCase {
    func testScenesCanBeInstantiated() {
        let container = DropKnowV1Container()
        _ = MenuBarSceneView(container: container)
        _ = QuickPanelSceneView(container: container)
        _ = SettingsSceneView()
        _ = DocumentDetailSceneView(document_id: "doc_fake", container: container)
        XCTAssertTrue(true)
    }
}
#endif
#endif
