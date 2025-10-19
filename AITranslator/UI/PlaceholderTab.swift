//
//  PlaceholderTab.swift
//  AITranslator
//
//  Created by Codex on 2025/10/19.
//

import SwiftUI
import ShareCore

struct PlaceholderTab: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Text(message)
                    .foregroundColor(colors.textSecondary)
                    .font(.system(size: 14))
            }
        }
    }
}
