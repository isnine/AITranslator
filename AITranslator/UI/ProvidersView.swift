//
//  ProvidersView.swift
//  TLingo
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
                VStack(alignment: .leading, spacing: 28) {
                    headerSection
                    providersSection
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
        .tint(colors.accent)
#if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }

    // MARK: - Providers Section
    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                Text("PROVIDERS")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                
                Spacer()
                
                Button {
                    isAddingNewProvider = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 4)
            
            if configurationStore.providers.isEmpty {
                emptyState
            } else {
                // Providers list in card
                VStack(spacing: 0) {
                    ForEach(Array(configurationStore.providers.enumerated()), id: \.element.id) { index, provider in
                        ProviderRowView(
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
                        
                        if index < configurationStore.providers.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colors.cardBackground)
                )
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Providers")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(colors.textPrimary)

            Text("Configure AI providers")
                .font(.system(size: 15))
                .foregroundColor(colors.textSecondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(colors.textSecondary.opacity(0.4))

            VStack(spacing: 6) {
                Text("No Providers Yet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.textPrimary)

                Text("Tap + to add your first provider")
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.cardBackground)
        )
    }

    private func status(for provider: ProviderConfig) -> ProviderRowView.Status {
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
    struct ProviderRowView: View {
        let provider: ProviderConfig
        let isDefault: Bool
        let status: Status
        let colors: AppColorPalette
        let onToggleDeployment: (String, Bool) -> Void
        let onNavigate: () -> Void
        
        @State private var isExpanded = false

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

        var body: some View {
            VStack(spacing: 0) {
                // Main row
                HStack(spacing: 12) {
                    // Provider icon
                    Image(systemName: providerIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(iconColor)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(iconColor.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(provider.displayName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(colors.textPrimary)
                            
                            if isDefault && provider.category != .builtInCloud {
                                Text("Default")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(colors.accent.opacity(0.15))
                                    )
                                    .foregroundColor(colors.accent)
                            }
                        }

                        Text(subtitleText)
                            .font(.system(size: 13))
                            .foregroundColor(colors.textSecondary)
                    }

                    Spacer()

                    // Status indicator
                    Image(systemName: status.iconName)
                        .font(.system(size: 14))
                        .foregroundColor(status == .active ? colors.success : colors.error)
                    
                    // Expand/Navigate button
                    if !provider.deployments.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(colors.textSecondary.opacity(0.5))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    onNavigate()
                }
                
                // Expanded deployments
                if isExpanded && !provider.deployments.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(provider.deployments, id: \.self) { deployment in
                            deploymentToggleRow(deployment: deployment)
                            
                            if deployment != provider.deployments.last {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                    .padding(.leading, 40)
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }

        private var providerIcon: String {
            switch provider.category {
            case .builtInCloud:
                return "cloud.fill"
            case .azureOpenAI:
                return "server.rack"
            case .custom:
                return "gearshape.fill"
            case .local:
                return "desktopcomputer"
            }
        }

        private var iconColor: Color {
            switch provider.category {
            case .builtInCloud:
                return colors.accent
            case .azureOpenAI:
                return .blue
            case .custom:
                return .purple
            case .local:
                return .gray
            }
        }

        private var subtitleText: String {
            let enabledCount = provider.enabledDeployments.count
            let totalCount = provider.deployments.count
            
            if provider.category == .builtInCloud {
                return "\(enabledCount) of \(totalCount) models enabled"
            }
            
            if let host = provider.baseEndpoint.host {
                return host
            }
            return "\(enabledCount) models enabled"
        }
        
        private func deploymentToggleRow(deployment: String) -> some View {
            let isEnabled = provider.enabledDeployments.contains(deployment)
            return Button {
                onToggleDeployment(deployment, !isEnabled)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(isEnabled ? colors.accent : colors.textSecondary.opacity(0.4))

                    Text(deployment)
                        .font(.system(size: 14))
                        .foregroundColor(colors.textPrimary)

                    Spacer()
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    NavigationStack {
        ProvidersView()
            .preferredColorScheme(.dark)
    }
}
