//
//  LanguagePickerView.swift
//  ShareCore
//
//  Created by AI Assistant on 2026/01/22.
//

import SwiftUI

/// A reusable language picker view that can be presented as a sheet
public struct LanguagePickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedCode: String
    @Binding var isPresented: Bool

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    public init(selectedCode: Binding<String>, isPresented: Binding<Bool>) {
        _selectedCode = selectedCode
        _isPresented = isPresented
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
                Text("Select Target Language")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(TargetLanguageOption.selectionOptions) { option in
                            Button {
                                selectedCode = option.rawValue
                                isPresented = false
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.primaryLabel)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(colors.textPrimary)
                                        Text(option.secondaryLabel)
                                            .font(.system(size: 13))
                                            .foregroundColor(colors.textSecondary)
                                    }

                                    Spacer()

                                    if selectedCode == option.rawValue {
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
                        ForEach(TargetLanguageOption.selectionOptions) { option in
                            Button {
                                selectedCode = option.rawValue
                                isPresented = false
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.primaryLabel)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(colors.textPrimary)
                                        Text(option.secondaryLabel)
                                            .font(.system(size: 13))
                                            .foregroundColor(colors.textSecondary)
                                    }

                                    Spacer()

                                    if selectedCode == option.rawValue {
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
                .navigationTitle("Select Target Language")
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
