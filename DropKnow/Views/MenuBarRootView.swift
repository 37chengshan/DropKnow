import SwiftUI

public struct MenuBarRootView: View {
    private let container: DropKnowV1Container

    public init(container: DropKnowV1Container = DropKnowV1Container()) {
        self.container = container
    }

    public var body: some View {
        MenuBarSceneView(container: container)
    }
}
