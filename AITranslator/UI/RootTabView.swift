//
//  RootTabView.swift
//  TLingo
//
//  Created by Codex on 2025/10/19.
//

import ShareCore
import SwiftUI

struct RootTabView: View {
    @ObservedObject private var configStore: AppConfigurationStore

    init(configStore: AppConfigurationStore = .shared) {
        self.configStore = configStore
    }

    /// Reads `-SNAPSHOT_TAB <name>` from launch arguments to select a tab at startup.
    static var initialTab: TabItem {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-SNAPSHOT_TAB"),
           idx + 1 < args.count,
           let tab = TabItem(rawValue: args[idx + 1].lowercased())
        {
            return tab
        }
        return .home
    }

    /// TabItem enum defining all navigation tabs.
    /// Used by both TabView (iPhone) and custom sidebar (iPad/macOS).
    enum TabItem: String, CaseIterable, Identifiable {
        case home
        case history
        case actions
        case models
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home:
                return "Home"
            case .history:
                return "History"
            case .actions:
                return "Actions"
            case .models:
                return "Models"
            case .settings:
                return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .home:
                return "house.fill"
            case .history:
                return "clock.arrow.circlepath"
            case .actions:
                return "bolt.fill"
            case .models:
                return "cpu"
            case .settings:
                return "gearshape.fill"
            }
        }
    }

    var body: some View {
        #if os(macOS)
            SidebarLayoutView(initialTab: Self.initialTab, configStore: configStore)
                .modifier(DeepLinkHandler())
        #else
            AdaptiveNavigationView(initialTab: Self.initialTab, configStore: configStore)
                .modifier(DeepLinkHandler())
        #endif
    }
}

// MARK: - Deep Link Handling

extension RootTabView {
    struct DeepLinkHandler: ViewModifier {
        func body(content: Content) -> some View {
            content
                .onOpenURL { url in
                    guard let parsed = DeepLink.parse(url) else { return }
                    var userInfo: [String: Any] = [DeepLink.NotificationKey.text: parsed.text]
                    if let actionName = parsed.actionName {
                        userInfo[DeepLink.NotificationKey.actionName] = actionName
                    }
                    if let configName = parsed.configName {
                        userInfo[DeepLink.NotificationKey.configName] = configName
                    }
                    NotificationCenter.default.post(
                        name: .deepLinkTextReceived,
                        object: nil,
                        userInfo: userInfo
                    )
                }
        }
    }
}

// MARK: - iOS Adaptive Navigation

#if !os(macOS)
    private struct AdaptiveNavigationView: View {
        @Environment(\.horizontalSizeClass) private var sizeClass
        let initialTab: RootTabView.TabItem
        @ObservedObject var configStore: AppConfigurationStore

        var body: some View {
            if sizeClass == .regular {
                SidebarLayoutView(initialTab: initialTab, configStore: configStore)
            } else {
                TabBarView(initialTab: initialTab, configStore: configStore)
            }
        }
    }

    private struct TabBarView: View {
        @Environment(\.colorScheme) private var colorScheme
        @State private var selection: RootTabView.TabItem
        @ObservedObject var configStore: AppConfigurationStore
        @ObservedObject private var preferences = AppPreferences.shared

        init(initialTab: RootTabView.TabItem, configStore: AppConfigurationStore) {
            _selection = State(initialValue: initialTab)
            self.configStore = configStore
        }

        private var colors: AppColorPalette {
            AppColors.Palette(colorScheme: colorScheme, accentTheme: preferences.accentTheme)
        }

        var body: some View {
            TabView(selection: $selection) {
                Tab(
                    RootTabView.TabItem.home.title,
                    systemImage: RootTabView.TabItem.home.systemImage,
                    value: RootTabView.TabItem.home
                ) {
                    HomeView(context: nil)
                }
                .accessibilityIdentifier("tab_home")
                Tab(
                    RootTabView.TabItem.history.title,
                    systemImage: RootTabView.TabItem.history.systemImage,
                    value: RootTabView.TabItem.history
                ) {
                    HistoryView()
                }
                .accessibilityIdentifier("tab_history")
                Tab(
                    RootTabView.TabItem.actions.title,
                    systemImage: RootTabView.TabItem.actions.systemImage,
                    value: RootTabView.TabItem.actions
                ) {
                    ActionsView(configurationStore: configStore)
                }
                .accessibilityIdentifier("tab_actions")
                Tab(
                    RootTabView.TabItem.models.title,
                    systemImage: RootTabView.TabItem.models.systemImage,
                    value: RootTabView.TabItem.models
                ) {
                    ModelsView()
                }
                .accessibilityIdentifier("tab_models")
                Tab(
                    RootTabView.TabItem.settings.title,
                    systemImage: RootTabView.TabItem.settings.systemImage,
                    value: RootTabView.TabItem.settings
                ) {
                    SettingsView(configStore: configStore)
                }
                .accessibilityIdentifier("tab_settings")
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tint(colors.accent)
        }
    }
#endif
