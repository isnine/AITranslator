//
//  TranslationRecord.swift
//  ShareCore
//
//  Created by Zander Wang on 2026/03/13.
//

import Foundation
import SwiftData

/// A single model's result within a translation request.
public struct ModelResult: Codable, Identifiable, Hashable {
    public var id: UUID
    public var modelID: String
    public var modelDisplayName: String
    public var resultText: String
    public var duration: TimeInterval

    public init(
        id: UUID = UUID(),
        modelID: String,
        modelDisplayName: String,
        resultText: String,
        duration: TimeInterval
    ) {
        self.id = id
        self.modelID = modelID
        self.modelDisplayName = modelDisplayName
        self.resultText = resultText
        self.duration = duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        modelID = try container.decode(String.self, forKey: .modelID)
        modelDisplayName = try container.decode(String.self, forKey: .modelDisplayName)
        resultText = try container.decode(String.self, forKey: .resultText)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
    }
}

@Model
public final class TranslationRecord {
    public var id: UUID
    public var requestID: UUID
    public var sourceText: String
    public var actionName: String
    public var targetLanguage: String
    public var timestamp: Date
    public var isConversation: Bool

    /// JSON-encoded `[ModelResult]`. SwiftData doesn't natively support arrays of
    /// Codable structs, so we store them as raw Data and expose a computed accessor.
    public var modelResultsData: Data

    public var modelResults: [ModelResult] {
        get {
            (try? JSONDecoder().decode([ModelResult].self, from: modelResultsData)) ?? []
        }
        set {
            modelResultsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    public init(
        id: UUID = UUID(),
        requestID: UUID = UUID(),
        sourceText: String,
        actionName: String = "",
        targetLanguage: String = "",
        timestamp: Date = Date(),
        isConversation: Bool = false,
        modelResults: [ModelResult] = []
    ) {
        self.id = id
        self.requestID = requestID
        self.sourceText = sourceText
        self.actionName = actionName
        self.targetLanguage = targetLanguage
        self.timestamp = timestamp
        self.isConversation = isConversation
        modelResultsData = (try? JSONEncoder().encode(modelResults)) ?? Data()
    }
}
