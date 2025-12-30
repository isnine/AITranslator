//
//  LLMService.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//
import Foundation

public final class LLMService {
    public static let shared = LLMService()

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func perform(
        text: String,
        with action: ActionConfig,
        providers: [ProviderConfig],
        partialHandler: (@MainActor @Sendable (UUID, String) -> Void)? = nil,
        completionHandler: (@MainActor @Sendable (ProviderExecutionResult) -> Void)? = nil
    ) async -> [ProviderExecutionResult] {
        await withTaskGroup(of: ProviderExecutionResult?.self) { group in
            for provider in providers {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    do {
                        return try await self.sendRequest(
                            text: text,
                            action: action,
                            provider: provider,
                            partialHandler: partialHandler
                        )
                    } catch is CancellationError {
                        return nil
                    } catch {
                        return nil
                    }
                }
            }

            var results: [ProviderExecutionResult] = []
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

    private func sendRequest(
        text: String,
        action: ActionConfig,
        provider: ProviderConfig,
        partialHandler: (@MainActor @Sendable (UUID, String) -> Void)?
    ) async throws -> ProviderExecutionResult {
        let start = Date()

        var request = URLRequest(url: provider.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(provider.token, forHTTPHeaderField: provider.authHeaderName)
        let structuredOutputConfig = provider.category == .azureOpenAI ? action.structuredOutput : nil
        let streamingHandler = structuredOutputConfig == nil ? partialHandler : nil
        if streamingHandler != nil {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        let messages: [LLMRequestPayload.Message]
        if action.prompt.isEmpty {
            messages = [
                .init(role: "user", content: text)
            ]
        } else {
            messages = [
                .init(role: "system", content: action.prompt),
                .init(role: "user", content: text)
            ]
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let decoder = JSONDecoder.llmDecoder
            let payloadData: Data

            if let structuredOutputConfig,
               let responseFormat = structuredOutputConfig.responseFormatPayload() {
                var body: [String: Any] = [
                    "messages": messages.map { ["role": $0.role, "content": $0.content] }
                ]
                body["response_format"] = responseFormat
                payloadData = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted])
            } else {
                let payload = LLMRequestPayload(
                    messages: messages,
                    stream: streamingHandler != nil ? true : nil
                )
                payloadData = try encoder.encode(payload)
            }

            request.httpBody = payloadData

            if let jsonString = String(data: payloadData, encoding: .utf8) {
                print("Sending request to \(provider.apiURL.absoluteString)")
                print("Request payload: \(jsonString)")
            }

            try Task.checkCancellation()

            if let streamingHandler {
                return try await handleStreamingRequest(
                    start: start,
                    request: request,
                    provider: provider,
                    decoder: decoder,
                    partialHandler: streamingHandler
                )
            } else {
                let (data, response) = try await urlSession.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                let responseString = String(data: data, encoding: .utf8) ?? ""
                print("Response JSON from \(provider.displayName): \(responseString)")

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, body: responseString)
                }

                let parsed = try parseResponsePayload(
                    data: data,
                    structuredOutput: structuredOutputConfig
                )
                let trimmed = parsed.message.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw LLMServiceError.emptyContent }
                return ProviderExecutionResult(
                    providerID: provider.id,
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
            return ProviderExecutionResult(
                providerID: provider.id,
                duration: Date().timeIntervalSince(start),
                response: .failure(error)
            )
        }
    }

    private func handleStreamingRequest(
        start: Date,
        request: URLRequest,
        provider: ProviderConfig,
        decoder: JSONDecoder,
        partialHandler: @MainActor @Sendable (UUID, String) -> Void
    ) async throws -> ProviderExecutionResult {
        let (bytes, response) = try await urlSession.bytes(for: request)

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await chunk in bytes {
                errorData.append(chunk)
            }
            let responseString = String(data: errorData, encoding: .utf8) ?? ""
            print("Response JSON from \(provider.displayName): \(responseString)")
            throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, body: responseString)
        }

        let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()

        if contentType.contains("text/event-stream") {
            print("Streaming response from \(provider.displayName)")
            var aggregatedText = ""
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
                try Task.checkCancellation()
                await partialHandler(provider.id, aggregatedText)
            }

            let finalText = aggregatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            guard !finalText.isEmpty else { throw LLMServiceError.emptyContent }

            print("Final stream output from \(provider.displayName): \(finalText)")

            return ProviderExecutionResult(
                providerID: provider.id,
                duration: Date().timeIntervalSince(start),
                response: .success(finalText)
            )
        } else {
            var data = Data()
            for try await chunk in bytes {
                try Task.checkCancellation()
                data.append(chunk)
            }

            let responseString = String(data: data, encoding: .utf8) ?? ""
            print("Non-stream response from \(provider.displayName): \(responseString)")

            let parsed = try parseResponsePayload(data: data, structuredOutput: nil)
            let trimmed = parsed.message.trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            guard !trimmed.isEmpty else { throw LLMServiceError.emptyContent }
            await partialHandler(provider.id, trimmed)
            return ProviderExecutionResult(
                providerID: provider.id,
                duration: Date().timeIntervalSince(start),
                response: .success(trimmed)
            )
        }
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
              case let .object(object) = value else {
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
                   let dictionary = JSONValue.dictionary(from: text) {
                    return dictionary
                }
                if let content = part.content,
                   let dictionary = JSONValue.dictionary(from: content) {
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
                   !text.isEmpty {
                    fragments.append(text)
                }
                if let content = part.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !content.isEmpty {
                    fragments.append(content)
                }
                if let data = part.data?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !data.isEmpty {
                    fragments.append(data)
                }
                if let json = part.json?.renderedString?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !json.isEmpty {
                    fragments.append(json)
                }
                if let output = part.jsonSchema?.output?.renderedString?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty {
                    fragments.append(output)
                }
                if let result = part.jsonSchema?.result?.renderedString?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !result.isEmpty {
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
           let dictionary = message.structuredDictionary() {
            // Check for sentence_pairs array (for sentence-by-sentence translation)
            if structuredOutput.primaryField == "sentence_pairs",
               let pairsValue = dictionary["sentence_pairs"],
               case let .array(pairsArray) = pairsValue {
                let pairs = pairsArray.compactMap { item -> SentencePair? in
                    guard case let .object(obj) = item,
                          let originalValue = obj["original"],
                          let translationValue = obj["translation"],
                          let original = originalValue.renderedString?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let translation = translationValue.renderedString?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !original.isEmpty, !translation.isEmpty else {
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
               !primaryValue.isEmpty {
                var supplemental: [String] = []
                for field in structuredOutput.additionalFields {
                    guard let value = dictionary[field]?.renderedString?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                          !value.isEmpty else {
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
    static var llmDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private extension JSONEncoder {
    static var llmEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
