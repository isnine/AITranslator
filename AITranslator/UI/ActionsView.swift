//
//  ActionsView.swift
//  AITranslator
//
//  Created by Codex on 2025/10/23.
//

import SwiftUI
import ShareCore

struct ActionsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var configurationStore = AppConfigurationStore.shared

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    Text("All Actions")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colors.textPrimary)

                    VStack(spacing: 16) {
                        ForEach(configurationStore.actions) { action in
                            NavigationLink(value: action) {
                                ActionCardView(
                                    action: action,
                                    isDefault: action.id == configurationStore.defaultAction?.id,
                                    providerCount: providerCount(for: action),
                                    colors: colors
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
            .background(colors.background.ignoresSafeArea())
            .overlay(alignment: .topTrailing) {
                addButton
                    .padding(.top, 24)
                    .padding(.trailing, 24)
            }
            .navigationDestination(for: ActionConfig.self) { action in
                ActionDetailView(
                    action: action,
                    configurationStore: configurationStore
                )
            }
        }
        .tint(colors.accent)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Action Library")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(colors.textPrimary)
            Text("Manage your custom actions")
                .font(.system(size: 15))
                .foregroundColor(colors.textSecondary)
        }
    }

    private var addButton: some View {
        Button(action: {}) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colors.chipPrimaryText)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(colors.accent)
                )
                .shadow(color: colors.accent.opacity(0.35), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func providerCount(for action: ActionConfig) -> Int {
        let availableIDs = Set(configurationStore.providers.map(\.id))
        return action.providerIDs.filter { availableIDs.contains($0) }.count
    }
}

private struct ActionCardView: View {
    let action: ActionConfig
    let isDefault: Bool
    let providerCount: Int
    let colors: AppColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(action.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colors.textPrimary)

                if isDefault {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundColor(colors.accent)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
            }

            Text(action.summary)
                .font(.system(size: 15))
                .foregroundColor(colors.textSecondary)

            Text(providerCountText)
                .font(.system(size: 13))
                .foregroundColor(colors.textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colors.cardBackground)
        )
    }

    private var providerCountText: String {
        if providerCount == 1 {
            return "1 provider"
        }
        return "\(providerCount) providers"
    }
}

#Preview {
    ActionsView()
        .preferredColorScheme(.dark)
}
