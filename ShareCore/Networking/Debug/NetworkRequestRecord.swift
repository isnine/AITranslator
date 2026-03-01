//
//  NetworkRequestRecord.swift
//  ShareCore
//
//  Created by Copilot on 2026/02/28.
//

#if DEBUG

import Foundation

/// A single network request/response record for debug inspection.
public struct NetworkRequestRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let source: Source

    // Request
    public let httpMethod: String
    public let url: String
    public let requestHeaders: [String: String]
    public let requestBody: Data?

    // Response
    public var statusCode: Int?
    public var responseHeaders: [String: String]?
    public var responseBody: Data?
    public var latency: TimeInterval?
    public var errorDescription: String?

    public enum Source: String, Codable, Sendable {
        case app
        case `extension`
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: Source,
        httpMethod: String,
        url: String,
        requestHeaders: [String: String],
        requestBody: Data?,
        statusCode: Int? = nil,
        responseHeaders: [String: String]? = nil,
        responseBody: Data? = nil,
        latency: TimeInterval? = nil,
        errorDescription: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.httpMethod = httpMethod
        self.url = url
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.latency = latency
        self.errorDescription = errorDescription
    }
}

// MARK: - Display Helpers

public extension NetworkRequestRecord {
    /// Short path component for list display (e.g. "/gpt-4o/chat/completions")
    var urlPath: String {
        guard let components = URLComponents(string: url) else { return url }
        return components.path
    }

    var requestBodyString: String? {
        guard let data = requestBody else { return nil }
        return prettyJSON(data) ?? String(data: data, encoding: .utf8)
    }

    var responseBodyString: String? {
        guard let data = responseBody else { return nil }
        return prettyJSON(data) ?? String(data: data, encoding: .utf8)
    }

    var formattedLatency: String {
        guard let latency else { return "—" }
        if latency < 1 {
            return String(format: "%.0f ms", latency * 1000)
        }
        return String(format: "%.2f s", latency)
    }

    var statusColor: StatusColor {
        guard let code = statusCode else { return .unknown }
        switch code {
        case 200 ..< 300: return .success
        case 400 ..< 500: return .clientError
        case 500...: return .serverError
        default: return .unknown
        }
    }

    enum StatusColor: Sendable {
        case success, clientError, serverError, unknown
    }

    private func prettyJSON(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8)
        else { return nil }
        return string
    }
}

#endif
