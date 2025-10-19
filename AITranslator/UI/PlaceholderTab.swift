//
//  PlaceholderTab.swift
//  AITranslator
//
//  Created by Codex on 2025/10/19.
//

import SwiftUI
import ShareCore

struct PlaceholderTab: View {
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
