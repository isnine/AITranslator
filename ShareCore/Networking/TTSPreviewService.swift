//
//  TTSPreviewService.swift
//  ShareCore
//
//  Created by AI Assistant on 2025/02/02.
//

import AVFoundation
import Combine
import CryptoKit
import Foundation

/// Service for playing TTS voice previews from the Worker API
public final class TTSPreviewService: ObservableObject {
    public static let shared = TTSPreviewService()

    /// Fixed preview text for voice samples
    public static let previewText = "Hello, this is a sample voice preview."

    /// TTS model to use for preview
    private static let ttsModel = "gpt-4o-mini-tts"

    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentVoiceID: String?

    private let urlSession: URLSession
    private var audioPlayer: AVAudioPlayer?

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Plays a TTS preview for the specified voice
    /// - Parameter voiceID: The voice ID to preview (e.g., "alloy")
    @MainActor
    public func playPreview(voiceID: String) async {
        // Stop any current playback
        stopPlayback()

        isPlaying = true
        currentVoiceID = voiceID

        do {
            let audioData = try await fetchTTSAudio(voiceID: voiceID)
            try await playAudio(data: audioData)
        } catch {
            Logger.debug("[TTSPreviewService] Preview failed for voice '\(voiceID)': \(error)")
        }

        isPlaying = false
        currentVoiceID = nil
    }

    /// Stops any current audio playback
    @MainActor
    public func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentVoiceID = nil
    }

    // MARK: - Private Methods

    private func fetchTTSAudio(voiceID: String) async throws -> Data {
        let url = CloudServiceConstants.endpoint.appendingPathComponent("tts")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        // Apply HMAC authentication
        let path = "/tts"
        applyCloudAuth(to: &request, path: path)

        // Build request body
        let body: [String: Any] = [
            "model": Self.ttsModel,
            "input": Self.previewText,
            "voice": voiceID,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Logger.debug("[TTSPreviewService] Requesting TTS preview for voice: \(voiceID)")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSPreviewError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw TTSPreviewError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        Logger.debug("[TTSPreviewService] Received \(data.count) bytes of audio data")
        return data
    }

    @MainActor
    private func playAudio(data: Data) async throws {
        #if os(iOS)
            // Configure audio session for iOS
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        #endif

        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()

        // Wait for playback to complete
        while audioPlayer?.isPlaying == true {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }

    // MARK: - HMAC Authentication

    private func generateSignature(timestamp: String, path: String) -> String {
        let message = "\(timestamp):\(path)"
        let key = SymmetricKey(data: Data(hexString: CloudServiceConstants.secret) ?? Data())
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(signature).hexEncodedString()
    }

    private func applyCloudAuth(to request: inout URLRequest, path: String) {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = generateSignature(timestamp: timestamp, path: path)
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue(signature, forHTTPHeaderField: "X-Signature")
    }
}

// MARK: - Error Types

public enum TTSPreviewError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case playbackFailed

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from TTS service"
        case let .httpError(statusCode, body):
            if let body {
                return "HTTP \(statusCode): \(body)"
            }
            return "HTTP error \(statusCode)"
        case .playbackFailed:
            return "Failed to play audio"
        }
    }
}
