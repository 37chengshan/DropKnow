import SwiftUI

struct DropKnowMainWindowView: View {
    @State private var model: DropKnowAppModel

    init(model: DropKnowAppModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if model.watcherStatusText == "未启动" {
                    ProgressView("正在准备 DropKnow...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TabView {
                        MenuBarSceneView(container: model.container, refreshToken: model.contentRevision)
                            .tabItem {
                                Label("总览", systemImage: "tray.full")
                            }

                        QuickPanelSceneView(container: model.container)
                            .tabItem {
                                Label("搜索", systemImage: "magnifyingglass")
                            }
                    }
                }
            }

            if let banner = model.banner {
                ToastBannerView(
                    title: banner.title,
                    message: banner.message,
                    style: banner.style,
                    onDismiss: { model.closeBanner() }
                )
                .padding(18)
            }
        }
        .task {
            await model.start()
        }
    }
}

#Preview {
    DropKnowMainWindowView(model: DropKnowAppModel(container: DropKnowV1Container()))
}
