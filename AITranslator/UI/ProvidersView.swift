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
                                    ProviderCardView(
                                        provider: provider,
                                        isDefault: provider.id == configurationStore.defaultProvider?.id,
                                        status: status(for: provider),
                                        colors: colors,
                                        onToggleDeployment: { deployment, enabled in
                                            toggleDeployment(for: provider, deployment: deployment, enabled: enabled)
                                        },
                                        onNavigate: {
                                            selectedProvider = provider
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
            .background(colors.background.ignoresSafeArea())
            .navigationDestination(item: $selectedProvider) { provider in
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
        // Built-in Cloud is always active (uses built-in authentication)
        if provider.category == .builtInCloud {
            return .active
        }
        if provider.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .inactive
        }
        return .active
    }
    
    private func toggleDeployment(for provider: ProviderConfig, deployment: String, enabled: Bool) {
        var updatedProvider = provider
        if enabled {
            updatedProvider.enabledDeployments.insert(deployment)
        } else {
            updatedProvider.enabledDeployments.remove(deployment)
        }
        
        var providers = configurationStore.providers
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = updatedProvider
            _ = configurationStore.updateProviders(providers)
        }
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
        let onToggleDeployment: (String, Bool) -> Void
        let onNavigate: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                // Header row with navigation
                Button(action: onNavigate) {
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
                }
                .buttonStyle(.plain)

                // Endpoint info
                Text(provider.baseEndpoint.host ?? provider.baseEndpoint.absoluteString)
                    .font(.system(size: 15))
                    .foregroundColor(colors.textSecondary)

                // Deployments list with toggles
                if !provider.deployments.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(provider.deployments, id: \.self) { deployment in
                            deploymentToggleRow(deployment: deployment)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colors.cardBackground)
            )
        }
        
        private func deploymentToggleRow(deployment: String) -> some View {
            let isEnabled = provider.enabledDeployments.contains(deployment)
            return HStack(spacing: 12) {
                Button {
                    onToggleDeployment(deployment, !isEnabled)
                } label: {
                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isEnabled ? colors.accent : colors.textSecondary)
                }
                .buttonStyle(.plain)

                Text(deployment)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.textPrimary)

                Spacer()

                Text(isEnabled ? "Enabled" : "Disabled")
                    .font(.system(size: 12))
                    .foregroundColor(isEnabled ? colors.success : colors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colors.inputBackground)
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
