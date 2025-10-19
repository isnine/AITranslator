//
//  AITranslatorApp.swift
//  AITranslator
//
//  Created by Zander Wang on 2025/10/18.
//

import SwiftUI
import ShareCore

@main
struct AITranslatorApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
        }
    }
}

private struct RootTabView: View {
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
        .tint(AppColors.accent)
        .background(AppColors.background.ignoresSafeArea())
    }
}

private struct PlaceholderTab: View {
    let title: String
    let message: String

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text(message)
                    .foregroundColor(AppColors.textSecondary)
                    .font(.system(size: 14))
            }
        }
    }
}
