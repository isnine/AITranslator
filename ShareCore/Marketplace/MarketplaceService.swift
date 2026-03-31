//
//  MarketplaceService.swift
//  ShareCore
//
//  Created by Claude on 2026/03/31.
//

import CloudKit
import Combine
import Foundation

@MainActor
public final class MarketplaceService: ObservableObject {
    public static let shared = MarketplaceService()

    // MARK: - Published State

    @Published public private(set) var actions: [MarketplaceAction] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?
    @Published public private(set) var isPublishing = false
    @Published public private(set) var hasMoreResults = true

    // MARK: - Private

    private let container: CKContainer
    private let publicDB: CKDatabase
    private var queryCursor: CKQueryOperation.Cursor?
    private var currentUserRecordName: String?
    private var fetchNonce: UUID?
    private static let containerIdentifier = "iCloud.com.zanderwang.AITranslator"
    private static let pageSize = 20

    private init() {
        container = CKContainer(identifier: Self.containerIdentifier)
        publicDB = container.publicCloudDatabase
    }

    // MARK: - Public API

    public func fetchActions(
        searchText: String = "",
        category: MarketplaceCategory? = nil,
        sortBy: MarketplaceSortOption = .newest
    ) async {
        let nonce = UUID()
        fetchNonce = nonce
        isLoading = true
        error = nil
        queryCursor = nil
        actions = []
        hasMoreResults = true

        do {
            let query = buildQuery(searchText: searchText, category: category, sortBy: sortBy)
            let (results, cursor) = try await publicDB.records(
                matching: query,
                resultsLimit: Self.pageSize
            )
            // Discard results if a newer fetch was started
            guard fetchNonce == nonce else { return }
            let fetched = results.compactMap { _, result in
                try? result.get()
            }.compactMap { MarketplaceAction(record: $0) }

            actions = fetched
            queryCursor = cursor
            hasMoreResults = cursor != nil
        } catch {
            guard fetchNonce == nonce else { return }
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    public func fetchNextPage() async {
        guard let cursor = queryCursor, !isLoading else { return }
        isLoading = true

        do {
            let (results, newCursor) = try await publicDB.records(
                continuingMatchFrom: cursor,
                resultsLimit: Self.pageSize
            )
            let fetched = results.compactMap { _, result in
                try? result.get()
            }.compactMap { MarketplaceAction(record: $0) }

            actions.append(contentsOf: fetched)
            queryCursor = newCursor
            hasMoreResults = newCursor != nil
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    public func publish(
        action: ActionConfig,
        description: String,
        category: MarketplaceCategory,
        authorName: String
    ) async throws -> MarketplaceAction {
        isPublishing = true
        defer { isPublishing = false }

        let record = CKRecord(recordType: MarketplaceAction.recordType)
        record[MarketplaceAction.FieldKey.name] = action.name
        record[MarketplaceAction.FieldKey.prompt] = action.prompt
        record[MarketplaceAction.FieldKey.actionDescription] = description
        record[MarketplaceAction.FieldKey.outputType] = action.outputType.rawValue
        record[MarketplaceAction.FieldKey.usageScenes] = Int64(action.usageScenes.rawValue)
        record[MarketplaceAction.FieldKey.category] = category.rawValue
        record[MarketplaceAction.FieldKey.authorName] = authorName.isEmpty ? "Anonymous" : authorName
        record[MarketplaceAction.FieldKey.downloadCount] = Int64(0)

        let savedRecord = try await publicDB.save(record)

        guard let marketplaceAction = MarketplaceAction(record: savedRecord) else {
            throw MarketplaceError.invalidRecord
        }

        actions.insert(marketplaceAction, at: 0)
        return marketplaceAction
    }

    public func delete(_ action: MarketplaceAction) async throws {
        let recordID = CKRecord.ID(recordName: action.id)
        try await publicDB.deleteRecord(withID: recordID)
        actions.removeAll { $0.id == action.id }
    }

    public func incrementDownloadCount(for action: MarketplaceAction) {
        Task {
            do {
                let recordID = CKRecord.ID(recordName: action.id)
                let record = try await publicDB.record(for: recordID)
                let current = record[MarketplaceAction.FieldKey.downloadCount] as? Int64 ?? 0
                record[MarketplaceAction.FieldKey.downloadCount] = current + 1
                _ = try await publicDB.save(record)

                if let index = actions.firstIndex(where: { $0.id == action.id }) {
                    let updated = MarketplaceAction(record: record)
                    if let updated {
                        actions[index] = updated
                    }
                }
            } catch {
                // Download count increment is best-effort
            }
        }
    }

    public func isOwnedByCurrentUser(_ action: MarketplaceAction) -> Bool {
        guard let currentUser = currentUserRecordName,
              let creator = action.creatorUserRecordName
        else {
            return false
        }
        return currentUser == creator
    }

    public func ensureUserRecordFetched() async {
        guard currentUserRecordName == nil else { return }
        do {
            let recordID = try await container.userRecordID()
            currentUserRecordName = recordID.recordName
        } catch {
            // Not signed in or iCloud unavailable
        }
    }

    // MARK: - Private

    private func buildQuery(
        searchText: String,
        category: MarketplaceCategory?,
        sortBy: MarketplaceSortOption
    ) -> CKQuery {
        var predicates: [NSPredicate] = []

        if !searchText.isEmpty {
            predicates.append(NSPredicate(
                format: "self contains %@",
                searchText
            ))
        }

        if let category {
            predicates.append(NSPredicate(
                format: "%K == %@",
                MarketplaceAction.FieldKey.category,
                category.rawValue
            ))
        }

        let predicate: NSPredicate
        if predicates.isEmpty {
            predicate = NSPredicate(value: true)
        } else {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        let query = CKQuery(recordType: MarketplaceAction.recordType, predicate: predicate)

        switch sortBy {
        case .newest:
            query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        case .popular:
            query.sortDescriptors = [NSSortDescriptor(
                key: MarketplaceAction.FieldKey.downloadCount,
                ascending: false
            )]
        }

        return query
    }
}

// MARK: - Errors

public enum MarketplaceError: LocalizedError {
    case invalidRecord

    public var errorDescription: String? {
        switch self {
        case .invalidRecord:
            return String(localized: "Failed to process marketplace action.", comment: "Marketplace error")
        }
    }
}
