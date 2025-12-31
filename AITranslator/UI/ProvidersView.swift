//
//  ProvidersView.swift
//  AITranslator
//
//  Created by Codex on 2025/10/25.
//

import SwiftUI
import ShareCore

struct ProvidersView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var configurationStore = AppConfigurationStore.shared
    @State private var selectedProvider: ProviderConfig?
    @State private var isAddingNewProvider = false

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection

                    if configurationStore.providers.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Configured Providers")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(colors.textPrimary)

                            VStack(spacing: 16) {
                                ForEach(configurationStore.providers) { provider in
                                    NavigationLink(value: provider) {
                                        ProviderCardView(
                                            provider: provider,
                                            isDefault: provider.id == configurationStore.defaultProvider?.id,
                                            status: status(for: provider),
                                            colors: colors
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
            .background(colors.background.ignoresSafeArea())
            .navigationDestination(for: ProviderConfig.self) { provider in
                ProviderDetailView(
                    provider: provider,
                    configurationStore: configurationStore
                )
            }
            .navigationDestination(isPresented: $isAddingNewProvider) {
                ProviderDetailView(
                    provider: nil,
                    configurationStore: configurationStore
                )
            }
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Providers")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(colors.textPrimary)

                Text("Configure AI providers")
                    .font(.system(size: 15))
                    .foregroundColor(colors.textSecondary)
            }
            
            Spacer()
            
            Button {
                isAddingNewProvider = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(colors.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No providers configured yet.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(colors.textPrimary)
            Text("Add a provider to start using translation features.")
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Button {
                isAddingNewProvider = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Add Provider")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(colors.accent)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colors.cardBackground)
        )
    }

    private func status(for provider: ProviderConfig) -> ProviderCardView.Status {
        if provider.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .inactive
        }
        return .active
    }
}

private extension ProvidersView {
    struct ProviderCardView: View {
        enum Status {
            case active
            case inactive

            var iconName: String {
                switch self {
                case .active:
                    return "checkmark.circle.fill"
                case .inactive:
                    return "xmark.circle.fill"
                }
            }
        }

        let provider: ProviderConfig
        let isDefault: Bool
        let status: Status
        let colors: AppColorPalette

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text(provider.displayName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colors.textPrimary)

                    if isDefault {
                        Text("Default")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(colors.chipSecondaryBackground)
                            )
                            .foregroundColor(colors.chipSecondaryText)
                    }

                    Spacer()

                    Image(systemName: status.iconName)
                        .font(.system(size: 18))
                        .foregroundColor(status == .active ? colors.success : colors.error)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.apiURL.host ?? provider.apiURL.absoluteString)
                        .font(.system(size: 15))
                        .foregroundColor(colors.textSecondary)

                    Text(provider.modelName)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colors.cardBackground)
            )
        }
    }
}

#Preview {
    NavigationStack {
        ProvidersView()
            .preferredColorScheme(.dark)
    }
}
