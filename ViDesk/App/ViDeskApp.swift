import SwiftUI
import SwiftData
#if os(visionOS)
import RealityKit
#endif

/// ViDesk 应用入口
@main
struct ViDeskApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: ConnectionConfig.self)

        #if os(visionOS)
        // VisionOS 特有的 ImmersiveSpace (如果需要沉浸式体验)
        ImmersiveSpace(id: "ImmersiveDesktop") {
            ImmersiveDesktopView()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        #endif
    }
}

#if os(visionOS)
/// 沉浸式桌面视图 (VisionOS)
struct ImmersiveDesktopView: View {
    var body: some View {
        RealityView { content in
            // TODO: 实现 3D 远程桌面体验
        }
    }
}
#endif
