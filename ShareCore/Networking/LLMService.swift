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
        providers: [ProviderConfig]
    ) async -> [ProviderExecutionResult] {
        await withTaskGroup(of: ProviderExecutionResult?.self) { group in
            for provider in providers {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return await self.sendRequest(
                        text: text,
                        action: action,
                        provider: provider
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
        provider: ProviderConfig
    ) async -> ProviderExecutionResult {
        let start = Date()

        var request = URLRequest(url: provider.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(provider.token, forHTTPHeaderField: provider.authHeaderName)

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

        let payload = LLMRequestPayload(messages: messages)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let encodedPayload = try encoder.encode(payload)
            request.httpBody = encodedPayload

            if let jsonString = String(data: encodedPayload, encoding: .utf8) {
                print("Sending request to \(provider.apiURL.absoluteString)")
                print("Request payload: \(jsonString)")
            }

            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            let responseString = String(data: data, encoding: .utf8) ?? ""
            print("Response JSON from \(provider.displayName): \(responseString)")

            guard (200...299).contains(httpResponse.statusCode) else {
                throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, body: responseString)
            }

            let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
            if let message = decoded.choices?.first?.message.content, !message.isEmpty {
                return ProviderExecutionResult(
                    providerID: provider.id,
                    duration: Date().timeIntervalSince(start),
                    response: .success(message.trimmingCharacters(in: .whitespacesAndNewlines))
                )
            } else {
                throw LLMServiceError.emptyContent
            }
        } catch {
            return ProviderExecutionResult(
                providerID: provider.id,
                duration: Date().timeIntervalSince(start),
                response: .failure(error)
            )
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
