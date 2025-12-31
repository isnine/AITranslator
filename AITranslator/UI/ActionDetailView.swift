//
//  ActionDetailView.swift
//  AITranslator
//
//  Created by Codex on 2025/10/23.
//

import SwiftUI
import ShareCore

struct ActionDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var configurationStore: AppConfigurationStore

    private let actionID: UUID
    @State private var name: String
    @State private var summary: String
    @State private var prompt: String
    @State private var selectedProviderIDs: Set<UUID>
    @State private var usageScenes: ActionConfig.UsageScene
    @State private var showsDiff: Bool

    init(
        action: ActionConfig,
        configurationStore: AppConfigurationStore
    ) {
        self._configurationStore = ObservedObject(wrappedValue: configurationStore)
        self.actionID = action.id
        _name = State(initialValue: action.name)
        _summary = State(initialValue: action.summary)
        _prompt = State(initialValue: action.prompt)
        _selectedProviderIDs = State(initialValue: Set(action.providerIDs))
        _usageScenes = State(initialValue: action.usageScenes)
        _showsDiff = State(initialValue: action.showsDiff)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    basicInfoSection
                    promptSection
                    providerSection
                    usageSection
                    optionsSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .background(colors.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    private var headerBar: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(colors.textPrimary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: saveAction) {
                Text("Save")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(colors.background.opacity(0.98))
    }

    private var basicInfoSection: some View {
        section(title: "Basic Info") {
            labeledField(title: "Action Name", text: $name)
            labeledField(title: "Action Summary", text: $summary)
        }
    }

    private var promptSection: some View {
        section(title: "Prompt Template", subtitle: "Use {text} as placeholder") {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $prompt)
                    .font(.system(size: 15))
                    .foregroundColor(colors.textPrimary)
                    .frame(minHeight: 160)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(colors.inputBackground)
                    )
                    .scrollContentBackground(.hidden)
            }
        }
    }

    private var providerSection: some View {
        section(title: "Select Providers") {
            VStack(spacing: 12) {
                ForEach(configurationStore.providers) { provider in
                    providerRow(for: provider)
                }
            }
        }
    }

    private var usageSection: some View {
        section(title: "Usage Scenes") {
            VStack(alignment: .leading, spacing: 12) {
                usageSceneRow(title: "App", description: "Available inside the app", scene: .app)
                usageSceneRow(title: "Read-Only Context", description: "Visible when you can only read text", scene: .contextRead)
                usageSceneRow(title: "Editable Context", description: "Visible when you can edit and replace text", scene: .contextEdit)
            }
        }
    }

    private var optionsSection: some View {
        section(title: "Options") {
            Toggle(isOn: $showsDiff) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show diff output")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text("Highlights differences between original and AI output")
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: colors.accent))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colors.inputBackground)
            )
        }
    }

    @ViewBuilder
    private func section(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(colors.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(colors.textSecondary)
            }

            content()
        }
    }

    private func labeledField(title: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.textSecondary)

          TextField(String(), text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(colors.inputBackground)
                )
        }
    }

    private func providerRow(for provider: ProviderConfig) -> some View {
        let isSelected = selectedProviderIDs.contains(provider.id)
        return Button {
            toggleProvider(provider.id)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.textPrimary)

                    Text(provider.modelName)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(colors.accent)
                        .font(.system(size: 20))
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(colors.textSecondary.opacity(0.6))
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isSelected ? colors.accent : colors.cardBackground, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func usageSceneRow(
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        scene: ActionConfig.UsageScene
    ) -> some View {
        let isSelected = usageScenes.contains(scene)
        return Button {
            toggleScene(scene)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? colors.accent : colors.textSecondary.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colors.cardBackground)
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleProvider(_ id: UUID) {
        if selectedProviderIDs.contains(id) {
            selectedProviderIDs.remove(id)
        } else {
            selectedProviderIDs.insert(id)
        }
    }

    private func toggleScene(_ scene: ActionConfig.UsageScene) {
        if usageScenes.contains(scene) {
            usageScenes.remove(scene)
        } else {
            usageScenes.insert(scene)
        }
        if usageScenes.isEmpty {
            usageScenes.insert(.app)
        }
    }

    private func saveAction() {
        let orderedProviderIDs = configurationStore.providers
            .map(\.id)
            .filter { selectedProviderIDs.contains($0) }

        let updated = ActionConfig(
            id: actionID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            providerIDs: orderedProviderIDs,
            usageScenes: usageScenes,
            showsDiff: showsDiff
        )

        var actions = configurationStore.actions

        // Find and update the action
        if let index = actions.firstIndex(where: { $0.id == actionID }) {
            actions[index] = updated
        } else {
            // New action
            actions.append(updated)
        }

        configurationStore.updateActions(actions)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ActionDetailView(
            action: AppConfigurationStore.shared.actions.first!,
            configurationStore: AppConfigurationStore.shared
        )
        .preferredColorScheme(.dark)
    }
}
