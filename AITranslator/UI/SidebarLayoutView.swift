//
//  SidebarLayoutView.swift
//  TLingo
//
//  Created by Codex on 2026/03/27.
//

import ShareCore
import SwiftUI

struct SidebarLayoutView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: RootTabView.TabItem
    @ObservedObject private var configStore: AppConfigurationStore
    @ObservedObject private var preferences = AppPreferences.shared

    init(initialTab: RootTabView.TabItem, configStore: AppConfigurationStore) {
        _selection = State(initialValue: initialTab)
        self.configStore = configStore
    }

    private var colors: AppColorPalette {
        AppColors.Palette(colorScheme: colorScheme, accentTheme: preferences.accentTheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            CustomSidebarView(selection: $selection, colors: colors)

            Divider()

            contentView(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func contentView(for tab: RootTabView.TabItem) -> some View {
        switch tab {
        case .home:
            HomeView(context: nil)
        case .history:
            HistoryView()
        case .actions:
            ActionsView(configurationStore: configStore)
        case .models:
            ModelsView()
        case .settings:
            SettingsView(configStore: configStore)
        }
    }
}
