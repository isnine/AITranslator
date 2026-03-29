# Voice-to-Action Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users create Actions by voice — speak a description, pick from AI-generated options, and land in ActionDetailView with all fields pre-filled.

**Architecture:** Local speech recognition via `SFSpeechRecognizer` → transcript sent to new `/voice-to-action` Worker endpoint → AI generates ≤3 ActionConfig options → user picks one → pre-fills existing ActionDetailView. Two new services (SpeechRecognitionService, VoiceActionService), two new views (VoiceRecordingView, VoiceIntentConfirmationView), modifications to ActionsView and ActionDetailView.

**Tech Stack:** SwiftUI, Speech framework, AVFoundation, Cloudflare Workers (TypeScript), Azure OpenAI (gpt-4o-mini)

**Spec:** `docs/superpowers/specs/2026-03-29-voice-to-action-design.md`

---

## File Map

### New Files

| File | Module | Responsibility |
|------|--------|---------------|
| `ShareCore/Networking/SpeechRecognitionService.swift` | ShareCore | `SFSpeechRecognizer` + `AVAudioEngine` wrapper with state machine (idle/recording/paused/processing) |
| `ShareCore/Networking/VoiceActionService.swift` | ShareCore | REST client for `/voice-to-action` endpoint; decodes `VoiceActionResponse` |
| `AITranslator/UI/VoiceRecordingView.swift` | AITranslator | Recording overlay: mic button, real-time transcript, cancel/done |
| `AITranslator/UI/VoiceIntentConfirmationView.swift` | AITranslator | Option cards (≤3), custom input, confirm button |

### Modified Files

| File | Change |
|------|--------|
| `AITranslator/Info.plist` | Add `NSSpeechRecognitionUsageDescription` + `NSMicrophoneUsageDescription` |
| `AITranslator/UI/ActionsView.swift` | Add 🎙️ button next to "+", navigation to voice flow |
| `AITranslator/UI/ActionDetailView.swift` | Accept `isAIGenerated` flag, show banner, expand collapsible sections |
| `Workers/azureProxyWorker.ts` | Add `/voice-to-action` route + handler |

---

## Task 1: Info.plist Permissions

**Files:**
- Modify: `AITranslator/Info.plist`

- [ ] **Step 1: Add permission keys**

Add before the closing `</dict>`:

```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>TLingo uses speech recognition to create translation actions from your voice.</string>
<key>NSMicrophoneUsageDescription</key>
<string>TLingo needs microphone access to record your voice for creating actions.</string>
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild -project AITranslator.xcodeproj -scheme TLingo -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add AITranslator/Info.plist
git commit -m "[Developer] Add microphone and speech recognition plist keys"
```

---

## Task 2: SpeechRecognitionService

**Files:**
- Create: `ShareCore/Networking/SpeechRecognitionService.swift`

- [ ] **Step 1: Create service with state machine**

```swift
//
//  SpeechRecognitionService.swift
//  ShareCore
//

import AVFoundation
import Foundation
import Speech

public enum SpeechRecognitionError: Error, LocalizedError {
    case notAvailable
    case permissionDenied
    case audioEngineError(String)
    case recognitionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Speech recognition is not available on this device"
        case .permissionDenied:
            return "Speech recognition or microphone permission was denied"
        case let .audioEngineError(detail):
            return "Audio engine error: \(detail)"
        case let .recognitionFailed(detail):
            return "Recognition failed: \(detail)"
        }
    }
}

public final class SpeechRecognitionService: NSObject, ObservableObject {
    public enum State: Equatable {
        case idle
        case recording
        case paused
        case processing
    }

    @Published public private(set) var transcript: String = ""
    @Published public private(set) var state: State = .idle
    @Published public private(set) var error: SpeechRecognitionError?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?
    private var backgroundTime: Date?

    public override init() {
        speechRecognizer = SFSpeechRecognizer()
        super.init()
        registerForAppLifecycle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Authorization

    @MainActor
    public func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            error = .permissionDenied
            return false
        }

        #if os(iOS)
            let micStatus = await AVAudioApplication.requestRecordPermission()
            guard micStatus else {
                error = .permissionDenied
                return false
            }
        #endif

        guard speechRecognizer?.isAvailable == true else {
            error = .notAvailable
            return false
        }

        return true
    }

    // MARK: - Recording

    @MainActor
    public func startRecording() throws {
        guard state == .idle else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechRecognitionError.notAvailable
        }

        // Reset
        transcript = ""
        error = nil

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        self.recognitionRequest = recognitionRequest

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, taskError in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }
            }
            if taskError != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    if self.state == .recording {
                        self.finishRecording()
                    }
                }
            }
        }

        #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        audioEngine.prepare()
        try audioEngine.start()
        state = .recording
    }

    @MainActor
    public func stopRecording() {
        guard state == .recording || state == .paused else { return }
        state = .processing
        finishRecording()
    }

    @MainActor
    public func cancelRecording() {
        state = .idle
        finishRecording()
        transcript = ""
    }

    @MainActor
    private func finishRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        if state == .processing, transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = .idle
        } else if state == .processing {
            // Keep .processing — caller reads transcript
        }
    }

    // MARK: - App Lifecycle

    private func registerForAppLifecycle() {
        #if os(iOS)
            NotificationCenter.default.addObserver(
                self, selector: #selector(appDidEnterBackground),
                name: UIApplication.didEnterBackgroundNotification, object: nil
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(appWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification, object: nil
            )
        #endif
    }

    @objc private func appDidEnterBackground() {
        guard state == .recording else { return }
        backgroundTime = Date()
        Task { @MainActor in
            state = .paused
            audioEngine.pause()
        }
    }

    @objc private func appWillEnterForeground() {
        guard state == .paused else { return }
        let elapsed = backgroundTime.map { Date().timeIntervalSince($0) } ?? .infinity
        Task { @MainActor in
            if elapsed > 30 {
                cancelRecording()
            } else {
                try? audioEngine.start()
                state = .recording
            }
            backgroundTime = nil
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild -project AITranslator.xcodeproj -scheme TLingo -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ShareCore/Networking/SpeechRecognitionService.swift
git commit -m "[Added] SpeechRecognitionService with state machine"
```

---

## Task 3: VoiceActionService

**Files:**
- Create: `ShareCore/Networking/VoiceActionService.swift`

- [ ] **Step 1: Create service with types and API client**

```swift
//
//  VoiceActionService.swift
//  ShareCore
//

import Foundation

public enum VoiceActionError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case emptyTranscript

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case let .httpError(statusCode, body):
            return "Server error (\(statusCode)): \(body ?? "Unknown")"
        case .emptyTranscript:
            return "Transcript is empty"
        }
    }
}

public final class VoiceActionService: Sendable {
    public static let shared = VoiceActionService()

    private let urlSession: URLSession

    public init(urlSession: URLSession = NetworkSession.shared) {
        self.urlSession = urlSession
    }

    // MARK: - Public Types

    public struct VoiceActionOption: Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let description: String
        public let actionConfig: ActionConfig

        public init(title: String, description: String, actionConfig: ActionConfig) {
            self.id = UUID()
            self.title = title
            self.description = description
            self.actionConfig = actionConfig
        }
    }

    public struct VoiceActionResult: Sendable {
        public let options: [VoiceActionOption]
        public let allowCustomInput: Bool
    }

    // MARK: - API

    public func generateOptions(transcript: String, locale: String) async throws -> VoiceActionResult {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceActionError.emptyTranscript
        }

        let url = CloudServiceConstants.endpoint.appendingPathComponent("voice-to-action")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        CloudAuthHelper.applyAuth(to: &request, path: "/voice-to-action")

        let body: [String: String] = ["transcript": transcript, "locale": locale]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceActionError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw VoiceActionError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
        return mapResponse(apiResponse, transcript: transcript)
    }

    // MARK: - Private

    private struct APIResponse: Decodable {
        let options: [APIOption]
        let allowCustomInput: Bool

        enum CodingKeys: String, CodingKey {
            case options
            case allowCustomInput = "allow_custom_input"
        }
    }

    private struct APIOption: Decodable {
        let title: String
        let description: String
        let actionConfig: PartialActionConfig

        enum CodingKeys: String, CodingKey {
            case title, description
            case actionConfig = "action_config"
        }
    }

    private struct PartialActionConfig: Decodable {
        let name: String
        let prompt: String
        let outputType: String
        let usageScenes: [String]

        enum CodingKeys: String, CodingKey {
            case name, prompt
            case outputType = "output_type"
            case usageScenes = "usage_scenes"
        }

        func toActionConfig() -> ActionConfig {
            let scenes = parseUsageScenes()
            let output = OutputType(rawValue: outputType) ?? .plain
            return ActionConfig(name: name, prompt: prompt, usageScenes: scenes, outputType: output)
        }

        private func parseUsageScenes() -> ActionConfig.UsageScene {
            var result: ActionConfig.UsageScene = []
            for scene in usageScenes {
                switch scene {
                case "app": result.insert(.app)
                case "contextRead": result.insert(.contextRead)
                case "contextEdit": result.insert(.contextEdit)
                default: break
                }
            }
            return result.isEmpty ? .app : result
        }
    }

    private func mapResponse(_ response: APIResponse, transcript: String) -> VoiceActionResult {
        var options = response.options.map { option in
            VoiceActionOption(
                title: option.title,
                description: option.description,
                actionConfig: option.actionConfig.toActionConfig()
            )
        }

        // Client-side fallback if API returned empty options
        if options.isEmpty {
            let fallback = VoiceActionOption(
                title: String(localized: "Basic Translation Action"),
                description: String(localized: "A translation action based on your description"),
                actionConfig: ActionConfig(
                    name: String(localized: "Custom Action"),
                    prompt: "Based on the user's request: \"\(transcript)\"\n\nTranslate \"{text}\" to {targetLanguage}.",
                    usageScenes: .all,
                    outputType: .plain
                )
            )
            options.append(fallback)
        }

        return VoiceActionResult(options: options, allowCustomInput: response.allowCustomInput || response.options.isEmpty)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild -project AITranslator.xcodeproj -scheme TLingo -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ShareCore/Networking/VoiceActionService.swift
git commit -m "[Added] VoiceActionService API client"
```

---

## Task 4: VoiceRecordingView (Phase 2 UI)

**Files:**
- Create: `AITranslator/UI/VoiceRecordingView.swift`

- [ ] **Step 1: Create recording overlay view**

```swift
//
//  VoiceRecordingView.swift
//  TLingo
//

import ShareCore
import SwiftUI

struct VoiceRecordingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var speechService = SpeechRecognitionService()
    let onComplete: (String) -> Void
    let onCancel: () -> Void

    /// Debounce: ignore taps within 300ms
    @State private var lastTapTime: Date = .distantPast
    @State private var showPermissionAlert = false
    @State private var showEmptyTranscriptToast = false

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            micButton

            stateLabel

            transcriptBox

            if showEmptyTranscriptToast {
                Text("No speech detected, please try again", comment: "Empty transcript toast")
                    .font(.system(size: 14))
                    .foregroundColor(colors.error)
                    .transition(.opacity)
            }

            actionButtons

            Spacer()
        }
        .padding(24)
        .background(colors.background.ignoresSafeArea())
        .onAppear {
            startRecording()
        }
        .onChange(of: speechService.state) { _, newState in
            if newState == .processing {
                let text = speechService.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    speechService.cancelRecording()
                    withAnimation {
                        showEmptyTranscriptToast = true
                    }
                    // Auto-dismiss after 2s
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation { showEmptyTranscriptToast = false }
                    }
                } else {
                    onComplete(text)
                }
            }
        }
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button("Open Settings", comment: "Open system settings for permissions") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {
                onCancel()
            }
        } message: {
            Text("Microphone and speech recognition permissions are required. Please enable them in Settings.", comment: "Permission denied alert message")
        }
    }

    private var micButton: some View {
        Button {
            guard Date().timeIntervalSince(lastTapTime) > 0.3 else { return }
            lastTapTime = Date()

            if speechService.state == .recording {
                speechService.stopRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        speechService.state == .recording
                            ? LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [colors.accent, colors.accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(speechService.state == .recording ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: speechService.state == .recording)

                Image(systemName: "mic.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private var stateLabel: some View {
        Group {
            switch speechService.state {
            case .recording:
                Text("Listening...", comment: "Voice recording state")
                    .font(.system(size: 16, weight: .semibold))
            case .paused:
                Text("Paused", comment: "Voice recording paused state")
                    .font(.system(size: 16, weight: .semibold))
            case .processing:
                ProgressView()
            case .idle:
                if let error = speechService.error {
                    Text(error.localizedDescription)
                        .font(.system(size: 14))
                        .foregroundColor(colors.error)
                } else {
                    Text("Describe the action you want to create", comment: "Voice recording hint")
                        .font(.system(size: 14))
                }
            }
        }
        .foregroundColor(colors.textSecondary)
    }

    private var transcriptBox: some View {
        Group {
            if !speechService.transcript.isEmpty {
                Text(speechService.transcript)
                    .font(.system(size: 15))
                    .foregroundColor(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colors.inputBackground)
                    )
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                speechService.cancelRecording()
                onCancel()
            } label: {
                Text("Cancel", comment: "Cancel voice recording")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colors.textSecondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(colors.cardBackground)
                    )
            }
            .buttonStyle(.plain)

            if speechService.state == .recording {
                Button {
                    guard Date().timeIntervalSince(lastTapTime) > 0.3 else { return }
                    lastTapTime = Date()
                    speechService.stopRecording()
                } label: {
                    Text("Done", comment: "Finish voice recording")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(
                                LinearGradient(colors: [colors.accent, colors.accent.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func startRecording() {
        Task {
            let authorized = await speechService.requestAuthorization()
            guard authorized else {
                showPermissionAlert = true
                return
            }
            try? speechService.startRecording()
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild -project AITranslator.xcodeproj -scheme TLingo -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add AITranslator/UI/VoiceRecordingView.swift
git commit -m "[Added] VoiceRecordingView recording overlay"
```

---

## Task 5: VoiceIntentConfirmationView (Phase 3 UI)

**Files:**
- Create: `AITranslator/UI/VoiceIntentConfirmationView.swift`

- [ ] **Step 1: Create option selection view**

```swift
//
//  VoiceIntentConfirmationView.swift
//  TLingo
//

import ShareCore
import SwiftUI

struct VoiceIntentConfirmationView: View {
    @Environment(\.colorScheme) private var colorScheme

    let transcript: String
    let onActionSelected: (ActionConfig) -> Void
    let onCancel: () -> Void

    @State private var options: [VoiceActionService.VoiceActionOption] = []
    @State private var allowCustomInput = false
    @State private var selectedOptionID: UUID?
    @State private var customText: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isRetrying = false

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection

            if isLoading {
                loadingSection
            } else if let errorMessage {
                errorSection(message: errorMessage)
            } else {
                optionsSection
                confirmButton
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(colors.background.ignoresSafeArea())
        .task {
            await fetchOptions()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("I understand you want:", comment: "AI intent confirmation header")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(colors.textPrimary)
            Text(transcript)
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)
                .lineLimit(3)
        }
    }

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Generating options...", comment: "Loading AI options")
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorSection(message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(colors.error)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    Task { await fetchOptions() }
                } label: {
                    Text("Retry", comment: "Retry fetching options")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.accent)
                }
                .buttonStyle(.plain)

                Button {
                    onCancel()
                } label: {
                    Text("Create Manually", comment: "Fall back to manual creation")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var optionsSection: some View {
        VStack(spacing: 10) {
            Text("Choose the best match:", comment: "Option selection prompt")
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)

            ForEach(options) { option in
                optionCard(option)
            }

            if allowCustomInput {
                customInputCard
            }
        }
    }

    private func optionCard(_ option: VoiceActionService.VoiceActionOption) -> some View {
        let isSelected = selectedOptionID == option.id
        return Button {
            selectedOptionID = option.id
            customText = ""
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text(option.description)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? colors.accent : colors.textSecondary.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? colors.accent : .clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var isCustomSelected: Bool {
        selectedOptionID == nil && !customText.isEmpty
    }

    private var customInputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                selectedOptionID = nil
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Description", comment: "Custom input option title")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                        Text("Describe what you want in your own words", comment: "Custom input option hint")
                            .font(.system(size: 13))
                            .foregroundColor(colors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: isCustomSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isCustomSelected ? colors.accent : colors.textSecondary.opacity(0.5))
                }
            }
            .buttonStyle(.plain)

            if selectedOptionID == nil {
                TextField(
                    String(localized: "Enter your description...", comment: "Custom input placeholder"),
                    text: $customText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(colors.textPrimary)
                .lineLimit(3 ... 6)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(colors.inputBackground)
                )
                .onChange(of: customText) {
                    if customText.count > 500 {
                        customText = String(customText.prefix(500))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isCustomSelected ? colors.accent : .clear, lineWidth: 2)
                )
        )
    }

    private var confirmButton: some View {
        let canConfirm = selectedOptionID != nil || !customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return Button {
            if isCustomSelected {
                // Re-send with custom text
                Task { await submitCustomInput() }
            } else if let selectedID = selectedOptionID,
                      let option = options.first(where: { $0.id == selectedID })
            {
                onActionSelected(option.actionConfig)
            }
        } label: {
            Group {
                if isRetrying {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Confirm and Generate", comment: "Confirm option selection")
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(
                    canConfirm
                        ? LinearGradient(colors: [colors.accent, colors.accent.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canConfirm || isRetrying)
    }

    // MARK: - API

    private func fetchOptions() async {
        isLoading = true
        errorMessage = nil

        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        do {
            let result = try await VoiceActionService.shared.generateOptions(transcript: transcript, locale: locale)
            options = result.options
            allowCustomInput = result.allowCustomInput
            if let first = options.first {
                selectedOptionID = first.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func submitCustomInput() async {
        isRetrying = true
        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        do {
            let result = try await VoiceActionService.shared.generateOptions(transcript: customText, locale: locale)
            if let firstOption = result.options.first {
                onActionSelected(firstOption.actionConfig)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isRetrying = false
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild -project AITranslator.xcodeproj -scheme TLingo -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add AITranslator/UI/VoiceIntentConfirmationView.swift
git commit -m "[Added] VoiceIntentConfirmationView option selection UI"
```

---

## Task 6: Modify ActionDetailView (AI banner + isAIGenerated flag)

**Files:**
- Modify: `AITranslator/UI/ActionDetailView.swift`

- [ ] **Step 1: Add `isAIGenerated` parameter to init**

In `ActionDetailView.swift`, add a new stored property and update init:

```swift
// Add after line 32 (showDeleteConfirmation):
private let isAIGenerated: Bool
```

Update the `init` signature (line 34):

```swift
init(
    action: ActionConfig?,
    configurationStore: AppConfigurationStore,
    isAIGenerated: Bool = false
)
```

Add inside init body after line 38:

```swift
self.isAIGenerated = isAIGenerated
```

- [ ] **Step 2: Auto-expand collapsible sections when AI-generated**

Change initial state values for collapsible sections (lines 28-29):

In body's `.onAppear` or change the `@State` initialization:

Actually, since `@State` init must be compile-time constant or set via `State(initialValue:)`, change the init to set these:

Replace lines 28-29:
```swift
@State private var isUsageScenesExpanded: Bool
@State private var isOutputTypeExpanded: Bool
```

In the init, after `self.isAIGenerated = isAIGenerated`, add:
```swift
_isUsageScenesExpanded = State(initialValue: isAIGenerated)
_isOutputTypeExpanded = State(initialValue: isAIGenerated)
```

Remove the `= false` default for these two `@State` vars since they're now set in init.

- [ ] **Step 3: Add AI-generated banner**

Add after `optionsSection` and before the delete section check (around line 66):

```swift
if isAIGenerated {
    aiGeneratedBanner
}
```

Add the computed property:

```swift
private var aiGeneratedBanner: some View {
    HStack(spacing: 8) {
        Image(systemName: "sparkles")
            .font(.system(size: 14))
        Text("Generated by AI — please review before saving", comment: "AI-generated action banner")
            .font(.system(size: 13))
    }
    .foregroundColor(colors.accent)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(colors.accent.opacity(0.08))
    )
}
```

- [ ] **Step 4: Update Preview and callers**

The default `isAIGenerated: Bool = false` means existing callers in ActionsView (lines 41, 48) don't need changes.

- [ ] **Step 5: Verify build**

Run: `xcodebuild -project AITranslator.xcodeproj -scheme TLingo -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add AITranslator/UI/ActionDetailView.swift
git commit -m "[Added] AI-generated banner and auto-expand in ActionDetailView"
```

---

## Task 7: Modify ActionsView (Voice button + navigation)

**Files:**
- Modify: `AITranslator/UI/ActionsView.swift`

- [ ] **Step 1: Add state variables for voice flow**

Add after line 19 (`isAddingNewAction`):

```swift
@State private var isVoiceRecording = false
@State private var voiceTranscript: String?
@State private var aiGeneratedAction: ActionConfig?
```

- [ ] **Step 2: Add 🎙️ button next to "+"**

Replace the "+" button (lines 92-99) with:

```swift
Button {
    isVoiceRecording = true
} label: {
    Image(systemName: "mic.fill")
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .frame(width: 28, height: 28)
        .background(
            Circle().fill(
                LinearGradient(colors: [colors.accent, colors.accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        )
}
.buttonStyle(.plain)

Button {
    isAddingNewAction = true
} label: {
    Image(systemName: "plus")
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(colors.accent)
}
.buttonStyle(.plain)
```

- [ ] **Step 3: Add sheet presentations**

Add after `.tint(colors.accent)` (line 53), before the `#if os(iOS)`:

```swift
.sheet(isPresented: $isVoiceRecording) {
    if let transcript = voiceTranscript {
        VoiceIntentConfirmationView(
            transcript: transcript,
            onActionSelected: { config in
                aiGeneratedAction = config
                voiceTranscript = nil
                isVoiceRecording = false
            },
            onCancel: {
                voiceTranscript = nil
                isVoiceRecording = false
            }
        )
        .presentationDetents([.large])
    } else {
        VoiceRecordingView(
            onComplete: { text in
                voiceTranscript = text
            },
            onCancel: {
                isVoiceRecording = false
            }
        )
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 4: Add navigation for AI-generated action**

Add a `navigationDestination` for the AI-generated action. After the existing `.navigationDestination(isPresented: $isAddingNewAction)` block (lines 46-51):

```swift
.navigationDestination(item: $aiGeneratedAction) { config in
    ActionDetailView(
        action: config,
        configurationStore: configurationStore,
        isAIGenerated: true
    )
}
```

Note: Since `ActionConfig` is already `Hashable`, this should work. The navigation destination receives the config as a pre-filled **new** action. However, since `ActionDetailView` treats a non-nil `action` as editing (not new), we need to pass `nil` and instead pre-fill fields differently.

Actually, looking at ActionDetailView init (line 40-54): when `action` is non-nil, it uses the existing `action.id` and sets `isNewAction = false`. When `nil`, it creates a new UUID with `isNewAction = true`. For AI-generated, we want a **new** action with pre-filled content. So we should pass `action: config` — the config already has a fresh UUID from `VoiceActionService`. The `isNewAction = false` path will try to find-and-update, but since the ID doesn't exist in the store, `saveAction()` at line 439 will hit the else branch and append it. This works correctly.

- [ ] **Step 5: Verify build**

Run: `xcodebuild -project AITranslator.xcodeproj -scheme TLingo -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add AITranslator/UI/ActionsView.swift
git commit -m "[Added] Voice-to-action button and flow in ActionsView"
```

---

## Task 8: Cloudflare Worker `/voice-to-action` Endpoint

**Files:**
- Modify: `Workers/azureProxyWorker.ts`

- [ ] **Step 1: Add route in the fetch handler**

After line 118 (`return handleTTSRequest(request, env);`), add:

```typescript
    // Route: /voice-to-action - Generate ActionConfig from voice transcript
    if (path === "/voice-to-action") {
      return handleVoiceToActionRequest(request, env);
    }
```

- [ ] **Step 2: Add handler function**

Add before the `isAuthorized` function (around line 284):

```typescript
// MARK: - Voice-to-Action Handler

async function handleVoiceToActionRequest(request: Request, env: Env): Promise<Response> {
  const clientIP = request.headers.get("CF-Connecting-IP") || "unknown";
  console.log(`Voice-to-Action Request - IP: ${clientIP}`);

  try {
    if (request.method !== "POST") {
      return buildResponse(
        JSON.stringify({ error: "Method not allowed" }),
        405,
        "application/json"
      );
    }

    const body = (await request.json()) as { transcript?: string; locale?: string };
    if (!body.transcript || body.transcript.trim().length === 0) {
      return buildResponse(
        JSON.stringify({ error: "transcript is required" }),
        400,
        "application/json"
      );
    }

    const transcript = body.transcript.trim();
    const locale = body.locale || "en";

    // Build Azure OpenAI request
    const azureURL = new URL(env.AZURE_ENDPOINT);
    const basePath = azureURL.pathname.replace(/\/+$/, "");
    azureURL.pathname = `${basePath}/gpt-4o-mini/chat/completions`;
    const searchParams = new URLSearchParams(azureURL.search);
    if (!searchParams.has("api-version")) {
      searchParams.set("api-version", "2025-01-01-preview");
    }
    azureURL.search = searchParams.toString();

    const systemPrompt = `You are an assistant that generates translation action configurations for a translation app called TLingo.

The user will describe a translation action they want in natural language. Generate 2-3 options as structured JSON.

Each option must have:
- title: Short name for the action (in the user's language: ${locale})
- description: One-line description (in the user's language)
- action_config: Object with:
  - name: Display name for the action
  - prompt: The prompt template. MUST include {text} placeholder. May include {targetLanguage} if relevant.
  - output_type: One of "plain", "diff", "sentencePairs", "grammarCheck"
  - usage_scenes: Array from ["app", "contextRead", "contextEdit"]. Default to all three.

Generate options that vary in specificity or approach. For example, one literal and one more creative interpretation.

Return ONLY valid JSON matching this schema:
{
  "options": [{ "title": "...", "description": "...", "action_config": { "name": "...", "prompt": "...", "output_type": "...", "usage_scenes": [...] } }],
  "allow_custom_input": true
}`;

    const llmPayload = {
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: transcript },
      ],
      temperature: 0.7,
      max_tokens: 1000,
      response_format: { type: "json_object" },
    };

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000);

    const llmResponse = await fetch(azureURL.toString(), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "api-key": env.AZURE_API_KEY,
      },
      body: JSON.stringify(llmPayload),
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!llmResponse.ok) {
      const errorBody = await llmResponse.text();
      console.error(`Azure OpenAI error: ${llmResponse.status} - ${errorBody}`);
      return buildResponse(
        JSON.stringify({ error: "Failed to generate options", detail: `Azure OpenAI returned ${llmResponse.status}` }),
        500,
        "application/json"
      );
    }

    const llmResult = (await llmResponse.json()) as { choices?: { message?: { content?: string } }[] };
    const content = llmResult.choices?.[0]?.message?.content;

    if (!content) {
      return buildResponse(
        JSON.stringify({ error: "Failed to generate options", detail: "Empty response from model" }),
        500,
        "application/json"
      );
    }

    // Parse and validate the JSON response
    let parsed;
    try {
      parsed = JSON.parse(content);
    } catch {
      return buildResponse(
        JSON.stringify({ error: "Failed to parse model response", detail: "Invalid JSON" }),
        500,
        "application/json"
      );
    }

    // Ensure options array exists
    if (!Array.isArray(parsed.options)) {
      parsed = { options: [], allow_custom_input: true };
    }

    const responseHeaders = new Headers();
    applyCors(responseHeaders);
    responseHeaders.set("Content-Type", "application/json");

    return new Response(JSON.stringify(parsed), {
      status: 200,
      headers: responseHeaders,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      return buildResponse(
        JSON.stringify({ error: "Request timed out" }),
        504,
        "application/json"
      );
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    return buildResponse(
      JSON.stringify({ error: "Voice-to-action request failed", message }),
      502,
      "application/json"
    );
  }
}
```

- [ ] **Step 3: Verify Worker builds**

Run: `cd Workers && npx wrangler deploy --dry-run 2>&1 | tail -5` (or `npx tsc --noEmit` if available)

- [ ] **Step 4: Commit**

```bash
git add Workers/azureProxyWorker.ts
git commit -m "[Added] /voice-to-action Worker endpoint"
```

---

## Task 9: Lint, Format, and Final Build Verification

**Files:** All modified files

- [ ] **Step 1: Format Swift code**

Run: `make format`

- [ ] **Step 2: Lint Swift code**

Run: `make lint`
Fix any issues reported.

- [ ] **Step 3: Full iOS build**

Run: `xcodebuild -project AITranslator.xcodeproj -scheme TLingo -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit any format/lint fixes**

```bash
git add -u
git commit -m "[Developer] Format and lint fixes"
```

---

## Task 10: Manual Testing Checklist

- [ ] Launch app on iOS Simulator
- [ ] Navigate to Actions tab
- [ ] Verify 🎙️ button appears next to "+"
- [ ] Tap 🎙️ — verify permission dialog appears (first time)
- [ ] Grant permissions — verify recording overlay opens
- [ ] Speak a description — verify real-time transcript displays
- [ ] Tap "Done" — verify intent confirmation options appear
- [ ] Select an option → "Confirm" — verify ActionDetailView opens with pre-filled fields
- [ ] Verify AI-generated banner displays
- [ ] Verify collapsible sections are expanded
- [ ] Save — verify action appears in list
- [ ] Test cancel flow (recording → cancel → back to list)
- [ ] Test empty transcript (say nothing → "Done" → verify returns to idle)
- [ ] Test app backgrounding during recording (background > 30s → auto-cancel)
