//
//  ProviderExecutionResult.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation

public struct ProviderExecutionResult {
    public let providerID: UUID
    public let duration: TimeInterval
    public let response: Result<String, Error>

    public init(
        providerID: UUID,
        duration: TimeInterval,
        response: Result<String, Error>
    ) {
        self.providerID = providerID
        self.duration = duration
        self.response = response
    }
}
