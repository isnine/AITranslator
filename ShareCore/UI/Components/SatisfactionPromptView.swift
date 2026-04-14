//
//  SatisfactionPromptView.swift
//  TLingo
//
//  Created by Zander Wang on 2026/04/13.
//

import SwiftUI

struct SatisfactionPromptView: View {
    let colors: AppColors.Palette
    let onSatisfied: () -> Void
    let onFeedback: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Enjoying TLingo?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(colors.textPrimary)

            HStack(spacing: 10) {
                Button {
                    onSatisfied()
                } label: {
                    Label("Satisfied", systemImage: "star.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(colors.accent, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onFeedback()
                } label: {
                    Label("Feedback", systemImage: "envelope")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(colors.inputBackground, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colors.cardBackground)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        )
    }
}
