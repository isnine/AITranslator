# Work Plan: Enable Action Configuration Editing

## Goal
Transform AITranslator from a read-only configuration model to a single editable configuration. Remove all ConfigurationMode infrastructure and make action editing work out of the box.

## Success Criteria
- [ ] App launches and loads configuration from App Group (or copies bundled default on first launch)
- [ ] Edit action -> Save button saves changes to file
- [ ] Reorder actions -> Changes persist to file
- [ ] Add new action -> Persists to file
- [ ] Delete action -> Persists to file
- [ ] External file edits trigger UI reload
- [ ] Import configuration works
- [ ] Export configuration works
- [ ] Build succeeds with zero compilation errors

---

## Phase 1: AppConfigurationStore.swift (Core Changes)

### Task 1.1: Remove ConfigurationMode enum and related types
**File:** `ShareCore/Configuration/AppConfigurationStore.swift`
**Lines:** 14-51

**Remove:**
- `ConfigurationMode` enum (lines 14-36)
- `CreateCustomConfigurationRequest` struct (lines 39-51)

**Why:** These are the foundation of the disabled multi-config system. Removing them cascades to all mode checks.

---

### Task 1.2: Remove mode-related publishers and properties
**File:** `ShareCore/Configuration/AppConfigurationStore.swift`

**Remove:**
- `createCustomConfigurationRequestPublisher` property
- `resetPendingChangesPublisher` property  
- `configurationMode` published property

**Keep:**
- `configurationSwitchedPublisher` (review if still needed after cleanup)

---

### Task 1.3: Enable updateActions() method
**File:** `ShareCore/Configuration/AppConfigurationStore.swift`
**Current Location:** Around line 180-190

**Before:**
```swift
public func updateActions(_ actions: [ActionConfig]) -> ConfigurationValidationResult? {
    print("[ConfigStore] Configuration changes are disabled")
    return nil
}
```

**After:**
```swift
public func updateActions(_ actions: [ActionConfig]) -> ConfigurationValidationResult? {
    return applyActionsUpdate(actions)
}
```

**Why:** `applyActionsUpdate()` already implements correct validation and saving.

---

### Task 1.4: Remove dead update methods
**File:** `ShareCore/Configuration/AppConfigurationStore.swift`

**Remove entirely:**
- `updateTTSConfiguration(_ ttsConfig: TTSConfiguration)` - dead code, TTS handled via AppPreferences
- `updateTargetLanguage(_ option: TargetLanguageOption)` - dead code, handled via AppPreferences

---

### Task 1.5: Remove disabled configuration management methods
**File:** `ShareCore/Configuration/AppConfigurationStore.swift`

**Remove entirely:**
- `createCustomConfigurationFromDefault(named:)` - disabled method
- `switchConfiguration(to:)` - disabled method

---

### Task 1.6: Update loadConfiguration() for first-launch copy
**File:** `ShareCore/Configuration/AppConfigurationStore.swift`
**Current Location:** Around line 300-400

**Modify to:**
1. Check if `Configuration.json` exists in App Group via `configFileManager.configurationExists(named: "Configuration")`
2. If not exists: copy bundled `DefaultConfiguration.json` to App Group as `Configuration.json`
3. Load configuration
4. Start file monitoring

**Implementation pattern:**
```swift
public func loadConfiguration() {
    let configName = "Configuration"
    
    // First launch: copy bundled default if no config exists
    if !configFileManager.configurationExists(named: configName) {
        copyBundledDefaultConfiguration()
    }
    
    // Load from App Group
    if let config = configFileManager.loadConfiguration(named: configName) {
        self.configuration = config
        self.actions = config.actions
        self.currentConfigurationName = configName
        setupFileChangeObserver()
    } else {
        print("[ConfigStore] Failed to load configuration")
    }
}

private func copyBundledDefaultConfiguration() {
    // Implementation in Task 7.1
}
```

---

### Task 1.7: Update saveConfiguration() - remove mode guard
**File:** `ShareCore/Configuration/AppConfigurationStore.swift`
**Current Location:** Around line 571-574

**Remove this guard:**
```swift
guard !configurationMode.isDefault else {
    print("[ConfigStore] Cannot save default configuration")
    return
}
```

**Why:** With single editable config, there's no "default" vs "custom" distinction.

---

### Task 1.8: Simplify setConfigurationModeAndName()
**File:** `ShareCore/Configuration/AppConfigurationStore.swift`

**Rename and simplify to:**
```swift
private func setCurrentConfigurationName(_ name: String) {
    self.currentConfigurationName = name
}
```

**Why:** No more mode concept, just track the name.

---

### Task 1.9: Simplify or remove mode-related helpers
**File:** `ShareCore/Configuration/AppConfigurationStore.swift`

**Review and update:**
- `switchToDefaultConfiguration()` - simplify or remove
- `resetToDefault()` - simplify to reload bundled config

---

## Phase 2: ConfigurationService.swift

### Task 2.1: Update applyConfiguration()
**File:** `ShareCore/Configuration/ConfigurationService.swift`
**Current Location:** Check for `setConfigurationModeAndName` calls

**Before:** Sets mode to `.customConfiguration(name:)`
**After:** Just sets the configuration name via simplified method

---

## Phase 3: ActionDetailView.swift

### Task 3.1: Remove read-only alert infrastructure
**File:** `AITranslator/UI/ActionDetailView.swift`

**Remove:**
- `@State private var showReadOnlyAlert = false` (line 31)
- Alert definition (lines 89-93):
```swift
.alert("Read-Only Configuration", isPresented: $showReadOnlyAlert) {
    Button("OK", role: .cancel) {}
} message: {
    Text("Configuration changes are disabled...")
}
```

---

### Task 3.2: Enable Save button action
**File:** `AITranslator/UI/ActionDetailView.swift`
**Lines:** 117-118

**Before:**
```swift
Button {
    showReadOnlyAlert = true
}
```

**After:**
```swift
Button {
    saveAction()
}
```

---

## Phase 4: ActionsView.swift

### Task 4.1: Verify no changes needed
**File:** `AITranslator/UI/ActionsView.swift`

**Verify:** `onMove` handler already calls `configStore.updateActions()` which will now work.

**Action:** Read and confirm. No code changes expected.

---

## Phase 5: RootTabView.swift

### Task 5.1: Remove create custom config infrastructure
**File:** `AITranslator/UI/RootTabView.swift`

**Remove state variables:**
- `showCreateCustomConfigDialog`
- `pendingConfigRequest`
- `customConfigName`
- `cancellables` (if only used for removed publishers)

**Remove handlers:**
- `.onReceive(configStore.createCustomConfigurationRequestPublisher)` 
- Alert for "Create Custom Configuration"

**Remove functions:**
- `handleCreateCustomConfigRequest()`
- `createCustomConfiguration()`

---

## Phase 6: SettingsView.swift

### Task 6.1: Remove saved configurations state
**File:** `AITranslator/UI/SettingsView.swift`

**Remove state variables:**
- `savedConfigurations` (line 35)
- `showDeleteConfirmation`
- `configToDelete`
- `showSaveDialog`
- `newConfigName`

---

### Task 6.2: Remove publisher handlers
**File:** `AITranslator/UI/SettingsView.swift`

**Remove:**
- `.onReceive(configStore.resetPendingChangesPublisher)` (lines 130-133)
- `.onReceive(configStore.$configurationMode)` (lines 140-143)

---

### Task 6.3: Simplify configurationStatusRow
**File:** `AITranslator/UI/SettingsView.swift`
**Lines:** 469-510

**Remove:**
- "Read-Only" badge display
- `configurationMode.isDefault` checks
- Mode-based logic

**Keep:** 
- Current configuration name display
- Storage location info

---

### Task 6.4: Remove savedConfigurationsRow entirely
**File:** `AITranslator/UI/SettingsView.swift`
**Lines:** 512-590

**Remove:** Entire `savedConfigurationsRow` view and all its subviews.

---

### Task 6.5: Remove configuration management functions
**File:** `AITranslator/UI/SettingsView.swift`

**Remove functions:**
- `refreshSavedConfigurations()`
- `duplicateCurrentConfiguration()`
- `loadConfiguration(_:)`
- `deleteConfiguration(_:)`
- `createFromDefaultTemplate()`

**Keep:**
- Import/export functions (use ConfigurationService)
- Storage location toggle

---

## Phase 7: ConfigurationFileManager.swift

### Task 7.1: Add bundled config copy method
**File:** `ShareCore/Configuration/ConfigurationFileManager.swift`

**Add new method:**
```swift
public func copyBundledDefaultIfNeeded(to name: String) -> Bool {
    // Check if target already exists
    guard !configurationExists(named: name) else {
        return true // Already exists
    }
    
    // Find bundled DefaultConfiguration.json in ShareCore bundle
    guard let bundledURL = Bundle(for: Self.self).url(
        forResource: "DefaultConfiguration",
        withExtension: "json"
    ) else {
        print("[ConfigFileManager] Bundled default config not found")
        return false
    }
    
    // Copy to configurations directory
    let targetURL = configurationsDirectory.appendingPathComponent("\(name).json")
    
    do {
        try FileManager.default.createDirectory(
            at: configurationsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: bundledURL, to: targetURL)
        return true
    } catch {
        print("[ConfigFileManager] Failed to copy bundled config: \(error)")
        return false
    }
}
```

---

## Phase 8: Build & Verification

### Task 8.1: Build and fix compilation errors
```bash
xcodebuild -project AITranslator.xcodeproj -scheme AITranslator \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

**Fix:** Any compilation errors from removed types/methods.

---

### Task 8.2: Test core functionality
Manual verification:

1. **First launch simulation:**
   - Delete app/App Group data
   - Launch app
   - Verify config loads from copied bundled default

2. **Edit action:**
   - Open any action
   - Change a field
   - Tap Save
   - Verify file updated in App Group

3. **Reorder actions:**
   - Drag to reorder in list
   - Verify order persists after app restart

4. **Add new action:**
   - Add action via UI
   - Verify persists after restart

5. **Delete action:**
   - Delete action via UI
   - Verify removal persists

6. **External file edit:**
   - Edit JSON file externally
   - Verify app UI updates

7. **Import/Export:**
   - Export configuration
   - Modify exported file
   - Import modified file
   - Verify changes applied

---

## Risk Mitigation

### Risks Identified:
1. **ConfigurationMode removal cascade** - Many files reference this. Compilation errors expected but manageable.
2. **Publisher removal** - UI may have `.onReceive` calls that break.
3. **Bundle path for DefaultConfiguration.json** - Must verify it exists in ShareCore bundle.

### Mitigation:
- Compile after each phase to catch errors early
- Use Find References before removing any type
- Test first-launch copy path explicitly

---

## Dependencies Between Tasks

```
Phase 1 (Core) 
    ├── Task 1.1 (Remove ConfigurationMode) 
    │   └── Blocks: 1.2, 1.6, 1.7, 1.8, 1.9, Phase 2, 3, 5, 6
    ├── Task 1.3 (Enable updateActions) 
    │   └── Blocks: Phase 4 verification
    └── Task 1.6 (loadConfiguration) 
        └── Depends on: Phase 7 (copyBundledDefaultIfNeeded)

Phase 7 should be done early (before 1.6)
Phases 3, 5, 6 can be done in parallel after Phase 1
Phase 8 is last
```

## Recommended Execution Order

1. Phase 7 (add copy method first)
2. Phase 1 (core changes - will cause compilation errors)
3. Phase 2 (fix ConfigurationService)
4. Phase 3 (fix ActionDetailView)
5. Phase 5 (fix RootTabView)
6. Phase 6 (fix SettingsView)
7. Phase 4 (verify ActionsView - likely no changes)
8. Phase 8 (build, fix remaining errors, test)
