import SwiftUI

public struct SettingsSceneView: View {
    @State private var model: DropKnowAppModel

    public init(model: DropKnowAppModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        SettingsView(model: model)
            .frame(minWidth: 360, minHeight: 280)
    }
}
