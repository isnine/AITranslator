//
//  MarketplaceActionDetailView.swift
//  TLingo
//
//  Created by Claude on 2026/03/31.
//

import ShareCore
import SwiftUI

struct MarketplaceActionDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var marketplace = MarketplaceService.shared
    @ObservedObject private var configStore: AppConfigurationStore

    let action: MarketplaceAction

    @State private var showDownloadSuccess = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    init(action: MarketplaceAction, configurationStore: AppConfigurationStore = .shared) {
        self.action = action
        configStore = configurationStore
    }

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                metadataSection
                descriptionSection
                promptSection
                detailsSection
                downloadButton
                if marketplace.isOwnedByCurrentUser(action) {
                    deleteSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .background(colors.background.ignoresSafeArea())
        #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
        #endif
            .alert("Downloaded", isPresented: $showDownloadSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Action has been added to your local actions.", comment: "Marketplace download success")
            }
            .alert("Delete Action", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    performDelete()
                }
            } message: {
                Text(
                    "This will remove the action from the marketplace. This cannot be undone.",
                    comment: "Marketplace delete confirm"
                )
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
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.accent)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(action.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(colors.textPrimary)

            HStack(spacing: 12) {
                Label(action.authorName, systemImage: "person.circle")
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)

                Label(action.category.displayName, systemImage: action.category.systemImage)
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)

                if action.downloadCount > 0 {
                    Label("\(action.downloadCount)", systemImage: "arrow.down.circle")
                        .font(.system(size: 14))
                        .foregroundColor(colors.textSecondary)
                }
            }

            Text(action.createdAt, style: .date)
                .font(.system(size: 13))
                .foregroundColor(colors.textSecondary.opacity(0.7))
        }
    }

    // MARK: - Description

    @ViewBuilder
    private var descriptionSection: some View {
        if !action.actionDescription.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("DESCRIPTION", icon: "text.alignleft")
                Text(action.actionDescription)
                    .font(.system(size: 15))
                    .foregroundColor(colors.textPrimary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colors.cardBackground)
                    )
            }
        }
    }

    // MARK: - Prompt Preview

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("PROMPT", icon: "text.bubble")
            Text(action.prompt)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(colors.textPrimary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colors.cardBackground)
                )
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("DETAILS", icon: "info.circle")
            VStack(spacing: 0) {
                detailRow(
                    label: String(localized: "Output Type", comment: "Marketplace detail label"),
                    value: action.outputType.displayName
                )
                Divider().padding(.leading, 16)
                detailRow(
                    label: String(localized: "Usage", comment: "Marketplace detail label"),
                    value: usageScenesDescription
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colors.cardBackground)
            )
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Download

    private var isAlreadyDownloaded: Bool {
        configStore.actions.contains { $0.name == action.name && $0.prompt == action.prompt }
    }

    private var downloadButton: some View {
        Button {
            downloadAction()
        } label: {
            HStack {
                Image(systemName: isAlreadyDownloaded ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                Text(
                    isAlreadyDownloaded
                        ? String(localized: "Downloaded", comment: "Marketplace already downloaded label")
                        : String(localized: "Download", comment: "Marketplace download button")
                )
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(isAlreadyDownloaded ? colors.textSecondary : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isAlreadyDownloaded ? colors.cardBackground : colors.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyDownloaded)
    }

    // MARK: - Delete (owner only)

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("DANGER ZONE", icon: "exclamationmark.triangle")
            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete from Marketplace", comment: "Marketplace delete button")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
    }

    // MARK: - Helpers

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

    private var usageScenesDescription: String {
        var scenes: [String] = []
        if action.usageScenes.contains(.app) {
            scenes.append(String(localized: "In App", comment: "Usage scene"))
        }
        if action.usageScenes.contains(.contextRead) {
            scenes.append(String(localized: "Read-Only", comment: "Usage scene"))
        }
        if action.usageScenes.contains(.contextEdit) {
            scenes.append(String(localized: "Editable", comment: "Usage scene"))
        }
        return scenes.isEmpty
            ? String(localized: "All", comment: "Usage scene all")
            : scenes.joined(separator: ", ")
    }

    private func downloadAction() {
        let newAction = action.toActionConfig()
        var actions = configStore.actions
        if isAlreadyDownloaded {
            errorMessage = String(
                localized: "This action already exists in your local actions.",
                comment: "Marketplace duplicate error"
            )
            return
        }
        actions.append(newAction)
        if let result = configStore.updateActions(actions), result.hasErrors {
            errorMessage = result.errors.map(\.message).joined(separator: "\n")
            return
        }
        marketplace.incrementDownloadCount(for: action)
        showDownloadSuccess = true
    }

    private func performDelete() {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            do {
                try await marketplace.delete(action)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isDeleting = false
            }
        }
    }
}
