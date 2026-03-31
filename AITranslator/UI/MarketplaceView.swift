//
//  MarketplaceView.swift
//  TLingo
//
//  Created by Claude on 2026/03/31.
//

import ShareCore
import SwiftUI

struct MarketplaceView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var marketplace = MarketplaceService.shared
    @ObservedObject private var configStore: AppConfigurationStore
    @ObservedObject private var preferences = AppPreferences.shared

    @State private var searchText = ""
    @State private var selectedCategory: MarketplaceCategory?
    @State private var sortOption: MarketplaceSortOption = .newest
    @State private var showPublishSheet = false
    @State private var searchTask: Task<Void, Never>?

    init(configurationStore: AppConfigurationStore = .shared) {
        configStore = configurationStore
    }

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                searchBar
                categoryChips
                sortPicker
                contentSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .background(colors.background.ignoresSafeArea())
        .navigationDestination(for: MarketplaceAction.self) { action in
            MarketplaceActionDetailView(
                action: action,
                configurationStore: configStore
            )
        }
        .sheet(isPresented: $showPublishSheet) {
            PublishActionView(configurationStore: configStore)
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task {
            await marketplace.ensureUserRecordFetched()
            await marketplace.fetchActions(sortBy: sortOption)
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

            Text("Marketplace", comment: "Marketplace title")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(colors.textPrimary)

            Spacer()

            Button {
                showPublishSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)

            TextField(
                String(localized: "Search actions...", comment: "Marketplace search placeholder"),
                text: $searchText
            )
            .font(.system(size: 15))
            .foregroundColor(colors.textPrimary)
            .autocorrectionDisabled()
            .onChange(of: searchText) {
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await marketplace.fetchActions(
                        searchText: searchText,
                        category: selectedCategory,
                        sortBy: sortOption
                    )
                }
            }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colors.cardBackground)
        )
    }

    // MARK: - Category Chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: String(localized: "All", comment: "Marketplace filter all"), category: nil)
                ForEach(MarketplaceCategory.allCases) { category in
                    categoryChip(title: category.displayName, category: category)
                }
            }
        }
    }

    private func categoryChip(title: String, category: MarketplaceCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
            Task {
                await marketplace.fetchActions(
                    searchText: searchText,
                    category: selectedCategory,
                    sortBy: sortOption
                )
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? colors.chipPrimaryText : colors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? colors.accent : colors.cardBackground)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sort

    private var sortPicker: some View {
        HStack(spacing: 8) {
            ForEach(MarketplaceSortOption.allCases, id: \.rawValue) { option in
                let isSelected = sortOption == option
                Button {
                    sortOption = option
                    Task {
                        await marketplace.fetchActions(
                            searchText: searchText,
                            category: selectedCategory,
                            sortBy: sortOption
                        )
                    }
                } label: {
                    Text(option.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? colors.accent : colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        if marketplace.isLoading && marketplace.actions.isEmpty {
            loadingView
        } else if let error = marketplace.error, marketplace.actions.isEmpty {
            errorView(error)
        } else if marketplace.actions.isEmpty {
            emptyView
        } else {
            actionsList
        }
    }

    private var actionsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(marketplace.actions.enumerated()), id: \.element.id) { index, action in
                NavigationLink(value: action) {
                    MarketplaceActionRow(action: action, colors: colors)
                }
                .buttonStyle(.plain)

                if index < marketplace.actions.count - 1 {
                    Divider()
                        .padding(.leading, 20)
                }
            }

            if marketplace.hasMoreResults {
                Button {
                    Task {
                        await marketplace.fetchNextPage()
                    }
                } label: {
                    if marketplace.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        Text("Load More", comment: "Marketplace load more")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.cardBackground)
        )
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading...", comment: "Marketplace loading")
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(colors.textSecondary.opacity(0.5))

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await marketplace.fetchActions(
                        searchText: searchText,
                        category: selectedCategory,
                        sortBy: sortOption
                    )
                }
            } label: {
                Text("Retry", comment: "Marketplace retry")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.cardBackground)
        )
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(colors.textSecondary.opacity(0.4))

            Text("No actions found", comment: "Marketplace empty state")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.textPrimary)

            Text("Try adjusting your search or filters", comment: "Marketplace empty hint")
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.cardBackground)
        )
    }
}

// MARK: - Action Row

private struct MarketplaceActionRow: View {
    let action: MarketplaceAction
    let colors: AppColorPalette

    var body: some View {
        HStack(spacing: 12) {
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
                    Text(action.authorName)
                        .lineLimit(1)
                    Text("·")
                    Image(systemName: action.category.systemImage)
                        .font(.system(size: 11))
                    Text(action.category.displayName)
                    if action.downloadCount > 0 {
                        Text("·")
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11))
                        Text("\(action.downloadCount)")
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
