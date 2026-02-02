//
//  VoicesService.swift
//  ShareCore
//
//  Created by AI Assistant on 2025/02/02.
//

import Foundation

public final class VoicesService: Sendable {
    public static let shared = VoicesService()

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Fetches available voices from the worker API.
    /// Falls back to default voices on error.
    public func fetchVoices() async -> [VoiceConfig] {
        do {
            return try await fetchVoicesFromAPI()
        } catch {
            Logger.debug("[VoicesService] Failed to fetch voices from API: \(error). Using defaults.")
            return VoiceConfig.defaultVoices
        }
    }

    private func fetchVoicesFromAPI() async throws -> [VoiceConfig] {
        let url = CloudServiceConstants.endpoint.appendingPathComponent("voices")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoicesServiceError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw VoicesServiceError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        let voicesResponse = try JSONDecoder().decode(VoicesResponse.self, from: data)
        return voicesResponse.voices
    }
}

public enum VoicesServiceError: Error, LocalizedError {
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
