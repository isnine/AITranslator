//
//  ActionsView.swift
//  TLingo
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
                VStack(alignment: .leading, spacing: 28) {
                    headerSection
                    actionsSection
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

    // MARK: - Actions Section
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                Text("ACTIONS")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                
                Spacer()
                
                if !configurationStore.actions.isEmpty {
                    Button {
                        withAnimation {
                            isEditing.toggle()
                        }
                    } label: {
                        Text(isEditing ? "Done" : "Reorder")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.accent)
                    }
                    .buttonStyle(.plain)
                }
                
                Button {
                    isAddingNewAction = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 4)
            
            if configurationStore.actions.isEmpty {
                emptyStateView
            } else {
                // Actions list in card
                VStack(spacing: 0) {
                    ForEach(Array(configurationStore.actions.enumerated()), id: \.element.id) { index, action in
                        NavigationLink(value: action) {
                            ActionRowView(
                                action: action,
                                deploymentInfo: deploymentInfo(for: action),
                                showDragHandle: isEditing,
                                colors: colors
                            )
                        }
                        .buttonStyle(.plain)
                        .draggable(action.id.uuidString) {
                            ActionRowView(
                                action: action,
                                deploymentInfo: deploymentInfo(for: action),
                                showDragHandle: false,
                                colors: colors
                            )
                            .frame(width: 300)
                            .padding(16)
                            .background(colors.cardBackground)
                            .cornerRadius(12)
                            .opacity(0.9)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedIDString = items.first,
                                  let draggedID = UUID(uuidString: draggedIDString) else {
                                return false
                            }
                            reorderAction(from: draggedID, to: action.id)
                            return true
                        }
                        
                        if index < configurationStore.actions.count - 1 {
                            Divider()
                                .padding(.leading, isEditing ? 56 : 20)
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
            Text("Actions")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(colors.textPrimary)
            Text("Configure your translation actions")
                .font(.system(size: 15))
                .foregroundColor(colors.textSecondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(colors.textSecondary.opacity(0.4))

            VStack(spacing: 6) {
                Text("No Actions Yet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.textPrimary)

                Text("Tap + to create your first action")
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

    struct DeploymentInfo {
        let providerCount: Int
        let deploymentCount: Int
        let deploymentNames: [String]
    }

    /// Get global deployment info (all enabled deployments across all providers)
    private func deploymentInfo(for action: ActionConfig) -> DeploymentInfo {
        let availableProviders = configurationStore.providers
        var providerCount = 0
        var deploymentNames: [String] = []
        
        for provider in availableProviders {
            let enabledInProvider = provider.deployments.filter { provider.enabledDeployments.contains($0) }
            if !enabledInProvider.isEmpty {
                providerCount += 1
                deploymentNames.append(contentsOf: enabledInProvider)
            }
        }
        
        return DeploymentInfo(
            providerCount: providerCount,
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
    struct ActionRowView: View {
        let action: ActionConfig
        let deploymentInfo: ActionsView.DeploymentInfo
        let showDragHandle: Bool
        let colors: AppColorPalette

        var body: some View {
            HStack(spacing: 12) {
                if showDragHandle {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.textSecondary.opacity(0.6))
                        .frame(width: 24)
                }

                // Action icon
                Image(systemName: actionIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(colors.accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.textPrimary)

                    HStack(spacing: 6) {
                        Text(action.prompt)
                            .lineLimit(1)
                        if deploymentInfo.deploymentCount > 0 {
                            Text("·")
                            Text("\(deploymentInfo.deploymentCount) models")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }

        private var actionIcon: String {
            switch action.outputType {
            case .plain:
                return "doc.text"
            case .diff:
                return "arrow.left.arrow.right"
            case .sentencePairs:
                return "text.alignleft"
            case .grammarCheck:
                return "checkmark.seal"
            }
        }
    }
}

#Preview {
    ActionsView()
        .preferredColorScheme(.dark)
}
