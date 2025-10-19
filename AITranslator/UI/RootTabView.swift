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
                    Text("主页")
                }

            PlaceholderTab(title: "操作", message: "操作界面开发中…")
                .tabItem {
                    Image(systemName: "bolt.fill")
                    Text("操作")
                }

            PlaceholderTab(title: "提供商", message: "提供商配置稍后上线。")
                .tabItem {
                    Image(systemName: "rectangle.connected.to.line.below")
                    Text("提供商")
                }

            PlaceholderTab(title: "设置", message: "设置页面准备中…")
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("设置")
                }
        }
        .tint(colors.accent)
        .background(colors.background.ignoresSafeArea())
    }
}
