//
//  MarketplaceAction.swift
//  ShareCore
//
//  Created by Claude on 2026/03/31.
//

import Foundation

// MARK: - Marketplace Action Model

public struct MarketplaceAction: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let prompt: String
    public let actionDescription: String
    public let outputType: OutputType
    public let usageScenes: ActionConfig.UsageScene
    public let category: MarketplaceCategory
    public let authorName: String
    public var downloadCount: Int64
    public let createdAt: Date
    public let creatorId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, prompt, category
        case actionDescription = "action_description"
        case outputType = "output_type"
        case usageScenes = "usage_scenes"
        case authorName = "author_name"
        case downloadCount = "download_count"
        case createdAt = "created_at"
        case creatorId = "creator_id"
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: MarketplaceAction, rhs: MarketplaceAction) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Conversion to ActionConfig

public extension MarketplaceAction {
    func toActionConfig() -> ActionConfig {
        ActionConfig(
            name: name,
            prompt: prompt,
            usageScenes: usageScenes,
            outputType: outputType
        )
    }
}

// MARK: - Category

public enum MarketplaceCategory: String, CaseIterable, Sendable, Identifiable, Codable {
    case translation
    case writing
    case analysis
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .translation: return String(localized: "Translation", comment: "Marketplace category")
        case .writing: return String(localized: "Writing", comment: "Marketplace category")
        case .analysis: return String(localized: "Analysis", comment: "Marketplace category")
        case .other: return String(localized: "Other", comment: "Marketplace category")
        }
    }

    public var systemImage: String {
        switch self {
        case .translation: return "globe"
        case .writing: return "pencil.line"
        case .analysis: return "magnifyingglass"
        case .other: return "ellipsis.circle"
        }
    }
}

// MARK: - Sort Option

public enum MarketplaceSortOption: String, CaseIterable, Sendable {
    case newest
    case popular

    public var displayName: String {
        switch self {
        case .newest: return String(localized: "Newest", comment: "Marketplace sort option")
        case .popular: return String(localized: "Popular", comment: "Marketplace sort option")
        }
    }
}
