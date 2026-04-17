//
//  GoogleTranslateService.swift
//  ShareCore
//
//  Created by Claude on 2025/04/16.
//

import Foundation

/// Free Google Translate via the GTX API (no API key required).
public final class GoogleTranslateService: Sendable {
    public static let shared = GoogleTranslateService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private init() {}

    /// Translates text using the free Google Translate GTX endpoint.
    /// - Parameters:
    ///   - text: Source text to translate.
    ///   - sourceCode: BCP 47 source language code, or `nil` for auto-detection.
    ///   - targetCode: BCP 47 target language code.
    /// - Returns: A `ModelExecutionResult` with the translated text.
    public func translate(
        text: String,
        sourceCode: String?,
        targetCode: String
    ) async -> ModelExecutionResult {
        let start = Date()
        do {
            let translated = try await performRequest(text: text, sourceCode: sourceCode, targetCode: targetCode)
            return ModelExecutionResult(
                modelID: ModelConfig.googleTranslateID,
                duration: Date().timeIntervalSince(start),
                response: .success(translated)
            )
        } catch {
            return ModelExecutionResult(
                modelID: ModelConfig.googleTranslateID,
                duration: Date().timeIntervalSince(start),
                response: .failure(error)
            )
        }
    }

    private func performRequest(text: String, sourceCode: String?, targetCode: String) async throws -> String {
        let sl = mapToGoogleCode(sourceCode) ?? "auto"
        let tl = mapToGoogleCode(targetCode) ?? targetCode

        guard var components = URLComponents(string: "https://translate.google.com/translate_a/single") else {
            throw GoogleTranslateError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: sl),
            URLQueryItem(name: "tl", value: tl),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "dj", value: "1"),
            URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "q", value: text),
        ]

        guard let url = components.url else {
            throw GoogleTranslateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)

        let httpResponse = try response.asHTTP(or: GoogleTranslateError.invalidResponse)
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GoogleTranslateError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        let json = try JSONDecoder().decode(GTXResponse.self, from: data)
        let translated = json.sentences.compactMap(\.trans).joined()

        guard !translated.isEmpty else {
            throw GoogleTranslateError.emptyResult
        }
        return translated
    }

    /// Maps BCP 47 codes to Google Translate codes where they differ.
    private func mapToGoogleCode(_ bcp47: String?) -> String? {
        guard let code = bcp47 else { return nil }
        switch code {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "pt-BR": return "pt"
        default: return code
        }
    }
}

// MARK: - Response Model

private struct GTXResponse: Decodable {
    let sentences: [Sentence]

    struct Sentence: Decodable {
        let trans: String?
    }
}

// MARK: - Error

public enum GoogleTranslateError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Google Translate URL"
        case .invalidResponse:
            return "Invalid response from Google Translate"
        case let .apiError(statusCode, message):
            return "Google Translate error (\(statusCode)): \(message)"
        case .emptyResult:
            return "Google Translate returned an empty result"
        }
    }
}
