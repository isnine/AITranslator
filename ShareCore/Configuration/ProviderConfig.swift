//
//  ProviderConfig.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation

public struct ProviderConfig: Identifiable, Hashable {
    public let id: UUID
    public var displayName: String
    public var apiURL: URL
    public var token: String
    public var authHeaderName: String
    public var category: ProviderCategory
    public var modelName: String

    public init(
        id: UUID = UUID(),
        displayName: String,
        apiURL: URL,
        token: String,
        authHeaderName: String = "api-key",
        category: ProviderCategory = .custom,
        modelName: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.apiURL = apiURL
        self.token = token
        self.authHeaderName = authHeaderName
        self.category = category
        self.modelName = modelName ?? category.defaultModelHint
    }
}
