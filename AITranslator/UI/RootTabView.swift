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
    @State private var selection: Tab = .home
    @ObservedObject private var configStore = AppConfigurationStore.shared

    // State for create custom configuration dialog
    @State private var showCreateCustomConfigDialog = false
    @State private var pendingConfigRequest: CreateCustomConfigurationRequest?
    @State private var customConfigName = "My Configuration"

    private var cancellables = Set<AnyCancellable>()

    private enum Tab: String, CaseIterable, Identifiable {
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

#if os(macOS)
    private var sidebarSelectionBinding: Binding<Tab?> {
        Binding<Tab?>(
            get: { selection },
            set: { newValue in
                if let newValue {
                    selection = newValue
                }
            }
        )
    }
#endif

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(Tab.allCases, selection: sidebarSelectionBinding) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
        } detail: {
            tabContent(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(colors.background.ignoresSafeArea())
                .navigationTitle(selection.title)
        }
        .tint(colors.accent)
        .onReceive(configStore.createCustomConfigurationRequestPublisher) { request in
            handleCreateCustomConfigRequest(request)
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
        #else
        TabView(selection: $selection) {
            tabContent(for: .home)
                .tabItem {
                    Image(systemName: Tab.home.systemImage)
                    Text(Tab.home.title)
                }
                .tag(Tab.home)

            tabContent(for: .actions)
                .tabItem {
                    Image(systemName: Tab.actions.systemImage)
                    Text(Tab.actions.title)
                }
                .tag(Tab.actions)

            tabContent(for: .providers)
                .tabItem {
                    Image(systemName: Tab.providers.systemImage)
                    Text(Tab.providers.title)
                }
                .tag(Tab.providers)

            tabContent(for: .settings)
                .tabItem {
                    Image(systemName: Tab.settings.systemImage)
                    Text(Tab.settings.title)
                }
                .tag(Tab.settings)
        }
        .tint(colors.accent)
        .background(colors.background.ignoresSafeArea())
        .onReceive(configStore.createCustomConfigurationRequestPublisher) { request in
            handleCreateCustomConfigRequest(request)
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
        #endif
    }

    @ViewBuilder
    private func tabContent(for tab: Tab) -> some View {
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
