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
    public let diffSource: String?
    public let supplementalTexts: [String]
    public let sentencePairs: [SentencePair]

    public init(
        providerID: UUID,
        duration: TimeInterval,
        response: Result<String, Error>,
        diffSource: String? = nil,
        supplementalTexts: [String] = [],
        sentencePairs: [SentencePair] = []
    ) {
        self.providerID = providerID
        self.duration = duration
        self.response = response
        self.diffSource = diffSource
        self.supplementalTexts = supplementalTexts
        self.sentencePairs = sentencePairs
    }
}
