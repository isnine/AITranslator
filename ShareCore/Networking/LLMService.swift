//
//  LLMService.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//
import CryptoKit
import Foundation

/// Represents a streaming update that can be either plain text or sentence pairs.
public enum StreamingUpdate: Sendable {
    case text(String)
    case sentencePairs([SentencePair])
}

public final class LLMService {
    public static let shared = LLMService()

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - HMAC Signing for Built-in Cloud Provider

    private func generateSignature(timestamp: String, path: String) -> String {
        let message = "\(timestamp):\(path)"
        let key = SymmetricKey(data: Data(hexString: CloudServiceConstants.secret) ?? Data())
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(signature).hexEncodedString()
    }

    /// Applies cloud service authentication headers to a request
    private func applyCloudAuth(to request: inout URLRequest, path: String) {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = generateSignature(timestamp: timestamp, path: path)
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue(signature, forHTTPHeaderField: "X-Signature")

        // Include premium header when user has active subscription
        if AppPreferences.sharedDefaults.bool(forKey: "is_premium_subscriber") {
            request.setValue("true", forHTTPHeaderField: "X-Premium")
        }
    }

    public func perform(
        text: String,
        with action: ActionConfig,
        models: [ModelConfig],
        images: [ImageAttachment] = [],
        partialHandler: (@MainActor @Sendable (String, StreamingUpdate) -> Void)? = nil,
        completionHandler: (@MainActor @Sendable (ModelExecutionResult) -> Void)? = nil
    ) async -> [ModelExecutionResult] {
        let hasImages = !images.isEmpty
        return await withTaskGroup(of: ModelExecutionResult?.self) { group in
            for model in models {
                group.addTask { [weak self] in
                    guard let self else { return nil }

                    // Skip models that don't support vision when images are attached
                    if hasImages && !model.supportsVision {
                        return ModelExecutionResult(
                            modelID: model.id,
                            duration: 0,
                            response: .failure(LLMServiceError.visionNotSupported(modelName: model.displayName))
                        )
                    }

                    do {
                        return try await self.sendModelRequest(
                            text: text,
                            action: action,
                            model: model,
                            images: images,
                            partialHandler: partialHandler
                        )
                    } catch is CancellationError {
                        return nil
                    } catch {
                        return nil
                    }
                }
            }

            var results: [ModelExecutionResult] = []
            for await item in group {
                guard let item else { continue }
                if let completionHandler {
                    await MainActor.run {
                        completionHandler(item)
                    }
                }
                results.append(item)
            }
            return results
        }
    }

    private func sendModelRequest(
        text: String,
        action: ActionConfig,
        model: ModelConfig,
        images: [ImageAttachment] = [],
        partialHandler: (@MainActor @Sendable (String, StreamingUpdate) -> Void)?
    ) async throws -> ModelExecutionResult {
        let start = Date()

        let requestURL = CloudServiceConstants.endpoint
            .appendingPathComponent(model.id)
            .appendingPathComponent("chat/completions")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let path = "/\(model.id)/chat/completions"
        applyCloudAuth(to: &request, path: path)

        let structuredOutputConfig = action.structuredOutput
        let enableStreaming = partialHandler != nil
        if enableStreaming {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        let messages: [LLMRequestPayload.Message]
        let imageDataURLs = images.map { $0.base64DataURL }

        if action.prompt.isEmpty {
            messages = [
                .init(role: "user", text: text, imageDataURLs: imageDataURLs),
            ]
        } else {
            let processedPrompt = PromptSubstitution.substitute(
                prompt: action.prompt,
                text: text,
                targetLanguage: AppPreferences.shared.targetLanguage.promptDescriptor,
                sourceLanguage: AppPreferences.shared.sourceLanguage.promptDescriptor ?? ""
            )
            let promptContainsTextPlaceholder = PromptSubstitution.containsTextPlaceholder(action.prompt)

            if promptContainsTextPlaceholder {
                messages = [
                    .init(role: "user", text: processedPrompt, imageDataURLs: imageDataURLs),
                ]
            } else {
                messages = [
                    .init(role: "system", content: processedPrompt),
                    .init(role: "user", text: text, imageDataURLs: imageDataURLs),
                ]
            }
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = []
            let decoder = JSONDecoder.llmDecoder
            let payloadData: Data

            if let structuredOutputConfig,
               let responseFormat = structuredOutputConfig.responseFormatPayload()
            {
                // For structured output, we must use JSONSerialization to include response_format.
                // Build message dicts manually, supporting multimodal content.
                let messageDicts: [[String: Any]] = messages.map { msg in
                    // Encode the message to JSON data first, then deserialize to dict
                    // This leverages the custom Encodable to handle both text and parts
                    if let data = try? JSONEncoder().encode(msg),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    {
                        return dict
                    }
                    // Fallback: text-only
                    return ["role": msg.role, "content": msg.textContent]
                }

                var body: [String: Any] = [
                    "messages": messageDicts,
                    "stream": enableStreaming,
                ]
                body["response_format"] = responseFormat
                payloadData = try JSONSerialization.data(withJSONObject: body, options: [])
            } else {
                let payload = LLMRequestPayload(
                    messages: messages,
                    stream: enableStreaming ? true : nil
                )
                payloadData = try encoder.encode(payload)
            }

            request.httpBody = payloadData

            if let jsonString = String(data: payloadData, encoding: .utf8) {
                Logger.debug("[LLMService] Request Debug - Model: \(model.displayName)")
                Logger.debug("[LLMService] URL: \(requestURL.absoluteString)")
                Logger.debug("[LLMService] Action: \(action.name)")
                Logger.debug("[LLMService] Original Prompt: \(action.prompt)")
                Logger
                    .debug(
                        "[LLMService] Target Language: \(AppPreferences.shared.targetLanguage.rawValue) (\(AppPreferences.shared.targetLanguage.promptDescriptor))"
                    )
                Logger.debug("[LLMService] Request payload: \(jsonString)")
            }

            try Task.checkCancellation()

            if enableStreaming, let partialHandler {
                return try await handleModelStreamingRequest(
                    start: start,
                    request: request,
                    model: model,
                    decoder: decoder,
                    structuredOutputConfig: structuredOutputConfig,
                    partialHandler: partialHandler
                )
            } else {
                let (data, response) = try await urlSession.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                let responseString = String(data: data, encoding: .utf8) ?? ""
                Logger.debug("[LLMService] Response JSON from \(model.displayName): \(responseString)")

                guard (200 ... 299).contains(httpResponse.statusCode) else {
                    throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, body: responseString)
                }

                let parsed = try parseResponsePayload(
                    data: data,
                    structuredOutput: structuredOutputConfig
                )
                let trimmed = parsed.message.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw LLMServiceError.emptyContent }
                return ModelExecutionResult(
                    modelID: model.id,
                    duration: Date().timeIntervalSince(start),
                    response: .success(trimmed),
                    diffSource: parsed.diffSource?.trimmingCharacters(in: .whitespacesAndNewlines),
                    supplementalTexts: parsed.supplementalTexts,
                    sentencePairs: parsed.sentencePairs
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ModelExecutionResult(
                modelID: model.id,
                duration: Date().timeIntervalSince(start),
                response: .failure(error)
            )
        }
    }

    private func handleModelStreamingRequest(
        start: Date,
        request: URLRequest,
        model: ModelConfig,
        decoder: JSONDecoder,
        structuredOutputConfig: ActionConfig.StructuredOutputConfig?,
        partialHandler: @MainActor @Sendable (String, StreamingUpdate) -> Void
    ) async throws -> ModelExecutionResult {
        let (bytes, response) = try await urlSession.bytes(for: request)

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            var errorBytes: [UInt8] = []
            for try await chunk in bytes {
                errorBytes.append(chunk)
            }
            let responseString = String(data: Data(errorBytes), encoding: .utf8) ?? ""
            Logger.debug("[LLMService] Response JSON from \(model.displayName): \(responseString)")
            throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, body: responseString)
        }

        let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let isSentencePairsMode = structuredOutputConfig?.primaryField == "sentence_pairs"
        let isStructuredOutputMode = structuredOutputConfig != nil && !isSentencePairsMode

        if contentType.contains("text/event-stream") {
            Logger.debug("[LLMService] Streaming response from \(model.displayName)")
            var aggregatedText = ""
            let sentencePairParser = isSentencePairsMode ? StreamingSentencePairParser() : nil
            let structuredParser = isStructuredOutputMode ? StreamingStructuredOutputParser(config: structuredOutputConfig!) : nil

            for try await line in bytes.lines {
                try Task.checkCancellation()
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedLine.hasPrefix("data:") else { continue }
                let payload = trimmedLine.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" {
                    break
                }

                guard let data = payload.data(using: .utf8), !data.isEmpty else { continue }
                let chunk = try decoder.decode(ChatCompletionsStreamChunk.self, from: data)
                let deltaText = chunk.combinedText
                guard !deltaText.isEmpty else { continue }
                aggregatedText.append(deltaText)

                if let parser = sentencePairParser {
                    let pairs = parser.append(deltaText)
                    await partialHandler(model.id, .sentencePairs(pairs))
                } else if let parser = structuredParser {
                    let displayText = parser.append(deltaText)
                    await partialHandler(model.id, .text(displayText))
                } else {
                    await partialHandler(model.id, .text(aggregatedText))
                }
            }

            let finalText = aggregatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            guard !finalText.isEmpty else { throw LLMServiceError.emptyContent }

            Logger.debug("[LLMService] Final stream output from \(model.displayName): \(finalText)")

            if isSentencePairsMode {
                let pairs = parseSentencePairsFromJSON(finalText)
                let combinedText = pairs.map { "\($0.original)\n\($0.translation)" }.joined(separator: "\n\n")
                return ModelExecutionResult(
                    modelID: model.id,
                    duration: Date().timeIntervalSince(start),
                    response: .success(combinedText.isEmpty ? finalText : combinedText),
                    sentencePairs: pairs
                )
            }

            if let config = structuredOutputConfig {
                let parsed = parseStructuredOutputFromJSON(finalText, config: config)
                if let parsed {
                    return ModelExecutionResult(
                        modelID: model.id,
                        duration: Date().timeIntervalSince(start),
                        response: .success(parsed.message),
                        diffSource: parsed.diffSource,
                        supplementalTexts: parsed.supplementalTexts,
                        sentencePairs: []
                    )
                }
            }

            return ModelExecutionResult(
                modelID: model.id,
                duration: Date().timeIntervalSince(start),
                response: .success(finalText)
            )
        } else {
            var responseBytes: [UInt8] = []
            for try await chunk in bytes {
                try Task.checkCancellation()
                responseBytes.append(chunk)
            }
            let data = Data(responseBytes)

            let responseString = String(data: data, encoding: .utf8) ?? ""
            Logger.debug("[LLMService] Non-stream response from \(model.displayName): \(responseString)")

            let parsed = try parseResponsePayload(data: data, structuredOutput: structuredOutputConfig)
            let trimmed = parsed.message.trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            guard !trimmed.isEmpty else { throw LLMServiceError.emptyContent }

            if !parsed.sentencePairs.isEmpty {
                await partialHandler(model.id, .sentencePairs(parsed.sentencePairs))
            } else {
                await partialHandler(model.id, .text(trimmed))
            }

            return ModelExecutionResult(
                modelID: model.id,
                duration: Date().timeIntervalSince(start),
                response: .success(trimmed),
                sentencePairs: parsed.sentencePairs
            )
        }
    }

    // MARK: - Conversation Continuation

    /// Sends a continuation message in an ongoing conversation.
    /// Accepts a pre-built messages array (full conversation history) and streams the response.
    /// No structured output / response_format is used for follow-up conversation.
    public func sendContinuation(
        messages: [LLMRequestPayload.Message],
        model: ModelConfig,
        partialHandler: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        let requestURL = CloudServiceConstants.endpoint
            .appendingPathComponent(model.id)
            .appendingPathComponent("chat/completions")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let path = "/\(model.id)/chat/completions"
        applyCloudAuth(to: &request, path: path)

        let payload = LLMRequestPayload(messages: messages, stream: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        request.httpBody = try encoder.encode(payload)

        Logger.debug("[LLMService] Continuation request - Model: \(model.displayName)")
        Logger.debug("[LLMService] URL: \(requestURL.absoluteString)")
        Logger.debug("[LLMService] Messages count: \(messages.count)")

        try Task.checkCancellation()

        let (bytes, response) = try await urlSession.bytes(for: request)

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            var errorBytes: [UInt8] = []
            for try await chunk in bytes {
                errorBytes.append(chunk)
            }
            let responseString = String(data: Data(errorBytes), encoding: .utf8) ?? ""
            throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, body: responseString)
        }

        let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let decoder = JSONDecoder.llmDecoder

        if contentType.contains("text/event-stream") {
            var aggregatedText = ""

            for try await line in bytes.lines {
                try Task.checkCancellation()
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedLine.hasPrefix("data:") else { continue }
                let payload = trimmedLine.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }

                guard let data = payload.data(using: .utf8), !data.isEmpty else { continue }
                let chunk = try decoder.decode(ChatCompletionsStreamChunk.self, from: data)
                let deltaText = chunk.combinedText
                guard !deltaText.isEmpty else { continue }
                aggregatedText.append(deltaText)
                await partialHandler(aggregatedText)
            }

            let finalText = aggregatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !finalText.isEmpty else { throw LLMServiceError.emptyContent }
            return finalText
        } else {
            // Non-streaming fallback
            var responseBytes: [UInt8] = []
            for try await chunk in bytes {
                try Task.checkCancellation()
                responseBytes.append(chunk)
            }
            let data = Data(responseBytes)
            let parsed = try parseResponsePayload(data: data, structuredOutput: nil)
            let trimmed = parsed.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw LLMServiceError.emptyContent }
            await partialHandler(trimmed)
            return trimmed
        }
    }

    /// Parse sentence pairs from raw JSON string
    private func parseSentencePairsFromJSON(_ jsonString: String) -> [SentencePair] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pairsArray = json["sentence_pairs"] as? [[String: Any]]
        else {
            return []
        }

        return pairsArray.compactMap { dict -> SentencePair? in
            guard let original = dict["original"] as? String,
                  let translation = dict["translation"] as? String
            else {
                return nil
            }
            let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedOriginal.isEmpty, !trimmedTranslation.isEmpty else {
                return nil
            }
            return SentencePair(
                original: trimmedOriginal,
                translation: trimmedTranslation
            )
        }
    }

    /// Parse structured output from raw JSON string (e.g., for grammar check)
    private func parseStructuredOutputFromJSON(
        _ jsonString: String,
        config: ActionConfig.StructuredOutputConfig
    ) -> ParsedResponse? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        guard let primaryValue = json[config.primaryField] as? String,
              !primaryValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let trimmedPrimary = primaryValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var supplemental: [String] = []
        for field in config.additionalFields {
            guard let value = json[field] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }
            supplemental.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var sections = [trimmedPrimary]
        sections.append(contentsOf: supplemental)
        let combined = sections.joined(separator: "\n\n")

        return ParsedResponse(
            message: combined,
            diffSource: trimmedPrimary,
            supplementalTexts: supplemental,
            sentencePairs: []
        )
    }
}

/// Incremental parser for streaming structured output (e.g., grammar check).
/// Extracts field values as they stream in, hiding the JSON structure from the user.
private final class StreamingStructuredOutputParser {
    private var buffer = ""
    private let config: ActionConfig.StructuredOutputConfig
    private let fieldRegex: NSRegularExpression?

    init(config: ActionConfig.StructuredOutputConfig) {
        self.config = config
        let fieldPattern = "\"\(config.primaryField)\"\\s*:\\s*\""
        self.fieldRegex = try? NSRegularExpression(pattern: fieldPattern, options: [])
    }

    /// Append new delta text and return the display text for UI.
    func append(_ delta: String) -> String {
        buffer.append(delta)
        return extractDisplayText()
    }

    private func extractDisplayText() -> String {
        // Try to extract the primary field value incrementally
        // Look for pattern like "revised_text": "..."
        guard let fieldRegex else {
            return ""
        }

        let nsBuffer = buffer as NSString
        let range = NSRange(location: 0, length: nsBuffer.length)
        guard let match = fieldRegex.firstMatch(in: buffer, options: [], range: range) else {
            return ""
        }

        // Find content after the opening quote
        let contentStart = match.range.upperBound
        guard contentStart < nsBuffer.length else { return "" }

        // UTF-16 character constants
        let backslashChar: unichar = 0x5C // '\'
        let quoteChar: unichar = 0x22 // '"'
        let nChar: unichar = 0x6E // 'n'
        let tChar: unichar = 0x74 // 't'
        let rChar: unichar = 0x72 // 'r'

        // Extract content, handling escaped characters
        var result = ""
        var index = contentStart
        while index < nsBuffer.length {
            let char = nsBuffer.character(at: index)
            if char == backslashChar && index + 1 < nsBuffer.length {
                // Handle escape sequence
                let nextChar = nsBuffer.character(at: index + 1)
                switch nextChar {
                case nChar:
                    result.append("\n")
                case tChar:
                    result.append("\t")
                case rChar:
                    result.append("\r")
                case quoteChar:
                    result.append("\"")
                case backslashChar:
                    result.append("\\")
                default:
                    if let scalar = UnicodeScalar(nextChar) {
                        result.append(Character(scalar))
                    }
                }
                index += 2
            } else if char == quoteChar {
                // End of string value
                break
            } else {
                if let scalar = UnicodeScalar(char) {
                    result.append(Character(scalar))
                }
                index += 1
            }
        }

        return result
    }
}

/// Incremental JSON parser for streaming sentence pairs.
/// Extracts completed sentence pair objects as they become available.
private final class StreamingSentencePairParser {
    private var buffer = ""
    private var emittedPairs: [SentencePair] = []
    private var scanOffset = 0
    private let pairRegex: NSRegularExpression?

    init() {
        let pattern =
            #"\{\s*"(?:original|translation)"\s*:\s*"(?:[^"\\]|\\.)*"\s*,\s*"(?:original|translation)"\s*:\s*"(?:[^"\\]|\\.)*"\s*\}"#
        self.pairRegex = try? NSRegularExpression(pattern: pattern, options: [])
    }

    /// Append new delta text and return all completed pairs found so far.
    func append(_ delta: String) -> [SentencePair] {
        buffer.append(delta)

        // Try to extract completed sentence pair objects
        let newPairs = extractCompletedPairs()
        if !newPairs.isEmpty {
            emittedPairs.append(contentsOf: newPairs)
        }

        return emittedPairs
    }

    private func extractCompletedPairs() -> [SentencePair] {
        var pairs: [SentencePair] = []

        guard let regex = pairRegex else {
            return pairs
        }

        let nsString = buffer as NSString
        let searchRange = NSRange(location: scanOffset, length: nsString.length - scanOffset)
        let matches = regex.matches(in: buffer, options: [], range: searchRange)

        for match in matches {
            let matchString = nsString.substring(with: match.range)
            if let pair = parseSinglePair(matchString) {
                pairs.append(pair)
            }
            // Advance scan offset past this match
            scanOffset = match.range.upperBound
        }

        return pairs
    }

    private func parseSinglePair(_ jsonString: String) -> SentencePair? {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let original = dict["original"],
              let translation = dict["translation"]
        else {
            return nil
        }

        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty, !trimmedTranslation.isEmpty else {
            return nil
        }

        return SentencePair(
            original: trimmedOriginal,
            translation: trimmedTranslation
        )
    }
}

private extension LLMService {
    struct ChatCompletionsResponse: Decodable {
        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: MessageContent?
        }

        enum MessageContent: Decodable {
            case text(String)
            case parts([MessagePart])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) {
                    self = .text(text)
                } else if let parts = try? container.decode([MessagePart].self) {
                    self = .parts(parts)
                } else {
                    self = .text("")
                }
            }
        }

        struct MessagePart: Decodable {
            let type: String?
            let text: String?
            let data: String?
            let content: String?
            let json: JSONValue?
            let jsonSchema: JSONSchemaPayload?
        }

        struct JSONSchemaPayload: Decodable {
            let name: String?
            let schema: JSONValue?
            let output: JSONValue?
            let result: JSONValue?
            let json: JSONValue?
        }

        let choices: [Choice]?
    }

    struct ChatCompletionsStreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta?
        }

        let choices: [Choice]

        var combinedText: String {
            choices.compactMap { $0.delta?.content }.joined()
        }
    }

    enum JSONValue: Codable {
        case string(String)
        case number(Double)
        case object([String: JSONValue])
        case array([JSONValue])
        case bool(Bool)
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let string = try? container.decode(String.self) {
                self = .string(string)
            } else if let bool = try? container.decode(Bool.self) {
                self = .bool(bool)
            } else if let int = try? container.decode(Int.self) {
                self = .number(Double(int))
            } else if let double = try? container.decode(Double.self) {
                self = .number(double)
            } else if let object = try? container.decode([String: JSONValue].self) {
                self = .object(object)
            } else if let array = try? container.decode([JSONValue].self) {
                self = .array(array)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported JSON value"
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .string(value):
                try container.encode(value)
            case let .number(value):
                try container.encode(value)
            case let .object(value):
                try container.encode(value)
            case let .array(value):
                try container.encode(value)
            case let .bool(value):
                try container.encode(value)
            case .null:
                try container.encodeNil()
            }
        }
    }
}

private extension LLMService.JSONValue {
    var objectValue: [String: LLMService.JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var renderedString: String? {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            if value.isFinite {
                let integer = Int64(value)
                if Double(integer) == value {
                    return String(integer)
                }
            }
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        case let .object(value):
            guard let data = try? JSONEncoder.llmEncoder.encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        case let .array(value):
            guard let data = try? JSONEncoder.llmEncoder.encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        case .null:
            return nil
        }
    }

    static func dictionary(from string: String) -> [String: LLMService.JSONValue]? {
        guard let data = string.data(using: .utf8) else { return nil }
        guard let value = try? JSONDecoder.llmDecoder.decode(LLMService.JSONValue.self, from: data),
              case let .object(object) = value
        else {
            return nil
        }
        return object
    }
}

private extension LLMService.ChatCompletionsResponse.Message {
    typealias JSONValue = LLMService.JSONValue

    func structuredDictionary() -> [String: JSONValue]? {
        guard let content else { return nil }
        switch content {
        case let .text(text):
            return JSONValue.dictionary(from: text)
        case let .parts(parts):
            for part in parts {
                if let json = part.json?.objectValue {
                    return json
                }
                if let schema = part.jsonSchema {
                    if let output = schema.output?.objectValue {
                        return output
                    }
                    if let result = schema.result?.objectValue {
                        return result
                    }
                    if let json = schema.json?.objectValue {
                        return json
                    }
                }
                if let text = part.text,
                   let dictionary = JSONValue.dictionary(from: text)
                {
                    return dictionary
                }
                if let content = part.content,
                   let dictionary = JSONValue.dictionary(from: content)
                {
                    return dictionary
                }
            }
            return nil
        }
    }

    func plainText() -> String {
        guard let content else { return "" }
        switch content {
        case let .text(text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case let .parts(parts):
            var fragments: [String] = []
            for part in parts {
                if let text = part.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty
                {
                    fragments.append(text)
                }
                if let content = part.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !content.isEmpty
                {
                    fragments.append(content)
                }
                if let data = part.data?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !data.isEmpty
                {
                    fragments.append(data)
                }
                if let json = part.json?.renderedString?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !json.isEmpty
                {
                    fragments.append(json)
                }
                if let output = part.jsonSchema?.output?.renderedString?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !output.isEmpty
                {
                    fragments.append(output)
                }
                if let result = part.jsonSchema?.result?.renderedString?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !result.isEmpty
                {
                    fragments.append(result)
                }
            }
            return fragments.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

private extension LLMService {
    struct ParsedResponse {
        let message: String
        let diffSource: String?
        let supplementalTexts: [String]
        let sentencePairs: [SentencePair]
    }

    func parseResponsePayload(
        data: Data,
        structuredOutput: ActionConfig.StructuredOutputConfig?
    ) throws -> ParsedResponse {
        let response = try JSONDecoder.llmDecoder.decode(ChatCompletionsResponse.self, from: data)
        guard let message = response.choices?.first?.message else {
            throw LLMServiceError.emptyContent
        }

        if let structuredOutput,
           let dictionary = message.structuredDictionary()
        {
            // Check for sentence_pairs array (for sentence-by-sentence translation)
            if structuredOutput.primaryField == "sentence_pairs",
               let pairsValue = dictionary["sentence_pairs"],
               case let .array(pairsArray) = pairsValue
            {
                let pairs = pairsArray.compactMap { item -> SentencePair? in
                    guard case let .object(obj) = item,
                          let originalValue = obj["original"],
                          let translationValue = obj["translation"],
                          let original = originalValue.renderedString?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let translation = translationValue.renderedString?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !original.isEmpty, !translation.isEmpty
                    else {
                        return nil
                    }
                    return SentencePair(original: original, translation: translation)
                }

                if !pairs.isEmpty {
                    // Build combined text for fallback/copy
                    let combinedText = pairs.map { "\($0.original)\n\($0.translation)" }.joined(separator: "\n\n")
                    return ParsedResponse(
                        message: combinedText,
                        diffSource: nil,
                        supplementalTexts: [],
                        sentencePairs: pairs
                    )
                }
            }

            // Standard structured output handling
            if let primaryValue = dictionary[structuredOutput.primaryField]?.renderedString?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !primaryValue.isEmpty
            {
                var supplemental: [String] = []
                for field in structuredOutput.additionalFields {
                    guard let value = dictionary[field]?.renderedString?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                        !value.isEmpty
                    else {
                        continue
                    }
                    supplemental.append(value)
                }
                var sections = [primaryValue]
                sections.append(contentsOf: supplemental)
                let combined = sections.joined(separator: "\n\n")
                if !combined.isEmpty {
                    return ParsedResponse(
                        message: combined,
                        diffSource: primaryValue,
                        supplementalTexts: supplemental,
                        sentencePairs: []
                    )
                }
            }
        }

        let fallback = message.plainText()
        guard !fallback.isEmpty else {
            throw LLMServiceError.emptyContent
        }
        return ParsedResponse(
            message: fallback,
            diffSource: nil,
            supplementalTexts: [],
            sentencePairs: []
        )
    }
}

private extension JSONDecoder {
    static let llmDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

private extension JSONEncoder {
    static let llmEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
