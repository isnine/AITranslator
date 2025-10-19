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
            return "未从模型返回任何内容"
        case let .httpError(statusCode, body):
            return "HTTP 错误 \(statusCode): \(body)"
        }
    }
}
