//
//  HistoryView.swift
//  TLingo
//
//  Created by Zander Wang on 2026/03/13.
//

import ShareCore
import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

struct HistoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var records: [TranslationRecord] = []
    @State private var expandedRecordIDs: Set<UUID> = []
    @State private var showDeleteAllConfirmation = false
    @State private var isVisible = false

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                #if os(macOS)
                    headerSection
                #endif
                if records.isEmpty {
                    emptyState
                } else {
                    recordsList
                }
                privacyFooter
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .background(colors.background.ignoresSafeArea())
        .tint(colors.accent)
        #if os(iOS)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if !records.isEmpty {
                    Button {
                        showDeleteAllConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        #endif
        .onAppear {
                isVisible = true
                refreshRecords()
            }
            .onDisappear {
                isVisible = false
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { _ in
                guard isVisible else { return }
                refreshRecords()
            }
            #else
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                guard isVisible else { return }
                refreshRecords()
            }
            #endif
            .confirmationDialog(
                "Clear All History",
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    TranslationHistoryService.shared.deleteAll()
                    withAnimation {
                        records.removeAll()
                        expandedRecordIDs.removeAll()
                    }
                }
            } message: {
                Text("This action cannot be undone.")
            }
    }

    // MARK: - Header (macOS)

    #if os(macOS)
        private var headerSection: some View {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("History")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(colors.textPrimary)
                    Text("\(records.count) translations")
                        .font(.system(size: 16))
                        .foregroundColor(colors.textSecondary)
                }
                Spacer()
                if !records.isEmpty {
                    Button {
                        showDeleteAllConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    #endif

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(colors.textSecondary.opacity(0.5))
            Text("No history yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(colors.textPrimary)
            Text("Your translations will appear here")
                .font(.system(size: 15))
                .foregroundColor(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Records List

    private var recordsList: some View {
        LazyVStack(spacing: 12) {
            ForEach(records, id: \.id) { record in
                recordCard(record)
            }
        }
    }

    // MARK: - Record Card

    private func recordCard(_ record: TranslationRecord) -> some View {
        let results = record.modelResults
        let hasMultipleModels = results.count > 1
        let isExpanded = expandedRecordIDs.contains(record.id)

        return VStack(alignment: .leading, spacing: 0) {
            sourceSection(record, isExpanded: isExpanded)
            resultsSection(results, hasMultipleModels: hasMultipleModels, isExpanded: isExpanded)
            metadataRow(record, hasMultipleModels: hasMultipleModels, isExpanded: isExpanded)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .background(colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu { cardContextMenu(record) }
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasMultipleModels else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                if isExpanded {
                    expandedRecordIDs.remove(record.id)
                } else {
                    expandedRecordIDs.insert(record.id)
                }
            }
        }
    }

    private func sourceSection(_ record: TranslationRecord, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.sourceText)
                .font(.system(size: 15))
                .foregroundColor(colors.textPrimary)
                .lineLimit(isExpanded ? nil : 3)
            Rectangle()
                .fill(colors.divider)
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func resultsSection(
        _ results: [ModelResult],
        hasMultipleModels: Bool,
        isExpanded: Bool
    ) -> some View {
        if hasMultipleModels, !isExpanded {
            collapsedResult(results[0])
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        } else {
            ForEach(Array(results.enumerated()), id: \.element.id) { idx, modelResult in
                modelResultRow(modelResult, showLabel: hasMultipleModels)
                    .padding(.horizontal, 16)
                if hasMultipleModels, idx < results.count - 1 {
                    Rectangle()
                        .fill(colors.divider.opacity(0.5))
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func cardContextMenu(_ record: TranslationRecord) -> some View {
        if let first = record.modelResults.first {
            Button {
                PasteboardHelper.copy(first.resultText)
            } label: {
                Label("Copy Result", systemImage: "doc.on.doc")
            }
        }
        Button {
            PasteboardHelper.copy(record.sourceText)
        } label: {
            Label("Copy Source", systemImage: "doc.on.doc")
        }
        Divider()
        Button(role: .destructive) {
            TranslationHistoryService.shared.delete(record)
            withAnimation { records.removeAll { $0.id == record.id } }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Model Result Views

    private func collapsedResult(_ result: ModelResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.resultText)
                .font(.system(size: 15))
                .foregroundColor(colors.accent)
                .lineLimit(3)
        }
    }

    private func modelResultRow(_ result: ModelResult, showLabel: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if showLabel {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                    Text(result.modelDisplayName)
                        .font(.system(size: 12, weight: .medium))
                    if result.duration > 0 {
                        Text("· \(String(format: "%.1fs", result.duration))")
                            .font(.system(size: 12))
                    }
                }
                .foregroundColor(colors.textSecondary)
            }
            Text(result.resultText)
                .font(.system(size: 15))
                .foregroundColor(colors.accent)
                .lineLimit(showLabel ? nil : 3)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Metadata Row

    private func metadataRow(
        _ record: TranslationRecord,
        hasMultipleModels: Bool,
        isExpanded: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if !record.actionName.isEmpty {
                MetadataChipView(record.actionName, icon: "bolt.fill")
            }
            if record.isConversation {
                MetadataChipView("Chat", icon: "bubble.left.and.bubble.right.fill")
            }
            if hasMultipleModels {
                let models = record.modelResults
                MetadataChipView(
                    "\(models.count) models",
                    icon: isExpanded ? "chevron.up" : "chevron.down"
                )
            } else if let first = record.modelResults.first, !first.modelDisplayName.isEmpty {
                MetadataChipView(first.modelDisplayName, icon: "cpu")
            }
            Spacer()
            Text(record.timestamp, style: .relative)
                .font(.system(size: 12))
                .foregroundColor(colors.textSecondary)
        }
    }

    // MARK: - Privacy Footer

    private var privacyFooter: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
            Text("All history is stored locally on your device.")
                .font(.system(size: 12))
        }
        .foregroundColor(colors.textSecondary.opacity(0.6))
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func refreshRecords() {
        records = TranslationHistoryService.shared.fetchAll()
    }
}
