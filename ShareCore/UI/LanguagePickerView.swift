//
//  LanguagePickerView.swift
//  ShareCore
//
//  Created by AI Assistant on 2026/01/22.
//

import SwiftUI

/// A row model for language option display.
public struct LanguageRow: Identifiable {
    public let id: String
    public let primaryLabel: String
    public let secondaryLabel: String

    public init(id: String, primaryLabel: String, secondaryLabel: String) {
        self.id = id
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
    }
}

/// A language picker view presented as a sheet. Accepts generic LanguageRow data.
public struct LanguagePickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedCode: String
    @Binding var isPresented: Bool
    private let rows: [LanguageRow]
    private let title: String

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    /// Generic initialiser — caller provides rows and an optional title.
    public init(
        selectedCode: Binding<String>,
        isPresented: Binding<Bool>,
        rows: [LanguageRow],
        title: String = String(localized: "Select Language")
    ) {
        _selectedCode = selectedCode
        _isPresented = isPresented
        self.rows = rows
        self.title = title
    }

    /// Convenience initialiser for target language options.
    public init(
        selectedCode: Binding<String>,
        isPresented: Binding<Bool>,
        availableOptions: [TargetLanguageOption]? = nil,
        title: String = String(localized: "Select Target Language")
    ) {
        _selectedCode = selectedCode
        _isPresented = isPresented
        let options = availableOptions ?? TargetLanguageOption.selectionOptions
        self.rows = options.map { LanguageRow(id: $0.rawValue, primaryLabel: $0.primaryLabel, secondaryLabel: $0.secondaryLabel) }
        self.title = title
    }

    public var body: some View {
        #if os(macOS)
            macOSPicker
        #else
            iOSPicker
        #endif
    }

    #if os(macOS)
        private var macOSPicker: some View {
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(rows) { row in
                            Button {
                                selectedCode = row.id
                                isPresented = false
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.primaryLabel)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(colors.textPrimary)
                                        Text(row.secondaryLabel)
                                            .font(.system(size: 13))
                                            .foregroundColor(colors.textSecondary)
                                    }

                                    Spacer()

                                    if selectedCode == row.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(colors.accent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(colors.cardBackground)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(colors.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colors.accent.opacity(0.12))
                    )
                }
            }
            .padding(24)
            .frame(minWidth: 420, minHeight: 380)
            .background(colors.background)
        }
    #endif

    #if os(iOS)
        private var iOSPicker: some View {
            NavigationStack {
                List {
                    Section {
                        ForEach(rows) { row in
                            Button {
                                selectedCode = row.id
                                isPresented = false
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.primaryLabel)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(colors.textPrimary)
                                        Text(row.secondaryLabel)
                                            .font(.system(size: 13))
                                            .foregroundColor(colors.textSecondary)
                                    }

                                    Spacer()

                                    if selectedCode == row.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(colors.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(colors.cardBackground)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(colors.background.ignoresSafeArea())
                .navigationTitle(title)
                .listStyle(.insetGrouped)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                }
            }
            .tint(colors.accent)
        }
    #endif
}
