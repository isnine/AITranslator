//
//  SettingsView.swift
//  AITranslator
//
//  Created by Codex on 2025/10/27.
//

import SwiftUI
import ShareCore
import UniformTypeIdentifiers
#if os(macOS)
import Carbon
#endif

struct SettingsView: View {
  @Environment(\.colorScheme) private var colorScheme
  @AppStorage(TargetLanguageOption.storageKey, store: AppPreferences.sharedDefaults)
  private var targetLanguageCode: String = TargetLanguageOption.appLanguage.rawValue
  @ObservedObject private var preferences: AppPreferences
  @ObservedObject private var configStore = AppConfigurationStore.shared
  @State private var isLanguagePickerPresented = false
  @State private var customTTSEndpoint: String
  @State private var customTTSAPIKey: String

  // Configuration import/export state
  @State private var isImportPresented = false
  @State private var isExportPresented = false
  @State private var configurationDocument: ConfigurationDocument?
  @State private var importError: String?
  @State private var showImportError = false
  @State private var showExportSuccess = false
  @State private var savedConfigurations: [ConfigurationFileInfo] = []
  @State private var showDeleteConfirmation = false
  @State private var configToDelete: ConfigurationFileInfo?
  @State private var showSaveDialog = false
  @State private var newConfigName = ""
  @State private var configEditorItem: ConfigEditorItem?
  
  // Collapsible section states
  @State private var isSavedConfigsExpanded = false
  @State private var isTTSAdvancedExpanded = false

  #if os(macOS)
  @ObservedObject private var hotKeyManager = HotKeyManager.shared
  @State private var isRecordingHotKey = false
  @State private var localEventMonitor: Any?
  #endif

  private var colors: AppColorPalette {
    AppColors.palette(for: colorScheme)
  }

  private var selectedOption: TargetLanguageOption {
    TargetLanguageOption(rawValue: targetLanguageCode) ?? .appLanguage
  }

  init(preferences: AppPreferences = .shared) {
    // Always show the actual stored custom TTS configuration (not the hardcoded default)
    let configuration = preferences.ttsConfiguration
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
            defaultFilename: "tree2lang-config.json"
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
      configurationCard
      languagePreferenceCard
      #if os(macOS)
      hotKeyPreferenceCard
      #endif
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
        // Always sync from store to show the actual stored custom values
        syncTTSPreferencesFromStore()
      }
    )
  }

  #if os(macOS)
  var hotKeyPreferenceCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Global Shortcut")
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(colors.textPrimary)
        Text("Press the shortcut to show/hide the app window from anywhere.")
          .font(.system(size: 13))
          .foregroundColor(colors.textSecondary)
      }

      HStack {
        Text("Shortcut")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(colors.textPrimary)

        Spacer()

        Button {
          startRecordingHotKey()
        } label: {
          Text(isRecordingHotKey ? "Press keys..." : hotKeyManager.configuration.displayString)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundColor(isRecordingHotKey ? colors.accent : colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isRecordingHotKey ? colors.accent.opacity(0.15) : colors.inputBackground)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isRecordingHotKey ? colors.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)

        if hotKeyManager.configuration != .default {
          Button {
            hotKeyManager.updateConfiguration(.default)
          } label: {
            Image(systemName: "arrow.counterclockwise")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(colors.textSecondary)
          }
          .buttonStyle(.plain)
          .help("Reset to default (⌥T)")
        }
      }
    }
    .padding(18)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(colors.cardBackground)
    )
  }

  func startRecordingHotKey() {
    isRecordingHotKey = true

    // 临时注销快捷键以便捕获新按键
    HotKeyManager.shared.unregister()

    localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      self.handleKeyEvent(event)
      return nil
    }
  }

  func stopRecordingHotKey() {
    isRecordingHotKey = false

    if let monitor = localEventMonitor {
      NSEvent.removeMonitor(monitor)
      localEventMonitor = nil
    }

    // 重新注册快捷键
    HotKeyManager.shared.register()
  }

  func handleKeyEvent(_ event: NSEvent) {
    // 忽略纯修饰键按下
    let keyCode = event.keyCode

    // 检查是否按下了 Escape 取消录制
    if keyCode == UInt16(kVK_Escape) {
      stopRecordingHotKey()
      return
    }

    // 需要至少一个修饰键
    let modifierFlags = event.modifierFlags
    var carbonModifiers: UInt32 = 0

    if modifierFlags.contains(.command) {
      carbonModifiers |= UInt32(cmdKey)
    }
    if modifierFlags.contains(.option) {
      carbonModifiers |= UInt32(optionKey)
    }
    if modifierFlags.contains(.control) {
      carbonModifiers |= UInt32(controlKey)
    }
    if modifierFlags.contains(.shift) {
      carbonModifiers |= UInt32(shiftKey)
    }

    // 至少需要一个修饰键 (Command, Option, Control)
    let hasRequiredModifier = modifierFlags.contains(.command)
      || modifierFlags.contains(.option)
      || modifierFlags.contains(.control)

    guard hasRequiredModifier else { return }

    let newConfiguration = HotKeyConfiguration(
      keyCode: UInt32(keyCode),
      modifiers: carbonModifiers
    )

    hotKeyManager.updateConfiguration(newConfiguration)
    stopRecordingHotKey()
  }
  #endif

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
            // Header with toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TTS Settings")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text(isUsingDefaultTTS ? "Using default configuration" : "Custom configuration")
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }
                Spacer()
                Toggle("", isOn: defaultToggleBinding)
                    .labelsHidden()
                    .tint(colors.accent)
            }

            // Collapsible advanced settings
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isTTSAdvancedExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isTTSAdvancedExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colors.textSecondary)
                            .frame(width: 16)
                        
                        Text("Advanced Settings")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.textPrimary)
                        
                        Spacer()
                        
                        if !isUsingDefaultTTS {
                            Text("Custom")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(colors.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(colors.accent.opacity(0.12))
                                )
                        }
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if isTTSAdvancedExpanded {
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
                    .padding(.leading, 26)
                    .padding(.bottom, 8)
                    .opacity(isUsingDefaultTTS ? 0.55 : 1)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colors.inputBackground.opacity(0.5))
            )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colors.cardBackground)
        )
    }

    var configurationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row with current config info
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Configuration")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    
                    HStack(spacing: 8) {
                        if let currentName = configStore.currentConfigurationName {
                            Text(currentName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colors.accent)
                        }
                        Text("·")
                            .foregroundColor(colors.textSecondary)
                        Text("\(configStore.providers.count) Provider")
                            .font(.system(size: 13))
                            .foregroundColor(colors.textSecondary)
                        Text("·")
                            .foregroundColor(colors.textSecondary)
                        Text("\(configStore.actions.count) Actions")
                            .font(.system(size: 13))
                            .foregroundColor(colors.textSecondary)
                    }
                }
                Spacer()
            }

            // Primary action buttons - only Import & Export
            HStack(spacing: 10) {
                configActionButton(
                    icon: "square.and.arrow.down",
                    title: "Import",
                    isAccent: true
                ) {
                    isImportPresented = true
                }

                configActionButton(
                    icon: "square.and.arrow.up",
                    title: "Export",
                    isAccent: false
                ) {
                    prepareAndExport()
                }
            }

            // Collapsible Saved Configurations section
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSavedConfigsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isSavedConfigsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colors.textSecondary)
                            .frame(width: 16)
                        
                        Text("Saved Configurations")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.textPrimary)
                        
                        if !savedConfigurations.isEmpty {
                            Text("(\(savedConfigurations.count))")
                                .font(.system(size: 13))
                                .foregroundColor(colors.textSecondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if isSavedConfigsExpanded {
                    VStack(spacing: 8) {
                        // Quick action buttons
                        HStack(spacing: 8) {
                            Button {
                                duplicateCurrentConfiguration()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Duplicate")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(colors.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(colors.accent.opacity(0.12))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(configStore.currentConfigurationName == nil)
                            
                            Button {
                                createEmptyTemplate()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.badge.plus")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("New Empty")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(colors.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(colors.inputBackground)
                                )
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                        }
                        .padding(.bottom, 4)
                        
                        if savedConfigurations.isEmpty {
                            Text("No saved configurations")
                                .font(.system(size: 13))
                                .foregroundColor(colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(savedConfigurations) { config in
                                savedConfigurationRow(config)
                            }
                        }
                    }
                    .padding(.leading, 26)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colors.inputBackground.opacity(0.5))
            )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colors.cardBackground)
        )
        .onAppear {
            refreshSavedConfigurations()
        }
        .alert("Delete Configuration", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let config = configToDelete {
                    deleteConfiguration(config)
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(configToDelete?.name ?? "")\"?")
        }
    }

    func savedConfigurationRow(_ config: ConfigurationFileInfo) -> some View {
        let isCurrentConfig = configStore.currentConfigurationName == config.name
        
        return HStack(spacing: 12) {
            // Tappable area to open editor
            Button {
                openConfigEditor(config)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isCurrentConfig ? "doc.text.fill" : "doc.text")
                        .font(.system(size: 14))
                        .foregroundColor(colors.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(config.name)
                                .font(.system(size: 14, weight: isCurrentConfig ? .semibold : .medium))
                                .foregroundColor(colors.textPrimary)
                            
                            if isCurrentConfig {
                                Text("Current")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(colors.accent)
                                    )
                            }
                        }
                        Text(config.formattedDate)
                            .font(.system(size: 11))
                            .foregroundColor(colors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                loadConfiguration(config)
            } label: {
                Text("Load")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colors.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(colors.accent.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)

            Button {
                configToDelete = config
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.red.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrentConfig ? colors.accent.opacity(0.08) : colors.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isCurrentConfig ? colors.accent.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
    }

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
        // Validate JSON first
        guard let data = text.data(using: .utf8) else {
            importError = "Invalid text encoding"
            showImportError = true
            return
        }
        
        do {
            // Try to parse to validate
            _ = try JSONDecoder().decode(AppConfiguration.self, from: data)
            
            // Write back to file
            try data.write(to: config.url)
            
            refreshSavedConfigurations()
            configEditorItem = nil
        } catch {
            importError = "Invalid configuration: \(error.localizedDescription)"
            showImportError = true
        }
    }

    func refreshSavedConfigurations() {
        savedConfigurations = ConfigurationFileManager.shared.listConfigurations()
    }

    func duplicateCurrentConfiguration() {
        guard let currentName = configStore.currentConfigurationName else { return }
        
        // Find the current configuration in the list
        guard let currentConfig = savedConfigurations.first(where: { $0.name == currentName }) else {
            importError = "Current configuration not found"
            showImportError = true
            return
        }
        
        do {
            _ = try ConfigurationFileManager.shared.duplicateConfiguration(from: currentConfig.url)
            refreshSavedConfigurations()
        } catch {
            importError = error.localizedDescription
            showImportError = true
        }
    }

    func loadConfiguration(_ config: ConfigurationFileInfo) {
        do {
            let appConfig = try ConfigurationFileManager.shared.loadConfiguration(from: config.url)
            ConfigurationService.shared.applyConfiguration(
                appConfig,
                to: configStore,
                preferences: preferences,
                configurationName: config.name
            )
        } catch {
            importError = error.localizedDescription
            showImportError = true
        }
    }

    func deleteConfiguration(_ config: ConfigurationFileInfo) {
        do {
            try ConfigurationFileManager.shared.deleteConfiguration(at: config.url)
            refreshSavedConfigurations()
        } catch {
            importError = error.localizedDescription
            showImportError = true
        }
    }

    func createEmptyTemplate() {
        do {
            _ = try ConfigurationFileManager.shared.createEmptyTemplate()
            refreshSavedConfigurations()
        } catch {
            importError = error.localizedDescription
            showImportError = true
        }
    }

    func configStatView(count: Int, label: String) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(colors.accent)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(colors.textSecondary)
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
        case .success(let urls):
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
                case .success(let config):
                    ConfigurationService.shared.applyConfiguration(
                        config,
                        to: configStore,
                        preferences: preferences
                    )
                case .failure(let error):
                    importError = error.localizedDescription
                    showImportError = true
                }
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }

        case .failure(let error):
            importError = error.localizedDescription
            showImportError = true
        }
    }

    func handleExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            showExportSuccess = true
        case .failure(let error):
            importError = error.localizedDescription
            showImportError = true
        }
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
        // Always show the actual stored custom TTS configuration values
        // This allows user to see what custom values are saved (even when using defaults)
        let configuration = preferences.ttsConfiguration
        customTTSEndpoint = configuration.endpointURL.absoluteString
        customTTSAPIKey = configuration.apiKey
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
        self._editableText = State(initialValue: initialText)
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
                        onSave(editableText)
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
                            onSave(editableText)
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
    }
    #endif

    private func handleCancel() {
        if hasChanges {
            showDiscardAlert = true
        } else {
            onDismiss()
        }
    }
}

// MARK: - Config Editor Item

struct ConfigEditorItem: Identifiable {
    let id = UUID()
    let configInfo: ConfigurationFileInfo
    let text: String
}
