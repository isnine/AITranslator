//
//  SettingsView.swift
//  AITranslator
//
//  Created by Codex on 2025/10/27.
//

import SwiftUI
import ShareCore

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(TargetLanguageOption.storageKey, store: AppPreferences.sharedDefaults) private var targetLanguageCode: String = TargetLanguageOption.appLanguage.rawValue
    @State private var isLanguagePickerPresented = false

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    private var selectedOption: TargetLanguageOption {
        TargetLanguageOption(rawValue: targetLanguageCode) ?? .appLanguage
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    preferencesSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
            .background(colors.background.ignoresSafeArea())
            .navigationTitle("")
#if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
        .tint(colors.accent)
        .sheet(isPresented: $isLanguagePickerPresented) {
            LanguagePickerView(
                selectedCode: $targetLanguageCode,
                isPresented: $isLanguagePickerPresented
            )
        }
        .onAppear {
            AppPreferences.shared.refreshFromDefaults()
        }
        .onChange(of: targetLanguageCode) { newValue in
            let option = TargetLanguageOption(rawValue: newValue) ?? .appLanguage
            AppPreferences.shared.setTargetLanguage(option)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("设置")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(colors.textPrimary)

            Text("应用偏好设置")
                .font(.system(size: 15))
                .foregroundColor(colors.textSecondary)
        }
    }

    private var preferencesSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                Button {
                    isLanguagePickerPresented = true
                } label: {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("目标翻译语言")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colors.textPrimary)
                            LanguageValueView(option: selectedOption, colors: colors)
                        }

                        Spacer(minLength: 12)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colors.textSecondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colors.cardBackground)
            )
        }
    }
}

private struct LanguageValueView: View {
    let option: TargetLanguageOption
    let colors: AppColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(option.primaryLabel)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(colors.textPrimary)
            Text(option.secondaryLabel)
                .font(.system(size: 13))
                .foregroundColor(colors.textSecondary)
        }
    }
}

private struct LanguagePickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedCode: String
    @Binding var isPresented: Bool

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
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
            .navigationTitle("选择目标语言")
#if os(iOS)
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        isPresented = false
                    }
                }
            }
        }
        .tint(colors.accent)
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
