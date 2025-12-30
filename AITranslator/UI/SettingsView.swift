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
    @AppStorage(TargetLanguageOption.storageKey, store: AppPreferences.sharedDefaults)
    private var targetLanguageCode: String = TargetLanguageOption.appLanguage.rawValue
    @ObservedObject private var preferences: AppPreferences
    @State private var isLanguagePickerPresented = false
    @State private var customTTSEndpoint: String
    @State private var customTTSAPIKey: String

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    private var selectedOption: TargetLanguageOption {
        TargetLanguageOption(rawValue: targetLanguageCode) ?? .appLanguage
    }

    init(preferences: AppPreferences = .shared) {
        let configuration = preferences.ttsUsesDefaultConfiguration ? TTSConfiguration.default : preferences.ttsConfiguration
        _preferences = ObservedObject(wrappedValue: preferences)
        _customTTSEndpoint = State(initialValue: configuration.endpointURL.absoluteString)
        _customTTSAPIKey = State(initialValue: configuration.apiKey)
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
            preferences.refreshFromDefaults()
            syncTTSPreferencesFromStore()
        }
        .onChange(of: targetLanguageCode) {
            let option = TargetLanguageOption(rawValue: targetLanguageCode) ?? .appLanguage
            preferences.setTargetLanguage(option)
        }
        .onChange(of: customTTSEndpoint) {
            persistCustomTTSConfiguration()
        }
        .onChange(of: customTTSAPIKey) {
            persistCustomTTSConfiguration()
        }
        .onReceive(preferences.$ttsUsesDefaultConfiguration) { _ in
            syncTTSPreferencesFromStore()
        }
        .onReceive(preferences.$ttsConfiguration) { _ in
            guard !isUsingDefaultTTS else { return }
            syncTTSPreferencesFromStore()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(colors.textPrimary)

            Text("App Preferences")
                .font(.system(size: 15))
                .foregroundColor(colors.textSecondary)
        }
    }

    private var preferencesSection: some View {
        VStack(spacing: 16) {
            languagePreferenceCard
            ttsPreferenceCard
        }
    }
}

private extension SettingsView {
    var isUsingDefaultTTS: Bool {
        preferences.ttsUsesDefaultConfiguration
    }

    var defaultToggleBinding: Binding<Bool> {
        Binding(
            get: { preferences.ttsUsesDefaultConfiguration },
            set: { newValue in
                preferences.setTTSUsesDefaultConfiguration(newValue)
                if newValue {
                    customTTSEndpoint = TTSConfiguration.default.endpointURL.absoluteString
                    customTTSAPIKey = TTSConfiguration.default.apiKey
                } else {
                    syncTTSPreferencesFromStore()
                }
            }
        )
    }

    var languagePreferenceCard: some View {
        VStack(spacing: 0) {
            Button {
                isLanguagePickerPresented = true
            } label: {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Target Language")
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

    var ttsPreferenceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TTS Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Text("Configure Azure speech endpoint and API Key for reading translations aloud.")
                    .font(.system(size: 13))
                    .foregroundColor(colors.textSecondary)
            }

            Toggle("Use Default Configuration", isOn: defaultToggleBinding)
                .font(.system(size: 14, weight: .medium))
                .tint(colors.accent)

            VStack(alignment: .leading, spacing: 12) {
                Text("Custom Endpoint")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)

                TextField("https://...", text: $customTTSEndpoint)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .foregroundColor(colors.textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colors.inputBackground)
                    )
                    .disabled(isUsingDefaultTTS)
                    .autocorrectionDisabled()
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
#endif

                Text("API Key")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)

                SecureField("Enter Azure Key here", text: $customTTSAPIKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .foregroundColor(colors.textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colors.inputBackground)
                    )
                    .disabled(isUsingDefaultTTS)
                    .autocorrectionDisabled()
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .textContentType(.password)
#endif
            }
            .opacity(isUsingDefaultTTS ? 0.55 : 1)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colors.cardBackground)
        )
    }

    func persistCustomTTSConfiguration() {
        guard !isUsingDefaultTTS else { return }

        let trimmedEndpoint = customTTSEndpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEndpoint.isEmpty, let endpointURL = URL(string: trimmedEndpoint) else {
            return
        }

        let trimmedKey = customTTSAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuration = TTSConfiguration(
            endpointURL: endpointURL,
            apiKey: trimmedKey
        )

        customTTSEndpoint = trimmedEndpoint
        customTTSAPIKey = trimmedKey
        preferences.setTTSConfiguration(configuration)
    }

    func syncTTSPreferencesFromStore() {
        if isUsingDefaultTTS {
            customTTSEndpoint = TTSConfiguration.default.endpointURL.absoluteString
            customTTSAPIKey = TTSConfiguration.default.apiKey
        } else {
            let configuration = preferences.ttsConfiguration
            customTTSEndpoint = configuration.endpointURL.absoluteString
            customTTSAPIKey = configuration.apiKey
        }
    }

    struct LanguageValueView: View {
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

    struct LanguagePickerView: View {
        @Environment(\.colorScheme) private var colorScheme
        @Binding var selectedCode: String
        @Binding var isPresented: Bool

        private var colors: AppColorPalette {
            AppColors.palette(for: colorScheme)
        }

        var body: some View {
#if os(macOS)
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
#else
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
#if os(iOS)
                .listStyle(.insetGrouped)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                }
            }
            .tint(colors.accent)
#endif
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
