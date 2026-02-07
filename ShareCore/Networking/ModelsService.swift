//
//  ModelsService.swift
//  ShareCore
//
//  Created by Codex on 2025/01/27.
//

import CryptoKit
import Foundation

public final class ModelsService: Sendable {
    public static let shared = ModelsService()

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func fetchModels() async throws -> [ModelConfig] {
        var url = CloudServiceConstants.endpoint.appendingPathComponent("models")
        url.append(queryItems: [URLQueryItem(name: "premium", value: "1")])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelsServiceError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw ModelsServiceError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return modelsResponse.models
    }
}

public enum ModelsServiceError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String?)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case let .httpError(statusCode, body):
            if let body {
                return "HTTP \(statusCode): \(body)"
            }
            return "HTTP error \(statusCode)"
        }
    }
}
