//
//  RootTabView.swift
//  TLingo
//
//  Created by Codex on 2025/10/19.
//

import SwiftUI
import ShareCore
import Combine

struct RootTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: TabItem = .home
    @ObservedObject private var configStore = AppConfigurationStore.shared

    // State for create custom configuration dialog
    @State private var showCreateCustomConfigDialog = false
    @State private var pendingConfigRequest: CreateCustomConfigurationRequest?
    @State private var customConfigName = "My Configuration"

    private var cancellables = Set<AnyCancellable>()

    /// TabItem enum defining all navigation tabs.
    /// Used by both TabView (iPhone) and NavigationSplitView sidebar (iPad/macOS).
    enum TabItem: String, CaseIterable, Identifiable {
        case home
        case actions
        case providers
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home:
                return "Home"
            case .actions:
                return "Actions"
            case .providers:
                return "Providers"
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
            case .providers:
                return "rectangle.connected.to.line.below"
            case .settings:
                return "gearshape.fill"
            }
        }
    }

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

var body: some View {
        // Unified layout for all platforms (iOS 18+, macOS 15+)
        // - iPhone: Bottom tab bar
        // - iPad: Adaptable top tab bar ↔ sidebar
        // - macOS: Always sidebar
        TabView(selection: $selection) {
            Tab(TabItem.home.title, systemImage: TabItem.home.systemImage, value: TabItem.home) {
                tabContent(for: TabItem.home)
            }
            Tab(TabItem.actions.title, systemImage: TabItem.actions.systemImage, value: TabItem.actions) {
                tabContent(for: TabItem.actions)
            }
            Tab(TabItem.providers.title, systemImage: TabItem.providers.systemImage, value: TabItem.providers) {
                tabContent(for: TabItem.providers)
            }
            Tab(TabItem.settings.title, systemImage: TabItem.settings.systemImage, value: TabItem.settings) {
                tabContent(for: TabItem.settings)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if !os(macOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .tint(colors.accent)
        .onReceive(configStore.createCustomConfigurationRequestPublisher) { request in
            handleCreateCustomConfigRequest(request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTargetLanguageSettings)) { _ in
            selection = .settings
        }
        .alert("Create Custom Configuration", isPresented: $showCreateCustomConfigDialog) {
            TextField("Configuration Name", text: $customConfigName)
            Button("Cancel", role: .cancel) {
                pendingConfigRequest?.completion(false)
                pendingConfigRequest = nil
            }
            Button("Create") {
                createCustomConfiguration()
            }
        } message: {
            Text("You're using the default configuration which is read-only. To make changes, create your own configuration.")
        }
    }

    @ViewBuilder
    private func tabContent(for tab: TabItem) -> some View {
        switch tab {
        case .home:
            HomeView(context: nil)
        case .actions:
            ActionsView()
        case .providers:
            ProvidersView()
        case .settings:
            SettingsView()
        }
    }

    private func handleCreateCustomConfigRequest(_ request: CreateCustomConfigurationRequest) {
        pendingConfigRequest = request
        customConfigName = "My Configuration"
        showCreateCustomConfigDialog = true
    }

    private func createCustomConfiguration() {
        let name = customConfigName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? "My Configuration" : name

        if configStore.createCustomConfigurationFromDefault(named: finalName) {
            pendingConfigRequest?.completion(true)
        } else {
            pendingConfigRequest?.completion(false)
        }
        pendingConfigRequest = nil
    }
}


