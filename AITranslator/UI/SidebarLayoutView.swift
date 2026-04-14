//
//  SidebarLayoutView.swift
//  TLingo
//
//  Created by Codex on 2026/03/27.
//

import ShareCore
import SwiftUI

#if os(macOS)

    // MARK: - Sidebar Selection

    enum SidebarSelection: Hashable {
        case tab(RootTabView.TabItem)
        case historyRecord(UUID)
    }

    // MARK: - SidebarLayoutView

    struct SidebarLayoutView: View {
        @State private var selection: SidebarSelection?
        @State private var historyRecords: [TranslationRecord] = []
        @State private var historyRefreshTask: Task<Void, Never>?
        @ObservedObject private var configStore: AppConfigurationStore

        init(initialTab: RootTabView.TabItem, configStore: AppConfigurationStore) {
            _selection = State(initialValue: .tab(initialTab))
            self.configStore = configStore
        }

        private static let sidebarTabs: [RootTabView.TabItem] = RootTabView.TabItem.allCases.filter { $0 != .history }

        var body: some View {
            NavigationSplitView {
                List(selection: $selection) {
                    Section {
                        ForEach(Self.sidebarTabs) { item in
                            Label(item.title, systemImage: item.systemImage)
                                .tag(SidebarSelection.tab(item))
                        }
                    }

                    if !historyRecords.isEmpty {
                        Section("History") {
                            ForEach(historyRecords) { record in
                                Label(
                                    record.sourceText,
                                    systemImage: configStore.actions
                                        .first(where: { $0.name == record.actionName })?
                                        .outputType.systemImageName ?? "clock"
                                )
                                .lineLimit(1)
                                .tag(SidebarSelection.historyRecord(record.id))
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200)
                .navigationTitle("TLingo")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PremiumSidebarFooter()
                        .frame(height: 72)
                }
            } detail: {
                contentView(for: selection ?? .tab(.home))
            }
            .onAppear {
                refreshHistory()
            }
            .onReceive(NotificationCenter.default.publisher(for: .translationRecordSaved)) { _ in
                historyRefreshTask?.cancel()
                historyRefreshTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    refreshHistory()
                }
            }
        }

        @ViewBuilder
        private func contentView(for selection: SidebarSelection) -> some View {
            switch selection {
            case .tab(let tab):
                tabContentView(for: tab)
            case .historyRecord(let id):
                if let record = historyRecords.first(where: { $0.id == id }) {
                    HistoryRecordDetailView(record: record)
                } else {
                    ContentUnavailableView("Record Not Found", systemImage: "clock.arrow.circlepath")
                }
            }
        }

        @ViewBuilder
        private func tabContentView(for tab: RootTabView.TabItem) -> some View {
            switch tab {
            case .home:
                HomeView(context: nil)
            case .history:
                let _ = { assertionFailure("History tab should not appear in macOS sidebar") }()
                EmptyView()
            case .actions:
                ActionsView(configurationStore: configStore)
            case .models:
                ModelsView()
            case .settings:
                SettingsView(configStore: configStore)
            }
        }

        private func refreshHistory() {
            let cutoff = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            historyRecords = TranslationHistoryService.shared.fetchSince(cutoff)
        }
    }

#else

    // MARK: - SidebarLayoutView (iOS)

    struct SidebarLayoutView: View {
        @State private var selection: RootTabView.TabItem?
        @ObservedObject private var configStore: AppConfigurationStore

        init(initialTab: RootTabView.TabItem, configStore: AppConfigurationStore) {
            _selection = State(initialValue: initialTab)
            self.configStore = configStore
        }

        var body: some View {
            NavigationSplitView {
                List(RootTabView.TabItem.allCases, selection: $selection) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200)
                .navigationTitle("TLingo")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PremiumSidebarFooter()
                        .frame(height: 72)
                }
            } detail: {
                contentView(for: selection ?? .home)
            }
        }

        @ViewBuilder
        private func contentView(for tab: RootTabView.TabItem) -> some View {
            switch tab {
            case .home:
                HomeView(context: nil)
            case .history:
                HistoryView()
            case .actions:
                ActionsView(configurationStore: configStore)
            case .models:
                ModelsView()
            case .settings:
                SettingsView(configStore: configStore)
            }
        }
    }

#endif

// MARK: - Premium Footer

private struct PremiumSidebarFooter: View {
    @ObservedObject private var preferences = AppPreferences.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPaywall = false

    private var accentColor: Color {
        preferences.accentTheme.color
    }

    private var fadeGradient: LinearGradient {
        #if canImport(AppKit)
            let base = Color(NSColor.windowBackgroundColor)
        #else
            let base = Color(.systemBackground)
        #endif
        return LinearGradient(
            stops: [
                .init(color: base.opacity(0), location: 0),
                .init(color: base.opacity(0.85), location: 0.4),
                .init(color: base, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            fadeGradient
                .allowsHitTesting(false)

            if StoreManager.shared.isPremium {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 13))
                    Text("Premium")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("Active")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13))
                        Text("Upgrade to Premium")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}
