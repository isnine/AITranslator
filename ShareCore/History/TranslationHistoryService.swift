//
//  TranslationHistoryService.swift
//  ShareCore
//
//  Created by Zander Wang on 2026/03/13.
//

import Foundation
import os
import SwiftData

private let logger = os.Logger(subsystem: "com.zanderwang.AITranslator", category: "History")

public extension Notification.Name {
    static let translationRecordSaved = Notification.Name("com.tlingo.translationRecordSaved")
}

@MainActor
public final class TranslationHistoryService {
    public static let shared = TranslationHistoryService()

    private static let appGroupIdentifier = AppPreferences.appGroupSuiteName

    private let modelContainer: ModelContainer?
    private let persistentContext: ModelContext?

    private init() {
        let storeURL = Self.historyStoreURL()

        guard let storeURL else {
            logger.debug("Could not determine storage directory — history disabled")
            modelContainer = nil
            persistentContext = nil
            return
        }

        // Ensure directory exists
        let directory = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Delete old-schema database if it exists (one-time migration from v1)
        Self.deleteOldStoreIfNeeded(at: storeURL)

        do {
            let schema = Schema([TranslationRecord.self])
            let config = ModelConfiguration(
                "TranslationHistory",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            persistentContext = ModelContext(modelContainer!)
            logger.info("Initialized at \(storeURL.path, privacy: .public)")
        } catch {
            logger.error("ModelContainer init failed: \(error.localizedDescription, privacy: .public)")
            modelContainer = nil
            persistentContext = nil
        }
    }

    // MARK: - Save

    // Saves or appends a model result to the record identified by `requestID`.
    // swiftlint:disable:next function_parameter_count
    public func save(
        requestID: UUID,
        sourceText: String,
        resultText: String,
        actionName: String,
        targetLanguage: String,
        modelID: String,
        modelDisplayName: String,
        duration: TimeInterval,
        isConversation: Bool = false
    ) {
        guard let persistentContext else { return }

        let newResult = ModelResult(
            modelID: modelID,
            modelDisplayName: modelDisplayName,
            resultText: resultText,
            duration: duration
        )

        // Try to find existing record for this request
        var descriptor = FetchDescriptor<TranslationRecord>(
            predicate: #Predicate { $0.requestID == requestID }
        )
        descriptor.fetchLimit = 1

        if let existing = try? persistentContext.fetch(descriptor).first {
            var results = existing.modelResults
            results.append(newResult)
            existing.modelResults = results
        } else {
            let record = TranslationRecord(
                requestID: requestID,
                sourceText: sourceText,
                actionName: actionName,
                targetLanguage: targetLanguage,
                isConversation: isConversation,
                modelResults: [newResult]
            )
            persistentContext.insert(record)
        }

        do {
            try persistentContext.save()
            logger.debug("Saved translation record for request \(requestID.uuidString.prefix(8), privacy: .public)")
            NotificationCenter.default.post(name: .translationRecordSaved, object: nil)
        } catch {
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Fetch

    public func fetchAll() -> [TranslationRecord] {
        guard let persistentContext else { return [] }
        var descriptor = FetchDescriptor<TranslationRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        return (try? persistentContext.fetch(descriptor)) ?? []
    }

    public func fetchSince(_ date: Date) -> [TranslationRecord] {
        guard let persistentContext else { return [] }
        var descriptor = FetchDescriptor<TranslationRecord>(
            predicate: #Predicate { $0.timestamp >= date },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        return (try? persistentContext.fetch(descriptor)) ?? []
    }

    // MARK: - Delete

    public func delete(_ record: TranslationRecord) {
        guard let persistentContext else { return }
        let recordID = record.id
        var descriptor = FetchDescriptor<TranslationRecord>(
            predicate: #Predicate { $0.id == recordID }
        )
        descriptor.fetchLimit = 1
        guard let found = try? persistentContext.fetch(descriptor).first else { return }
        persistentContext.delete(found)
        try? persistentContext.save()
    }

    public func deleteAll() {
        guard let persistentContext else { return }
        do {
            try persistentContext.delete(model: TranslationRecord.self)
            try persistentContext.save()
            logger.info("Deleted all records")
        } catch {
            logger.error("Delete all failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Store URL

    private static func historyStoreURL() -> URL? {
        #if os(macOS)
            // Use Application Support on macOS to avoid the "Access Data from Other Apps"
            // permission dialog that App Group containers trigger.
            guard let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                return nil
            }
            return appSupport
                .appendingPathComponent("History", isDirectory: true)
                .appendingPathComponent("TranslationHistory.store")
        #else
            guard let groupContainer = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            ) else {
                return nil
            }
            return groupContainer
                .appendingPathComponent("History", isDirectory: true)
                .appendingPathComponent("TranslationHistory.store")
        #endif
    }

    // MARK: - Migration

    /// Removes any existing SQLite files at the store URL if they use the old schema.
    /// The v1 schema had `resultText`/`modelID` columns directly on TranslationRecord;
    /// v2 uses `modelResultsData`. Since history is ephemeral, we just delete and start fresh.
    private static func deleteOldStoreIfNeeded(at url: URL) {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else { return }

        // Quick check: if the file is small and recent, it's probably v2 already.
        // For a reliable check, try to open with the new schema and see if it fails.
        // Simpler approach: check if the migration marker exists.
        let markerKey = "history.v2.migrated"
        guard !UserDefaults.standard.bool(forKey: markerKey) else { return }

        // Remove SQLite files (main + WAL + SHM)
        let suffixes = ["", "-wal", "-shm"]
        for suffix in suffixes {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
        UserDefaults.standard.set(true, forKey: markerKey)
        logger.debug("Removed v1 history store for schema migration")
    }
}
