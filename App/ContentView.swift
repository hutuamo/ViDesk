import SwiftUI

/// 主内容视图
struct ContentView: View {
    @State private var selectedTab: Tab = .connections
    @State private var activeSession: ActiveSession?
    @State private var navigationPath = NavigationPath()

    enum Tab {
        case connections
        case settings
    }

    struct ActiveSession: Identifiable {
        let id = UUID()
        let config: ConnectionConfig
        let password: String?
    }

    var body: some View {
        Group {
            if let session = activeSession {
                // 远程桌面会话
                RemoteDesktopView(config: session.config, password: session.password)
                    .transition(.opacity)
                    .id(session.id)
            } else {
                // 主界面
                mainView
            }
        }
        .animation(.easeInOut, value: activeSession?.id)
    }

    @ViewBuilder
    private var mainView: some View {
        #if os(visionOS)
        // VisionOS: 使用 TabView with Ornament
        TabView(selection: $selectedTab) {
            connectionsTab
                .tabItem {
                    Label("连接", systemImage: "desktopcomputer")
                }
                .tag(Tab.connections)

            settingsTab
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
                .tag(Tab.settings)
        }
        #else
        // iOS: 使用 TabView
        TabView(selection: $selectedTab) {
            connectionsTab
                .tabItem {
                    Label("连接", systemImage: "desktopcomputer")
                }
                .tag(Tab.connections)

            settingsTab
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
                .tag(Tab.settings)
        }
        #endif
    }

    private var connectionsTab: some View {
        ConnectionListView { config, password in
            startSession(config: config, password: password)
        }
    }

    private var settingsTab: some View {
        SettingsView()
    }

    private func startSession(config: ConnectionConfig, password: String?) {
        activeSession = ActiveSession(config: config, password: password)
    }

    private func endSession() {
        activeSession = nil
    }
}

// MARK: - VisionOS 窗口样式扩展

#if os(visionOS)
extension ContentView {
    /// 获取沉浸式空间 ID
    static let immersiveSpaceId = "ImmersiveDesktop"
}
#endif

#Preview {
    ContentView()
}
