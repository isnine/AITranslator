//
//  MarketplaceAction.swift
//  ShareCore
//
//  Created by Claude on 2026/03/31.
//

import CloudKit
import Foundation

// MARK: - Marketplace Action Model

public struct MarketplaceAction: Identifiable, Hashable, Sendable {
    public let id: String // CKRecord.recordName
    public let name: String
    public let prompt: String
    public let actionDescription: String
    public let outputType: OutputType
    public let usageScenes: ActionConfig.UsageScene
    public let category: MarketplaceCategory
    public let authorName: String
    public let downloadCount: Int64
    public let createdAt: Date
    public let creatorUserRecordName: String?

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

public enum MarketplaceCategory: String, CaseIterable, Sendable, Identifiable {
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

// MARK: - CKRecord Conversion

extension MarketplaceAction {
    static let recordType = "MarketplaceAction"

    enum FieldKey {
        static let name = "name"
        static let prompt = "prompt"
        static let actionDescription = "actionDescription"
        static let outputType = "outputType"
        static let usageScenes = "usageScenes"
        static let category = "category"
        static let authorName = "authorName"
        static let downloadCount = "downloadCount"
    }

    init?(record: CKRecord) {
        guard record.recordType == Self.recordType,
              let name = record[FieldKey.name] as? String,
              let prompt = record[FieldKey.prompt] as? String
        else {
            return nil
        }

        id = record.recordID.recordName
        self.name = name
        self.prompt = prompt
        actionDescription = record[FieldKey.actionDescription] as? String ?? ""
        authorName = record[FieldKey.authorName] as? String ?? "Anonymous"
        downloadCount = record[FieldKey.downloadCount] as? Int64 ?? 0
        createdAt = record.creationDate ?? Date()
        creatorUserRecordName = record.creatorUserRecordID?.recordName

        if let outputTypeRaw = record[FieldKey.outputType] as? String,
           let outputType = OutputType(rawValue: outputTypeRaw)
        {
            self.outputType = outputType
        } else {
            outputType = .plain
        }

        if let scenesRaw = record[FieldKey.usageScenes] as? Int64 {
            usageScenes = ActionConfig.UsageScene(rawValue: Int(scenesRaw))
        } else {
            usageScenes = .all
        }

        if let categoryRaw = record[FieldKey.category] as? String,
           let category = MarketplaceCategory(rawValue: categoryRaw)
        {
            self.category = category
        } else {
            category = .other
        }
    }

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType)
        record[FieldKey.name] = name
        record[FieldKey.prompt] = prompt
        record[FieldKey.actionDescription] = actionDescription
        record[FieldKey.outputType] = outputType.rawValue
        record[FieldKey.usageScenes] = Int64(usageScenes.rawValue)
        record[FieldKey.category] = category.rawValue
        record[FieldKey.authorName] = authorName
        record[FieldKey.downloadCount] = downloadCount
        return record
    }
}
