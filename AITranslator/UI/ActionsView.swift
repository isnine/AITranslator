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
                                        providerCount: providerCount(for: action),
                                        showDragHandle: isEditing,
                                        colors: colors
                                    )
                                }
                                .buttonStyle(.plain)
                                .draggable(action.id.uuidString) {
                                    ActionCardView(
                                        action: action,
                                        providerCount: providerCount(for: action),
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
#if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
#endif
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

    private func providerCount(for action: ActionConfig) -> Int {
        let availableIDs = Set(configurationStore.providers.map(\.id))
        return action.providerIDs.filter { availableIDs.contains($0) }.count
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
        configurationStore.updateActions(actions)
    }
}

private extension ActionsView {
    struct ActionCardView: View {
        let action: ActionConfig
        let providerCount: Int
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

                    Text(providerCountText)
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

        private var providerCountText: String {
            if providerCount == 1 {
                return "1 provider"
            }
            return "\(providerCount) providers"
        }
    }
}

#Preview {
    ActionsView()
        .preferredColorScheme(.dark)
}
