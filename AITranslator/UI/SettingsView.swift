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
  @State private var customTTSModel: String
  @State private var customTTSVoice: String
  @State private var ttsUseBuiltInCloud: Bool

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
  @State private var isStorageSettingsExpanded = false
  
  // Storage location state for UI refresh
  @State private var currentStorageLocation: ConfigurationFileManager.StorageLocation = .local
  
  // Sync control flag to prevent update loops
  @State private var isUpdatingFromPreferences = false

  #if os(macOS)
  @ObservedObject private var hotKeyManager = HotKeyManager.shared
  @State private var recordingHotKeyType: HotKeyType?
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
    _customTTSModel = State(initialValue: configuration.model)
    _customTTSVoice = State(initialValue: configuration.voice)
    _ttsUseBuiltInCloud = State(initialValue: configuration.useBuiltInCloud)
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
            guard !isUpdatingFromPreferences else { return }
            persistCustomTTSConfiguration()
        }
        .onChange(of: customTTSAPIKey) {
            guard !isUpdatingFromPreferences else { return }
            persistCustomTTSConfiguration()
        }
        .onChange(of: customTTSModel) {
            guard !isUpdatingFromPreferences else { return }
            persistCustomTTSConfiguration()
        }
        .onChange(of: customTTSVoice) {
            guard !isUpdatingFromPreferences else { return }
            persistCustomTTSConfiguration()
        }
        .onChange(of: ttsUseBuiltInCloud) {
            guard !isUpdatingFromPreferences else { return }
            persistCustomTTSConfiguration()
        }
        .onReceive(preferences.$ttsConfiguration) { _ in
            // Always sync TTS configuration to UI when it changes
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
  #if os(macOS)
  var hotKeyPreferenceCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Global Shortcuts")
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(colors.textPrimary)
        Text("Press shortcuts to show/hide windows from anywhere.")
          .font(.system(size: 13))
          .foregroundColor(colors.textSecondary)
      }

      // Main App Shortcut
      hotKeyRow(for: .mainApp)

      // Quick Translate Shortcut
      hotKeyRow(for: .quickTranslate)
    }
    .padding(18)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(colors.cardBackground)
    )
  }

  @ViewBuilder
  func hotKeyRow(for type: HotKeyType) -> some View {
    let config = hotKeyManager.configuration(for: type)
    let isRecording = recordingHotKeyType == type

    VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(type.displayName)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(colors.textPrimary)
          Text(type.description)
            .font(.system(size: 12))
            .foregroundColor(colors.textSecondary)
        }

        Spacer()

        Button {
          startRecordingHotKey(for: type)
        } label: {
          Text(isRecording ? "Press keys..." : config.displayString)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundColor(isRecording ? colors.accent : colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isRecording ? colors.accent.opacity(0.15) : colors.inputBackground)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isRecording ? colors.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)

        if !config.isEmpty {
          Button {
            hotKeyManager.clearConfiguration(for: type)
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(colors.textSecondary)
          }
          .buttonStyle(.plain)
          .help("Clear shortcut")
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(colors.inputBackground.opacity(0.5))
    )
  }

  func startRecordingHotKey(for type: HotKeyType) {
    recordingHotKeyType = type

    // 临时注销快捷键以便捕获新按键
    HotKeyManager.shared.unregister()

    localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      self.handleKeyEvent(event, for: type)
      return nil
    }
  }

  func stopRecordingHotKey() {
    recordingHotKeyType = nil

    if let monitor = localEventMonitor {
      NSEvent.removeMonitor(monitor)
      localEventMonitor = nil
    }

    // 重新注册快捷键
    HotKeyManager.shared.register()
  }

  func handleKeyEvent(_ event: NSEvent, for type: HotKeyType) {
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

    hotKeyManager.updateConfiguration(newConfiguration, for: type)
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
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("TTS Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Text("Configure text-to-speech for reading results aloud.")
                    .font(.system(size: 13))
                    .foregroundColor(colors.textSecondary)
            }

            // Built-in Cloud Toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use Built-in Cloud")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                    Text("Free TTS service powered by the app")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                }
                Spacer()
                Toggle("", isOn: $ttsUseBuiltInCloud)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colors.inputBackground)
            )

            // TTS configuration fields
            VStack(alignment: .leading, spacing: 12) {
                if ttsUseBuiltInCloud {
                    // Built-in Cloud mode: only show voice picker
                    Text("Voice")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.textSecondary)

                    Menu {
                        ForEach(TTSConfiguration.builtInCloudVoices, id: \.self) { voice in
                            Button(action: {
                                customTTSVoice = voice
                            }) {
                                HStack {
                                    Text(voice.capitalized)
                                    if customTTSVoice == voice {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(customTTSVoice.isEmpty ? "Select a voice" : customTTSVoice.capitalized)
                                .font(.system(size: 14))
                                .foregroundColor(customTTSVoice.isEmpty ? colors.textSecondary : colors.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(colors.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(colors.inputBackground)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    // Custom mode: show all fields
                    Text("Endpoint")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.textSecondary)

                    ZStack(alignment: .leading) {
                        if customTTSEndpoint.isEmpty || customTTSEndpoint == "https://" || customTTSEndpoint == TTSConfiguration.builtInCloudEndpoint.absoluteString {
                            Text("https://xxx.openai.azure.com/openai/deployments/gpt-4o-mini-tts/audio/speech?api-version=2025-03-01-preview")
                                .font(.system(size: 14))
                                .foregroundColor(colors.textSecondary.opacity(0.6))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        TextField("", text: Binding(
                            get: {
                                // Don't show built-in cloud endpoint in custom mode
                                if customTTSEndpoint == TTSConfiguration.builtInCloudEndpoint.absoluteString {
                                    return ""
                                }
                                return customTTSEndpoint == "https://" ? "" : customTTSEndpoint
                            },
                            set: { customTTSEndpoint = $0 }
                        ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundColor(colors.textPrimary)
                            .autocorrectionDisabled()
#if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
#endif
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colors.inputBackground)
                    )

                    Text("API Key")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.textSecondary)

                    SecureField("Enter API Key here", text: $customTTSAPIKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .foregroundColor(colors.textPrimary)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(colors.inputBackground)
                        )
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .textContentType(.password)
#endif

                    Text("Model")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.textSecondary)

                    TextField("e.g. gpt-4o-mini-tts", text: $customTTSModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .foregroundColor(colors.textPrimary)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(colors.inputBackground)
                        )
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif

                    Text("Voice")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.textSecondary)

                    TextField("e.g. alloy", text: $customTTSVoice)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .foregroundColor(colors.textPrimary)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(colors.inputBackground)
                        )
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                }
            }
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
                        // Show configuration mode
                        Text(configStore.configurationMode.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(configStore.configurationMode.isDefault ? colors.success : colors.accent)
                        
                        if configStore.configurationMode.isDefault {
                            Text("Read-Only")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(colors.success)
                                )
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

            // Default configuration info banner (when using default)
            if configStore.configurationMode.isDefault {
                defaultConfigurationBanner
            }

            // Saved Configurations section (displayed directly without collapsing)
            VStack(spacing: 8) {
                // Quick action buttons
                HStack(spacing: 8) {
                    // Use Default button (only show when using custom config)
                    if !configStore.configurationMode.isDefault {
                        Button {
                            configStore.switchToDefaultConfiguration()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Use Default")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(colors.success)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(colors.success.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
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
                    .disabled(configStore.configurationMode.isDefault)
                    .opacity(configStore.configurationMode.isDefault ? 0.5 : 1)
                    
                    Button {
                        createFromDefaultTemplate()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 12, weight: .medium))
                            Text("New")
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
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colors.inputBackground.opacity(0.5))
            )

            // Storage Location Settings
            storageLocationSection
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

    var defaultConfigurationBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 20))
                    .foregroundColor(colors.success)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Using Default Configuration")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text("Always up-to-date with the latest app features")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                }
                
                Spacer()
            }
            
            Text("The default configuration is bundled with the app and cannot be edited. To customize your settings, create a new configuration or load an existing one.")
                .font(.system(size: 12))
                .foregroundColor(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.success.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(colors.success.opacity(0.2), lineWidth: 1)
        )
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
        // At this point, validation has already passed in ConfigurationEditorView
        guard let data = text.data(using: .utf8) else {
            return
        }

        do {
            // Write back to file
            try data.write(to: config.url)

            // Refresh saved configurations list
            refreshSavedConfigurations()

            // Close editor only on success
            configEditorItem = nil
        } catch {
            importError = "Failed to save configuration: \(error.localizedDescription)"
            showImportError = true
            // Don't close editor on save failure
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

    func createFromDefaultTemplate() {
        do {
            _ = try ConfigurationFileManager.shared.createFromDefaultTemplate()
            refreshSavedConfigurations()
        } catch {
            importError = error.localizedDescription
            showImportError = true
        }
    }

    // MARK: - Storage Location Section

    var storageLocationSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isStorageSettingsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isStorageSettingsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colors.textSecondary)
                        .frame(width: 16)
                    
                    Text("Storage Location")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                    
                    Spacer()
                    
                    // Current location indicator
                    HStack(spacing: 4) {
                        Image(systemName: currentStorageLocation.icon)
                            .font(.system(size: 11))
                        Text(currentStorageLocation.rawValue)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(colors.accent)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isStorageSettingsExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose where to store your configuration files.")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                        .padding(.bottom, 4)
                    
                    // Current path display
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Path")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colors.textSecondary)
                        
                        HStack {
                            Text(shortenedPath(ConfigurationFileManager.shared.configurationsDirectory))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            #if os(macOS)
                            Button {
                                ConfigurationFileManager.shared.revealInFinder()
                            } label: {
                                Text("Reveal")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(colors.accent)
                            }
                            .buttonStyle(.plain)
                            #endif
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(colors.inputBackground)
                        )
                    }
                    
                    // Storage options
                    VStack(spacing: 8) {
                        storageOptionButton(
                            location: .local,
                            isSelected: currentStorageLocation == .local
                        ) {
                            ConfigurationFileManager.shared.switchToLocal(migrate: true)
                            updateStorageLocation()
                        }
                        
                        storageOptionButton(
                            location: .iCloud,
                            isSelected: currentStorageLocation == .iCloud,
                            isDisabled: !AppPreferences.isICloudAvailable
                        ) {
                            ConfigurationFileManager.shared.switchToICloud(migrate: true)
                            updateStorageLocation()
                        }
                        
                        #if os(macOS)
                        storageOptionButton(
                            location: .custom,
                            isSelected: currentStorageLocation == .custom
                        ) {
                            selectCustomFolder()
                        }
                        #endif
                    }
                    
                    // iCloud sync hint
                    if currentStorageLocation == .iCloud {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.icloud.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text("Configurations will sync across all your devices via iCloud.")
                                .font(.system(size: 11))
                                .foregroundColor(colors.textSecondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.leading, 26)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.inputBackground.opacity(0.5))
        )
        .onAppear {
            updateStorageLocation()
        }
        .onReceive(ConfigurationFileManager.shared.configDirectoryChangedPublisher) { _ in
            updateStorageLocation()
        }
    }

    func updateStorageLocation() {
        currentStorageLocation = ConfigurationFileManager.shared.currentStorageLocation
        refreshSavedConfigurations()
    }

    #if os(macOS)
    func selectCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Select Configuration Folder"
        panel.message = "Choose a folder to store your configuration files."
        panel.prompt = "Select"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // Start accessing security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    DispatchQueue.main.async {
                        self.importError = "Unable to access the selected folder."
                        self.showImportError = true
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    ConfigurationFileManager.shared.switchToCustomDirectory(url, migrate: true)
                    self.updateStorageLocation()
                }
            }
        }
    }
    #endif

    func storageOptionButton(
        location: ConfigurationFileManager.StorageLocation,
        isSelected: Bool,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: location.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? colors.accent : colors.textSecondary)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isDisabled ? colors.textSecondary.opacity(0.5) : colors.textPrimary)
                    Text(location.description)
                        .font(.system(size: 11))
                        .foregroundColor(colors.textSecondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(colors.accent)
                }
                
                if isDisabled && location == .iCloud {
                    Text("Not available")
                        .font(.system(size: 10))
                        .foregroundColor(colors.textSecondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? colors.accent.opacity(0.1) : colors.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? colors.accent.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1)
    }

    func shortenedPath(_ url: URL) -> String {
        let path = url.path
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        #endif
        return path
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
        let trimmedVoice = customTTSVoice.trimmingCharacters(in: .whitespacesAndNewlines)

        if ttsUseBuiltInCloud {
            // Built-in cloud mode: only voice matters
            let configuration = TTSConfiguration.builtInCloud(
                voice: trimmedVoice.isEmpty ? TTSConfiguration.builtInCloudDefaultVoice : trimmedVoice
            )
            preferences.setTTSConfiguration(configuration)
        } else {
            // Custom mode: use all fields
            let trimmedEndpoint = customTTSEndpoint
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let endpointURL = URL(string: trimmedEndpoint) ?? URL(string: "https://")!
            let trimmedKey = customTTSAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedModel = customTTSModel.trimmingCharacters(in: .whitespacesAndNewlines)

            let configuration = TTSConfiguration(
                endpointURL: endpointURL,
                apiKey: trimmedKey,
                model: trimmedModel,
                voice: trimmedVoice
            )
            preferences.setTTSConfiguration(configuration)
        }
    }

    func syncTTSPreferencesFromStore() {
        // Always show the actual stored custom TTS configuration values
        // This allows user to see what custom values are saved (even when using defaults)
        isUpdatingFromPreferences = true
        defer { isUpdatingFromPreferences = false }
        
        let configuration = preferences.ttsConfiguration
        ttsUseBuiltInCloud = configuration.useBuiltInCloud
        customTTSVoice = configuration.voice

        if !configuration.useBuiltInCloud {
            customTTSEndpoint = configuration.endpointURL.absoluteString
            customTTSAPIKey = configuration.apiKey
            customTTSModel = configuration.model
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
                print("[ConfigEditor] ⚠️ Saving with warnings:")
                for warning in validationResult.warnings {
                    print("[ConfigEditor]   - \(warning.message)")
                }
            }

            // Call onSave only if validation passed
            onSave(editableText)
        } catch let decodingError as DecodingError {
            // Provide more helpful error messages for JSON errors
            switch decodingError {
            case .dataCorrupted(let context):
                validationErrorMessage = "JSON format error: \(context.debugDescription)"
            case .keyNotFound(let key, let context):
                validationErrorMessage = "Missing required field '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .typeMismatch(let type, let context):
                validationErrorMessage = "Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
            case .valueNotFound(let type, let context):
                validationErrorMessage = "Missing value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
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
