//
//  LanguagePickerView.swift
//  ShareCore
//
//  Created by AI Assistant on 2026/01/22.
//

import SwiftUI

/// Defines whether the picker is selecting a source or target language.
public enum LanguagePickerMode {
    case source
    case target
}

/// A row model that unifies source and target language options for display.
private struct LanguageRow: Identifiable {
    let id: String // rawValue
    let primaryLabel: String
    let secondaryLabel: String
}

/// A reusable language picker view that can be presented as a sheet.
/// Supports both source language (with Auto option) and target language selection.
public struct LanguagePickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedCode: String
    @Binding var isPresented: Bool
    let mode: LanguagePickerMode

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    private var title: String {
        switch mode {
        case .source: return "Select Source Language"
        case .target: return "Select Target Language"
        }
    }

    private var rows: [LanguageRow] {
        switch mode {
        case .source:
            return SourceLanguageOption.selectionOptions.map { option in
                LanguageRow(id: option.rawValue, primaryLabel: option.primaryLabel, secondaryLabel: option.secondaryLabel)
            }
        case .target:
            return TargetLanguageOption.selectionOptions.map { option in
                LanguageRow(id: option.rawValue, primaryLabel: option.primaryLabel, secondaryLabel: option.secondaryLabel)
            }
        }
    }

    public init(selectedCode: Binding<String>, isPresented: Binding<Bool>, mode: LanguagePickerMode = .target) {
        _selectedCode = selectedCode
        _isPresented = isPresented
        self.mode = mode
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
