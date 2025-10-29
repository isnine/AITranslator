//
//  RootTabView.swift
//  AITranslator
//
//  Created by Codex on 2025/10/19.
//

import SwiftUI
import ShareCore

struct RootTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: Tab = .home

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
}
