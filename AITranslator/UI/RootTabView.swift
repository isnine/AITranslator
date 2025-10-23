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

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        TabView {
            HomeView(context: nil)
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }

            ActionsView()
                .tabItem {
                    Image(systemName: "bolt.fill")
                    Text("Actions")
                }

            ProvidersView()
                .tabItem {
                    Image(systemName: "rectangle.connected.to.line.below")
                    Text("Providers")
                }

            PlaceholderTab(title: "Settings", message: "Settings page in progress...")
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
        }
        .tint(colors.accent)
        .background(colors.background.ignoresSafeArea())
    }
}
