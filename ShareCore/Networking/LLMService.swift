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
        partialHandler: (@MainActor @Sendable (UUID, String) -> Void)? = nil
    ) async -> [ProviderExecutionResult] {
        await withTaskGroup(of: ProviderExecutionResult?.self) { group in
            for provider in providers {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return await self.sendRequest(
                        text: text,
                        action: action,
                        provider: provider,
                        partialHandler: partialHandler
                    )
                }
            }

            var results: [ProviderExecutionResult] = []
            for await item in group {
                guard let item else { continue }
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
    ) async -> ProviderExecutionResult {
        let start = Date()

        var request = URLRequest(url: provider.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(provider.token, forHTTPHeaderField: provider.authHeaderName)
        if partialHandler != nil {
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
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let payload = LLMRequestPayload(
                messages: messages,
                stream: partialHandler != nil ? true : nil
            )
            let encodedPayload = try encoder.encode(payload)
            request.httpBody = encodedPayload

            if let jsonString = String(data: encodedPayload, encoding: .utf8) {
                print("Sending request to \(provider.apiURL.absoluteString)")
                print("Request payload: \(jsonString)")
            }

            if let partialHandler {
                return try await handleStreamingRequest(
                    start: start,
                    request: request,
                    provider: provider,
                    decoder: decoder,
                    partialHandler: partialHandler
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

                let decoded = try decoder.decode(ChatCompletionsResponse.self, from: data)
                if let message = decoded.choices?.first?.message.content, !message.isEmpty {
                    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                    return ProviderExecutionResult(
                        providerID: provider.id,
                        duration: Date().timeIntervalSince(start),
                        response: .success(trimmed)
                    )
                } else {
                    throw LLMServiceError.emptyContent
                }
            }
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
                await partialHandler(provider.id, aggregatedText)
            }

            let finalText = aggregatedText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                data.append(chunk)
            }

            let responseString = String(data: data, encoding: .utf8) ?? ""
            print("Non-stream response from \(provider.displayName): \(responseString)")

            let decoded = try decoder.decode(ChatCompletionsResponse.self, from: data)
            if let message = decoded.choices?.first?.message.content, !message.isEmpty {
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                await partialHandler(provider.id, trimmed)
                return ProviderExecutionResult(
                    providerID: provider.id,
                    duration: Date().timeIntervalSince(start),
                    response: .success(trimmed)
                )
            } else {
                throw LLMServiceError.emptyContent
            }
        }
    }
}

private struct ChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]?
}

private struct ChatCompletionsStreamChunk: Decodable {
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
