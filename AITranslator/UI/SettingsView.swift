//
//  SettingsView.swift
//  TLingo
//
//  Created by Codex on 2025/10/27.
//

import ShareCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
    import AppKit
    import Carbon
#endif

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var preferences: AppPreferences
    @ObservedObject private var configStore = AppConfigurationStore.shared
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var isVoicePickerPresented = false
    @State private var showPaywall = false

    // Configuration import/export state
    @State private var isImportPresented = false
    @State private var isExportPresented = false
    @State private var configurationDocument: ConfigurationDocument?
    @State private var importError: String?
    @State private var showImportError = false
    @State private var showExportSuccess = false
    @State private var showDeleteConfirmation = false
    @State private var configToDelete: ConfigurationFileInfo?
    @State private var configEditorItem: ConfigEditorItem?
    @State private var showResetToDefaultConfirmation = false

    @State private var isShareSheetPresented = false
    @State private var configFileToShare: URL?

    #if DEBUG
        @State private var showNetworkDebug = false
    #endif

    #if os(macOS)
        @ObservedObject private var hotKeyManager = HotKeyManager.shared
        @State private var recordingHotKeyType: HotKeyType?
        @State private var localEventMonitor: Any?
    #endif

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    init(preferences: AppPreferences = .shared) {
        _preferences = ObservedObject(wrappedValue: preferences)
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
        .sheet(isPresented: $isVoicePickerPresented) {
            VoicePickerView(
                isPresented: $isVoicePickerPresented
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        #if DEBUG
        .sheet(isPresented: $showNetworkDebug) {
                NavigationStack {
                    NetworkDebugView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showNetworkDebug = false }
                            }
                        }
                }
                .presentationDetents([.large])
                #if os(macOS)
                    .frame(minWidth: 600, minHeight: 500)
                #endif
            }
        #endif
            .onAppear {
                preferences.refreshFromDefaults()
            }
            .fileImporter(
                isPresented: $isImportPresented,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .fileExporter(
                isPresented: $isExportPresented,
                document: configurationDocument,
                contentType: .json,
                defaultFilename: exportFilename
            ) { result in
                handleExport(result)
            }
            .alert("Import Failed", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "Unknown error")
            }
            .alert("Export Successful", isPresented: $showExportSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Configuration exported successfully.")
            }
            .alert("Delete Configuration?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    configToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let config = configToDelete {
                        deleteConfiguration(config)
                        configToDelete = nil
                    }
                }
            } message: {
                if let config = configToDelete {
                    Text(
                        String(
                            format: NSLocalizedString(
                                "Are you sure you want to delete '%@'? This action cannot be undone.",
                                comment: "Delete configuration confirmation"
                            ),
                            config.name
                        )
                    )
                }
            }
            .alert(
                NSLocalizedString(
                    "Reset to Default?",
                    comment: "Reset configuration confirmation title"
                ),
                isPresented: $showResetToDefaultConfirmation
            ) {
                Button("Cancel", role: .cancel) {}
                Button(
                    NSLocalizedString("Reset", comment: "Reset configuration button"),
                    role: .destructive
                ) {
                    configStore.resetToDefault()
                }
            } message: {
                Text(
                    NSLocalizedString(
                        "This will replace your current actions with the built-in defaults. Any custom changes will be lost.",
                        comment: "Reset configuration confirmation message"
                    )
                )
            }
            .sheet(item: $configEditorItem) { item in
                ConfigurationEditorView(
                    configInfo: item.configInfo,
                    initialText: item.text,
                    colors: colors,
                    onSave: { updatedText in
                        saveEditedConfiguration(updatedText, for: item.configInfo)
                    },
                    onDismiss: {
                        configEditorItem = nil
                    }
                )
            }
        #if os(iOS)
            .sheet(isPresented: $isShareSheetPresented) {
                if let url = configFileToShare {
                    ShareSheet(activityItems: [url])
                }
            }
        #endif
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
        VStack(spacing: 32) {
            // MARK: - Feedback Section

            settingsSection(title: "Feedback", icon: "envelope") {
                feedbackRow
            }

            // MARK: - General Section

            settingsSection(title: "General", icon: "gearshape") {
                VStack(spacing: 0) {
                    subscriptionRow
                    Divider()
                        .padding(.leading, 52)
                    voicePreferenceRow
                    #if DEBUG
                        Divider()
                            .padding(.leading, 52)
                        disableStreamingRow
                    #endif
                    #if os(macOS)
                        Divider()
                            .padding(.leading, 52)
                        hotKeyPreferenceRow
                        Divider()
                            .padding(.leading, 52)
                        keepRunningRow
                    #endif
                }
            }

            // MARK: - Configuration Section

            settingsSection(title: "Configuration", icon: "doc.text") {
                VStack(spacing: 0) {
                    configurationStatusRow
                    Divider()
                        .padding(.leading, 52)
                    configurationActionsRow
                }
            }

            #if DEBUG

                // MARK: - Developer Section

                settingsSection(title: "Developer", icon: "ladybug") {
                    Button {
                        showNetworkDebug = true
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.red.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "network")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.red)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Network Log")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(colors.textPrimary)
                                Text("View all HTTP request history")
                                    .font(.system(size: 13))
                                    .foregroundColor(colors.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colors.textSecondary.opacity(0.5))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            #endif
        }
    }

    // MARK: - Section Builder

    private func settingsSection<Content: View>(
        title: LocalizedStringKey,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.accent)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.horizontal, 4)

            // Section Content
            content()
                .background(sectionCardBackground)
        }
    }

    @ViewBuilder
    private var sectionCardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.clear)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private extension SettingsView {
    // MARK: - Row Style Components

    var voicePreferenceRow: some View {
        Button {
            isVoicePickerPresented = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                    Text(voiceDisplayName)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var voiceDisplayName: String {
        let voiceID = preferences.selectedVoiceID
        // Try to find voice name from defaults, otherwise capitalize the ID
        if let voice = VoiceConfig.defaultVoices.first(where: { $0.id == voiceID }) {
            return voice.name
        }
        return voiceID.capitalized
    }

    var subscriptionRow: some View {
        Button {
            if !storeManager.isPremium {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscription")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                    Text(storeManager.isPremium ? "Premium" : "Free")
                        .font(.system(size: 13))
                        .foregroundColor(storeManager.isPremium ? .orange : colors.textSecondary)
                }

                Spacer()

                if storeManager.isPremium {
                    Text("Active")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.15))
                        )
                } else {
                    Text("Upgrade")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.orange)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var disableStreamingRow: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "bolt.slash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Disable Streaming")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                Text("Receive complete responses at once")
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { preferences.disableStreaming },
                set: { preferences.setDisableStreaming($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    var feedbackRow: some View {
        Button {
            let subject = storeManager.isPremium ? "TLingo%20Feedback%20%5BPremium%5D" : "TLingo%20Feedback"
            if let url = URL(string: "mailto:xiaozwan@outlook.com?subject=\(subject)") {
                #if os(iOS)
                    UIApplication.shared.open(url)
                #elseif os(macOS)
                    NSWorkspace.shared.open(url)
                #endif
            }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "envelope")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.cyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Feedback")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                    Text("Every email gets a reply")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    #if os(macOS)
        var hotKeyPreferenceRow: some View {
            VStack(spacing: 0) {
                ForEach([HotKeyType.mainApp, HotKeyType.quickTranslate], id: \.self) { type in
                    let config = hotKeyManager.configuration(for: type)
                    let isRecording = recordingHotKeyType == type

                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(type == .mainApp ? Color.purple.opacity(0.15) : Color.orange.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: type == .mainApp ? "macwindow" : "bolt.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(type == .mainApp ? .purple : .orange)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.displayName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(colors.textPrimary)
                            Text(type.description)
                                .font(.system(size: 12))
                                .foregroundColor(colors.textSecondary)
                        }

                        Spacer()

                        Button {
                            startRecordingHotKey(for: type)
                        } label: {
                            Text(isRecording ? String(localized: "Press keys...") : config.displayString)
                                .font(.system(size: 13, weight: .medium, design: config.isEmpty ? .default : .monospaced))
                                .foregroundColor(
                                    isRecording ? colors
                                        .accent : (config.isEmpty ? colors.textSecondary : colors.textPrimary)
                                )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isRecording ? colors.accent.opacity(0.15) : colors.inputBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isRecording ? colors.accent : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)

                        if !config.isEmpty {
                            Button {
                                hotKeyManager.clearConfiguration(for: type)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(colors.textSecondary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if type == .mainApp {
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
        }

        private func startRecordingHotKey(for type: HotKeyType) {
            recordingHotKeyType = type

            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [self] event in
                if event.type == .keyDown {
                    let modifiers = event.modifierFlags.carbonModifiers
                    let keyCode = UInt32(event.keyCode)

                    // Escape to cancel
                    if keyCode == 53 {
                        stopRecordingHotKey()
                        return nil
                    }

                    // Need at least one modifier (except for function keys)
                    let isFunctionKey = (keyCode >= 122 && keyCode <= 135) || (keyCode >= 96 && keyCode <= 111)
                    if modifiers == 0, !isFunctionKey {
                        return nil
                    }

                    let config = HotKeyConfiguration(keyCode: keyCode, modifiers: modifiers)
                    hotKeyManager.updateConfiguration(config, for: type)
                    stopRecordingHotKey()
                    return nil
                }
                return event
            }
        }

        private func stopRecordingHotKey() {
            recordingHotKeyType = nil
            if let monitor = localEventMonitor {
                NSEvent.removeMonitor(monitor)
                localEventMonitor = nil
            }
        }

        var keepRunningRow: some View {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.cyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep Running in Menu Bar")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                    Text("App stays active when window is closed")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { preferences.keepRunningWhenClosed },
                    set: { preferences.setKeepRunningWhenClosed($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    #endif

    // MARK: - Configuration Rows

    var configurationStatusRow: some View {
        Button {
            openCurrentConfigurationInEditor()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(colors.accent.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(configStore.currentConfigurationName ?? "Configuration")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.textPrimary)

                    HStack(spacing: 6) {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "%lld Actions",
                                    comment: "Configuration actions count"
                                ),
                                Int64(configStore.actions.count)
                            )
                        )
                    }
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var configurationActionsRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                configActionButton(
                    icon: "square.and.arrow.down",
                    title: "Import Configuration",
                    isAccent: false
                ) {
                    isImportPresented = true
                }

                configActionButton(
                    icon: "square.and.arrow.up",
                    title: "Export Configuration",
                    isAccent: true
                ) {
                    prepareAndExport()
                }
            }

            configActionButton(
                icon: "arrow.counterclockwise",
                title: NSLocalizedString(
                    "Reset to Default",
                    comment: "Button to reset configuration to bundled default"
                ),
                isAccent: false
            ) {
                showResetToDefaultConfirmation = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var exportFilename: String {
        let baseName = configStore.currentConfigurationName ?? "Configuration"
        let sanitized = sanitizeExportFilename(baseName)
        if sanitized.lowercased().hasSuffix(".json") {
            return sanitized
        }
        return "\(sanitized).json"
    }

    private func sanitizeExportFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = name
            .components(separatedBy: invalidCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Configuration" : sanitized
    }

    private func openCurrentConfigurationInEditor() {
        guard let configName = configStore.currentConfigurationName else { return }
        let configURL = ConfigurationFileManager.shared.configurationURL(forName: configName)

        #if os(macOS)
            NSWorkspace.shared.open(configURL)
        #else
            configFileToShare = configURL
            isShareSheetPresented = true
        #endif
    }

    // MARK: - Configuration Helper Functions

    func openConfigEditor(_ config: ConfigurationFileInfo) {
        do {
            let data = try Data(contentsOf: config.url)
            if let jsonString = String(data: data, encoding: .utf8) {
                configEditorItem = ConfigEditorItem(configInfo: config, text: jsonString)
            }
        } catch {
            importError = "Failed to read configuration: \(error.localizedDescription)"
            showImportError = true
        }
    }

    func saveEditedConfiguration(_ text: String, for config: ConfigurationFileInfo) {
        // At this point, validation has already passed in ConfigurationEditorView
        guard let data = text.data(using: .utf8) else {
            return
        }

        do {
            // Write back to file
            try data.write(to: config.url)

            // Close editor only on success
            configEditorItem = nil
        } catch {
            importError = "Failed to save configuration: \(error.localizedDescription)"
            showImportError = true
            // Don't close editor on save failure
        }
    }

    func loadConfiguration(_ config: ConfigurationFileInfo) {
        Logger.debug("[SettingsView] 📂 Loading configuration: '\(config.name)'...")
        do {
            let appConfig = try ConfigurationFileManager.shared.loadConfiguration(from: config.url)
            Logger.debug("[SettingsView]   - Parsed config with \(appConfig.actions.count) actions")
            ConfigurationService.shared.applyConfiguration(
                appConfig,
                to: configStore,
                preferences: preferences,
                configurationName: config.name
            )
            Logger.debug("[SettingsView] ✅ Configuration loaded: '\(config.name)'")
        } catch {
            Logger.debug("[SettingsView] ❌ Failed to load configuration: \(error)")
            importError = error.localizedDescription
            showImportError = true
        }
    }

    func deleteConfiguration(_ config: ConfigurationFileInfo) {
        // Check if we're deleting the currently active configuration
        let isDeletingCurrentConfig = configStore.currentConfigurationName == config.name

        do {
            // If deleting the active configuration, switch to default first
            if isDeletingCurrentConfig {
                configStore.resetToDefault()
            }

            try ConfigurationFileManager.shared.deleteConfiguration(at: config.url)
        } catch {
            importError = error.localizedDescription
            showImportError = true
        }
    }

    func configActionButton(
        icon: String,
        title: String,
        isAccent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isAccent ? colors.accent : colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isAccent ? colors.accent.opacity(0.12) : colors.inputBackground)
            )
        }
        .buttonStyle(.plain)
    }

    func prepareAndExport() {
        let config = ConfigurationService.shared.exportConfiguration(
            from: configStore,
            preferences: preferences
        )
        guard let data = config else { return }

        do {
            configurationDocument = try ConfigurationDocument(data: data)
            isExportPresented = true
        } catch {
            importError = error.localizedDescription
            showImportError = true
        }
    }

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                importError = "Unable to access the selected file."
                showImportError = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let importResult = ConfigurationService.shared.importConfiguration(from: data)

                switch importResult {
                case let .success(config):
                    let baseName = url.deletingPathExtension().lastPathComponent
                    let uniqueName = uniqueConfigurationName(from: baseName)
                    try ConfigurationFileManager.shared.saveConfiguration(config, name: uniqueName)
                    ConfigurationService.shared.applyConfiguration(
                        config,
                        to: configStore,
                        preferences: preferences,
                        configurationName: uniqueName
                    )
                case let .failure(error):
                    importError = error.localizedDescription
                    showImportError = true
                }
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }

        case let .failure(error):
            importError = error.localizedDescription
            showImportError = true
        }
    }

    private func uniqueConfigurationName(from baseName: String) -> String {
        var candidate = baseName
        var counter = 2
        while ConfigurationFileManager.shared.configurationExists(named: candidate) {
            candidate = "\(baseName) \(counter)"
            counter += 1
        }
        return candidate
    }

    func handleExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            showExportSuccess = true
        case let .failure(error):
            importError = error.localizedDescription
            showImportError = true
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}

// MARK: - Configuration Editor View

struct ConfigurationEditorView: View {
    let configInfo: ConfigurationFileInfo
    let initialText: String
    let colors: AppColorPalette
    let onSave: (String) -> Void
    let onDismiss: () -> Void

    @State private var editableText: String
    @State private var hasChanges = false
    @State private var showDiscardAlert = false
    @State private var showValidationError = false
    @State private var validationErrorMessage = ""
    @Environment(\.dismiss) private var dismiss

    init(
        configInfo: ConfigurationFileInfo,
        initialText: String,
        colors: AppColorPalette,
        onSave: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.configInfo = configInfo
        self.initialText = initialText
        self.colors = colors
        self.onSave = onSave
        self.onDismiss = onDismiss
        _editableText = State(initialValue: initialText)
    }

    var body: some View {
        #if os(macOS)
            macOSEditor
        #else
            iOSEditor
        #endif
    }

    #if os(macOS)
        private var macOSEditor: some View {
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(configInfo.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                        Text("Edit JSON configuration")
                            .font(.system(size: 13))
                            .foregroundColor(colors.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            handleCancel()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(colors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(colors.inputBackground)
                        )

                        Button("Save") {
                            validateAndSave()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(colors.accent)
                        )
                        .disabled(!hasChanges)
                        .opacity(hasChanges ? 1 : 0.5)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(colors.cardBackground)

                Divider()

                // Editor
                TextEditor(text: $editableText)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(colors.background)
                    .padding(12)
            }
            .frame(minWidth: 600, minHeight: 500)
            .background(colors.background)
            .onChange(of: editableText) {
                hasChanges = editableText != initialText
            }
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    onDismiss()
                }
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
            .alert("Validation Failed", isPresented: $showValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationErrorMessage)
            }
        }
    #endif

    #if os(iOS)
        private var iOSEditor: some View {
            NavigationStack {
                TextEditor(text: $editableText)
                    .font(.system(size: 14, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(colors.background)
                    .padding(.horizontal, 12)
                    .navigationTitle(configInfo.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                handleCancel()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                validateAndSave()
                            }
                            .disabled(!hasChanges)
                        }
                    }
                    .background(colors.background.ignoresSafeArea())
            }
            .onChange(of: editableText) {
                hasChanges = editableText != initialText
            }
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    onDismiss()
                }
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
            .alert("Validation Failed", isPresented: $showValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationErrorMessage)
            }
        }
    #endif

    private func handleCancel() {
        if hasChanges {
            showDiscardAlert = true
        } else {
            onDismiss()
        }
    }

    private func validateAndSave() {
        // Validate JSON format
        guard let data = editableText.data(using: .utf8) else {
            validationErrorMessage = "Invalid text encoding"
            showValidationError = true
            return
        }

        do {
            // Try to parse JSON
            let config = try JSONDecoder().decode(AppConfiguration.self, from: data)

            // Validate configuration using ConfigurationValidator
            let validationResult = ConfigurationValidator.shared.validate(config)

            if validationResult.hasErrors {
                validationErrorMessage = validationResult.errors.map(\.message).joined(separator: "\n")
                showValidationError = true
                return
            }

            // Show warnings but still allow save
            if validationResult.hasWarnings {
                Logger.debug("[ConfigEditor] ⚠️ Saving with warnings:")
                for warning in validationResult.warnings {
                    Logger.debug("[ConfigEditor]   - \(warning.message)")
                }
            }

            // Call onSave only if validation passed
            onSave(editableText)
        } catch let decodingError as DecodingError {
            // Provide more helpful error messages for JSON errors
            switch decodingError {
            case let .dataCorrupted(context):
                validationErrorMessage = "JSON format error: \(context.debugDescription)"
            case let .keyNotFound(key, context):
                validationErrorMessage =
                    "Missing required field '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case let .typeMismatch(type, context):
                validationErrorMessage =
                    "Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
            case let .valueNotFound(type, context):
                validationErrorMessage =
                    "Missing value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            @unknown default:
                validationErrorMessage = "JSON parsing error: \(decodingError.localizedDescription)"
            }
            showValidationError = true
        } catch {
            validationErrorMessage = "Invalid configuration: \(error.localizedDescription)"
            showValidationError = true
        }
    }
}

// MARK: - Config Editor Item

struct ConfigEditorItem: Identifiable {
    let id = UUID()
    let configInfo: ConfigurationFileInfo
    let text: String
}

// MARK: - NSEvent Modifier Flags Extension

#if os(macOS)
    import Carbon

    extension NSEvent.ModifierFlags {
        var carbonModifiers: UInt32 {
            var modifiers: UInt32 = 0
            if contains(.control) { modifiers |= UInt32(controlKey) }
            if contains(.option) { modifiers |= UInt32(optionKey) }
            if contains(.shift) { modifiers |= UInt32(shiftKey) }
            if contains(.command) { modifiers |= UInt32(cmdKey) }
            return modifiers
        }
    }
#endif

// MARK: - Share Sheet (iOS)

#if os(iOS)
    import UIKit

    struct ShareSheet: UIViewControllerRepresentable {
        let activityItems: [Any]

        func makeUIViewController(context _: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        }

        func updateUIViewController(_: UIActivityViewController, context _: Context) {}
    }
#endif
