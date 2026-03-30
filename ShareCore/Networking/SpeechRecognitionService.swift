//
//  SpeechRecognitionService.swift
//  ShareCore
//

import AVFoundation
import Combine
import Foundation
#if canImport(UIKit)
    import UIKit
#endif

public enum SpeechRecognitionError: Error, LocalizedError {
    case permissionDenied
    case audioEngineError(String)
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission was denied"
        case let .audioEngineError(detail):
            return "Audio engine error: \(detail)"
        case let .transcriptionFailed(detail):
            return "Transcription failed: \(detail)"
        }
    }
}

public final class SpeechRecognitionService: NSObject, ObservableObject {
    public enum State: Equatable {
        case idle
        case preparing
        case recording
        case paused
        case processing
    }

    @Published public private(set) var transcript: String = ""
    @Published public private(set) var state: State = .idle
    @Published public private(set) var error: SpeechRecognitionError?
    @Published public private(set) var recordingDuration: TimeInterval = 0

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    private var backgroundTime: Date?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?

    override public init() {
        super.init()
        registerForAppLifecycle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Authorization

    @MainActor
    public func requestAuthorization() async -> Bool {
        #if os(iOS)
            let micStatus = await AVAudioApplication.requestRecordPermission()
            guard micStatus else {
                error = .permissionDenied
                return false
            }
        #endif
        return true
    }

    // MARK: - Recording

    @MainActor
    public func startRecording() async {
        guard state == .idle else { return }

        state = .preparing
        transcript = ""
        error = nil
        recordingDuration = 0

        do {
            // Yield so SwiftUI can render the preparing state
            await Task.yield()

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("m4a")
            audioFileURL = tempURL

            #if os(iOS)
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            let outputSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: recordingFormat.sampleRate,
                AVNumberOfChannelsKey: Int(recordingFormat.channelCount),
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]

            audioFile = try AVAudioFile(forWriting: tempURL, settings: outputSettings)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                try? self?.audioFile?.write(from: buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            state = .recording
            recordingStartTime = Date()
            startDurationTimer()
        } catch {
            self.error = .audioEngineError(error.localizedDescription)
            state = .idle
            cleanupAudioFile()
        }
    }

    @MainActor
    public func stopRecording() {
        guard state == .recording || state == .paused else { return }
        state = .processing
        stopDurationTimer()
        finishRecording()

        guard let audioFileURL else {
            state = .idle
            return
        }

        Task {
            do {
                let text = try await WhisperService.shared.transcribe(audioFileURL: audioFileURL)
                await MainActor.run {
                    self.transcript = text
                }
            } catch {
                await MainActor.run {
                    self.error = .transcriptionFailed(error.localizedDescription)
                    self.state = .idle
                }
                return
            }
            cleanupAudioFile()
        }
    }

    @MainActor
    public func cancelRecording() {
        stopDurationTimer()
        if state == .recording || state == .paused {
            finishRecording()
        }
        state = .idle
        transcript = ""
        cleanupAudioFile()
    }

    // MARK: - Private

    @MainActor
    private func finishRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFile = nil

        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func cleanupAudioFile() {
        guard let url = audioFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        audioFileURL = nil
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingStartTime = nil
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
