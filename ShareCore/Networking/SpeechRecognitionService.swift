//
//  SpeechRecognitionService.swift
//  ShareCore
//

import AVFoundation
import Combine
import Foundation
import Speech
#if canImport(UIKit)
    import UIKit
#endif

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

    override public init() {
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
