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
