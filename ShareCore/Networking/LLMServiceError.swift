//
//  LLMServiceError.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation

public enum LLMServiceError: LocalizedError {
    case emptyContent
    case httpError(statusCode: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "No content returned from the model"
        case let .httpError(statusCode, body):
            return "HTTP error \(statusCode): \(body)"
        }
    }
}
