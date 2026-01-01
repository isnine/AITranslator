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
    @State private var isEditing = false
    @State private var isAddingNewAction = false

    // Validation error state
    @State private var showValidationError = false
    @State private var validationErrorMessage = ""

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("All Actions")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(colors.textPrimary)
                            Spacer()
                            Button {
                                withAnimation {
                                    isEditing.toggle()
                                }
                            } label: {
                                Text(isEditing ? "Done" : "Reorder")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(colors.accent)
                            }
                        }

                        VStack(spacing: 12) {
                            ForEach(configurationStore.actions) { action in
                                NavigationLink(value: action) {
                                    ActionCardView(
                                        action: action,
                                        deploymentInfo: deploymentInfo(for: action),
                                        showDragHandle: isEditing,
                                        colors: colors
                                    )
                                }
                                .buttonStyle(.plain)
                                .draggable(action.id.uuidString) {
                                    ActionCardView(
                                        action: action,
                                        deploymentInfo: deploymentInfo(for: action),
                                        showDragHandle: false,
                                        colors: colors
                                    )
                                    .frame(width: 300)
                                    .opacity(0.8)
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let draggedIDString = items.first,
                                          let draggedID = UUID(uuidString: draggedIDString) else {
                                        return false
                                    }
                                    reorderAction(from: draggedID, to: action.id)
                                    return true
                                }
                            }
                        }
                    }

                    if configurationStore.actions.isEmpty {
                        emptyStateView
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
            .background(colors.background.ignoresSafeArea())
            .navigationDestination(for: ActionConfig.self) { action in
                ActionDetailView(
                    action: action,
                    configurationStore: configurationStore
                )
            }
            .navigationDestination(isPresented: $isAddingNewAction) {
                ActionDetailView(
                    action: nil,
                    configurationStore: configurationStore
                )
            }
        }
        .tint(colors.accent)
#if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
#endif
        .alert("Validation Failed", isPresented: $showValidationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationErrorMessage)
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Action Library")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Text("Manage your custom actions")
                    .font(.system(size: 15))
                    .foregroundColor(colors.textSecondary)
            }
            
            Spacer()
            
            Button {
                isAddingNewAction = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(colors.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(colors.textSecondary.opacity(0.5))

            VStack(spacing: 6) {
                Text("No Actions Yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(colors.textPrimary)

                Text("Create your first action by tapping the + button, or import a configuration from Settings.")
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }

    struct DeploymentInfo {
        let providerCount: Int
        let deploymentCount: Int
        let deploymentNames: [String]
    }

    private func deploymentInfo(for action: ActionConfig) -> DeploymentInfo {
        let availableProviders = configurationStore.providers
        var providerIDs = Set<UUID>()
        var deploymentNames: [String] = []
        
        for pd in action.providerDeployments {
            if let provider = availableProviders.first(where: { $0.id == pd.providerID }) {
                providerIDs.insert(pd.providerID)
                // Use deployment name if specified, otherwise use first deployment
                let name = pd.deployment.isEmpty ? (provider.deployments.first ?? provider.displayName) : pd.deployment
                deploymentNames.append(name)
            }
        }
        
        return DeploymentInfo(
            providerCount: providerIDs.count,
            deploymentCount: deploymentNames.count,
            deploymentNames: deploymentNames
        )
    }

    private func reorderAction(from sourceID: UUID, to destinationID: UUID) {
        guard sourceID != destinationID else { return }
        var actions = configurationStore.actions
        guard let sourceIndex = actions.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = actions.firstIndex(where: { $0.id == destinationID }) else {
            return
        }
        let movedAction = actions.remove(at: sourceIndex)
        actions.insert(movedAction, at: destinationIndex)
        if let result = configurationStore.updateActions(actions), result.hasErrors {
            validationErrorMessage = result.errors.map(\.message).joined(separator: "\n")
            showValidationError = true
        }
    }
}

private extension ActionsView {
    struct ActionCardView: View {
        let action: ActionConfig
        let deploymentInfo: ActionsView.DeploymentInfo
        let showDragHandle: Bool
        let colors: AppColorPalette

        var body: some View {
            HStack(spacing: 12) {
                if showDragHandle {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(action.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colors.textPrimary)

                    Text(action.summary)
                        .font(.system(size: 15))
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(2)

                    Text(summaryText)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary.opacity(0.8))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colors.cardBackground)
            )
        }

        private var summaryText: String {
            let providerText = deploymentInfo.providerCount == 1 ? "1 provider" : "\(deploymentInfo.providerCount) providers"
            let modelText = deploymentInfo.deploymentCount == 1 ? "1 model" : "\(deploymentInfo.deploymentCount) models"
            let modelNames = deploymentInfo.deploymentNames.joined(separator: ", ")
            
            if deploymentInfo.deploymentNames.isEmpty {
                return providerText
            }
            return "\(providerText), \(modelText) (\(modelNames))"
        }
    }
}

#Preview {
    ActionsView()
        .preferredColorScheme(.dark)
}
