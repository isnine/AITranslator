//
//  RootTabView.swift
//  TLingo
//
//  Created by Codex on 2025/10/19.
//

import ShareCore
import SwiftUI

struct RootTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: TabItem = Self.initialTab
    @ObservedObject private var configStore = AppConfigurationStore.shared

    /// Reads `-SNAPSHOT_TAB <name>` from launch arguments to select a tab at startup.
    private static var initialTab: TabItem {
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
    /// Used by both TabView (iPhone) and NavigationSplitView sidebar (iPad/macOS).
    enum TabItem: String, CaseIterable, Identifiable {
        case home
        case actions
        case models
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home:
                return "Home"
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
            case .actions:
                return "bolt.fill"
            case .models:
                return "cpu"
            case .settings:
                return "gearshape.fill"
            }
        }
    }

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(TabItem.home.title, systemImage: TabItem.home.systemImage, value: TabItem.home) {
                tabContent(for: TabItem.home)
            }
            .accessibilityIdentifier("tab_home")
            Tab(TabItem.actions.title, systemImage: TabItem.actions.systemImage, value: TabItem.actions) {
                tabContent(for: TabItem.actions)
            }
            .accessibilityIdentifier("tab_actions")
            Tab(TabItem.models.title, systemImage: TabItem.models.systemImage, value: TabItem.models) {
                tabContent(for: TabItem.models)
            }
            .accessibilityIdentifier("tab_models")
            Tab(TabItem.settings.title, systemImage: TabItem.settings.systemImage, value: TabItem.settings) {
                tabContent(for: TabItem.settings)
            }
            .accessibilityIdentifier("tab_settings")
        }
        .tabViewStyle(.sidebarAdaptable)
        #if !os(macOS)
            .tabBarMinimizeBehavior(.onScrollDown)
        #endif
            .tint(colors.accent)
            .onReceive(NotificationCenter.default.publisher(for: .openTargetLanguageSettings)) { _ in
                selection = .settings
            }
    }

    @ViewBuilder
    private func tabContent(for tab: TabItem) -> some View {
        switch tab {
        case .home:
            HomeView(context: nil)
        case .actions:
            ActionsView()
        case .models:
            ModelsView()
        case .settings:
            SettingsView()
        }
    }
}
