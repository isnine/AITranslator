//
//  ActionDetailView.swift
//  TLingo
//
//  Created by Codex on 2025/10/23.
//

import ShareCore
import SwiftUI

struct ActionDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var configurationStore: AppConfigurationStore

    private let actionID: UUID
    private let isNewAction: Bool
    @State private var name: String
    @State private var prompt: String
    @State private var usageScenes: ActionConfig.UsageScene
    @State private var outputType: OutputType

    // Validation error state
    @State private var showValidationError = false
    @State private var validationErrorMessage = ""

    // Delete confirmation state
    @State private var showDeleteConfirmation = false

    init(
        action: ActionConfig?,
        configurationStore: AppConfigurationStore
    ) {
        _configurationStore = ObservedObject(wrappedValue: configurationStore)

        if let action = action {
            actionID = action.id
            isNewAction = false
            _name = State(initialValue: action.name)
            _prompt = State(initialValue: action.prompt)
            _usageScenes = State(initialValue: action.usageScenes)
            _outputType = State(initialValue: action.outputType)
        } else {
            actionID = UUID()
            isNewAction = true
            _name = State(initialValue: "")
            _prompt = State(initialValue: "Translate the following text to {targetLanguage}:\n\n{text}")
            _usageScenes = State(initialValue: .app)
            _outputType = State(initialValue: .plain)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    basicInfoSection
                    promptSection
                    usageSection
                    optionsSection

                    if !isNewAction {
                        deleteSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .background(colors.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .alert("Validation Failed", isPresented: $showValidationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationErrorMessage)
        }
        .alert("Delete Action", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteAction()
            }
        } message: {
            Text("Are you sure you want to delete this action? This cannot be undone.")
        }
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

            Button {
                saveAction()
            } label: {
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
        }
    }

    private var promptSection: some View {
        section(title: "Prompt Template", subtitle: "Use {text} and {targetLanguage} as placeholders") {
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

    private var usageSection: some View {
        section(title: "Usage Scenes", subtitle: "Context options apply to the iOS Translation Extension only") {
            VStack(alignment: .leading, spacing: 12) {
                usageSceneRow(title: "In App", description: "Available inside the app", scene: .app)
                usageSceneRow(title: "Read-Only Context", description: "Show in iOS Extension when viewing text", scene: .contextRead)
                usageSceneRow(title: "Editable Context", description: "Show in iOS Extension when editing text", scene: .contextEdit)
            }
        }
    }

    private var optionsSection: some View {
        section(title: "Output Type") {
            VStack(spacing: 12) {
                outputTypeRow(
                    type: .plain,
                    title: "Plain Text",
                    description: "Standard text output without special formatting"
                )
                outputTypeRow(
                    type: .diff,
                    title: "Show Diff",
                    description: "Highlights differences between original and AI output"
                )
                outputTypeRow(
                    type: .sentencePairs,
                    title: "Sentence Pairs",
                    description: "Display original and translation side by side"
                )
                outputTypeRow(
                    type: .grammarCheck,
                    title: "Grammar Check",
                    description: "Show revised text with grammar explanations"
                )
            }
        }
    }

    private func outputTypeRow(
        type: OutputType,
        title: LocalizedStringKey,
        description: LocalizedStringKey
    ) -> some View {
        let isSelected = outputType == type
        return Button {
            outputType = type
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

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? colors.accent : colors.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectionRowBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selectionRowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.clear)
            .glassEffect(
                isSelected ? .regular : .regular.interactive(),
                in: .rect(cornerRadius: 18)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? colors.accent : .clear, lineWidth: 2)
            )
    }

    private var deleteSection: some View {
        section(title: "Danger Zone") {
            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Delete Action")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.red.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
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
            .background(usageSceneRowBackground)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var usageSceneRowBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.clear)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
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
        let updated = ActionConfig(
            id: actionID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            usageScenes: usageScenes,
            outputType: outputType
        )

        var actions = configurationStore.actions

        // Find and update the action
        if let index = actions.firstIndex(where: { $0.id == actionID }) {
            actions[index] = updated
        } else {
            // New action
            actions.append(updated)
        }

        if let result = configurationStore.updateActions(actions), result.hasErrors {
            validationErrorMessage = result.errors.map(\.message).joined(separator: "\n")
            showValidationError = true
        } else {
            dismiss()
        }
    }

    private func deleteAction() {
        var actions = configurationStore.actions
        actions.removeAll { $0.id == actionID }

        if let result = configurationStore.updateActions(actions), result.hasErrors {
            validationErrorMessage = result.errors.map(\.message).joined(separator: "\n")
            showValidationError = true
        } else {
            dismiss()
        }
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
