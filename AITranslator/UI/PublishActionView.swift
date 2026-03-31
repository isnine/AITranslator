//
//  PublishActionView.swift
//  TLingo
//
//  Created by Claude on 2026/03/31.
//

import ShareCore
import SwiftUI

struct PublishActionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var marketplace = MarketplaceService.shared
    @ObservedObject private var configStore: AppConfigurationStore

    @State private var selectedActionID: UUID?
    @State private var description = ""
    @State private var category: MarketplaceCategory = .translation
    @State private var authorName = ""
    @State private var errorMessage: String?
    @State private var showSuccess = false

    init(configurationStore: AppConfigurationStore = .shared) {
        configStore = configurationStore
    }

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    private var selectedAction: ActionConfig? {
        configStore.actions.first { $0.id == selectedActionID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    actionPickerSection
                    descriptionSection
                    categorySection
                    authorSection
                    publishButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .background(colors.background.ignoresSafeArea())
            .navigationTitle(Text("Publish Action", comment: "Publish action title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Publish cancel")
                    }
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Published", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your action is now available in the marketplace.", comment: "Publish success")
            }
            .overlay {
                if marketplace.isPublishing {
                    LoadingOverlay(
                        backgroundColor: colors.background.opacity(0.85),
                        messageFont: .system(size: 13),
                        textColor: colors.textSecondary,
                        accentColor: colors.accent
                    )
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Action Picker

    private var actionPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("ACTION", icon: "bolt.fill")
            VStack(spacing: 0) {
                ForEach(Array(configStore.actions.enumerated()), id: \.element.id) { index, action in
                    Button {
                        selectedActionID = action.id
                    } label: {
                        HStack(spacing: 12) {
                            Image(
                                systemName: selectedActionID == action.id
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.system(size: 18))
                            .foregroundColor(
                                selectedActionID == action.id
                                    ? colors.accent : colors.textSecondary.opacity(0.4)
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(colors.textPrimary)
                                Text(action.prompt)
                                    .font(.system(size: 13))
                                    .foregroundColor(colors.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < configStore.actions.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colors.cardBackground)
            )
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("DESCRIPTION", icon: "text.alignleft")
            TextEditor(text: $description)
                .font(.system(size: 15))
                .foregroundColor(colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colors.cardBackground)
                )
                .overlay(alignment: .topLeading) {
                    if description.isEmpty {
                        Text("Describe what this action does...", comment: "Publish description placeholder")
                            .font(.system(size: 15))
                            .foregroundColor(colors.textSecondary.opacity(0.5))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("CATEGORY", icon: "tag")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MarketplaceCategory.allCases) { cat in
                        let isSelected = category == cat
                        Button {
                            category = cat
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.systemImage)
                                    .font(.system(size: 12))
                                Text(cat.displayName)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(isSelected ? colors.chipPrimaryText : colors.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? colors.accent : colors.cardBackground)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Author Name

    private var authorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("AUTHOR NAME", icon: "person")
            TextField(
                String(localized: "Your name (optional)", comment: "Publish author placeholder"),
                text: $authorName
            )
            .font(.system(size: 15))
            .foregroundColor(colors.textPrimary)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colors.cardBackground)
            )
        }
    }

    // MARK: - Publish Button

    private var publishButton: some View {
        Button {
            performPublish()
        } label: {
            HStack {
                Image(systemName: "paperplane.fill")
                Text("Publish", comment: "Publish button")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(canPublish ? colors.accent : colors.accent.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .disabled(!canPublish)
    }

    // MARK: - Helpers

    private var canPublish: Bool {
        selectedAction != nil && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(colors.textSecondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colors.textSecondary)
        }
        .padding(.leading, 4)
    }

    private func performPublish() {
        guard let action = selectedAction else { return }
        Task {
            do {
                _ = try await marketplace.publish(
                    action: action,
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: category,
                    authorName: authorName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
