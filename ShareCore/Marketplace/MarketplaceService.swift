//
//  MarketplaceService.swift
//  ShareCore
//
//  Created by Claude on 2026/03/31.
//

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

    private let session: URLSession
    private var currentPage = 1
    private var fetchNonce: UUID?
    private static let pageSize = 20

    private var lastSearchText = ""
    private var lastCategory: MarketplaceCategory?
    private var lastSortBy: MarketplaceSortOption = .newest

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init(session: URLSession = NetworkSession.shared) {
        self.session = session
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
        currentPage = 1
        actions = []
        hasMoreResults = true

        lastSearchText = searchText
        lastCategory = category
        lastSortBy = sortBy

        do {
            let response = try await performFetch(
                searchText: searchText,
                category: category,
                sortBy: sortBy,
                page: currentPage
            )
            guard fetchNonce == nonce else { return }
            actions = response.actions
            hasMoreResults = response.hasMore
        } catch {
            guard fetchNonce == nonce else { return }
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    public func fetchNextPage() async {
        guard !isLoading, hasMoreResults else { return }
        isLoading = true
        currentPage += 1

        do {
            let response = try await performFetch(
                searchText: lastSearchText,
                category: lastCategory,
                sortBy: lastSortBy,
                page: currentPage
            )
            actions.append(contentsOf: response.actions)
            hasMoreResults = response.hasMore
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

        let body = CreateActionRequest(
            name: action.name,
            prompt: action.prompt,
            actionDescription: description,
            outputType: action.outputType.rawValue,
            usageScenes: action.usageScenes.rawValue,
            category: category.rawValue,
            authorName: authorName.isEmpty ? "Anonymous" : authorName
        )

        var request = buildRequest(path: "/marketplace/actions", method: "POST")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        let createResponse = try Self.decoder.decode(CreateResponse.self, from: data)
        actions.insert(createResponse.action, at: 0)
        return createResponse.action
    }

    public func delete(_ action: MarketplaceAction) async throws {
        var request = buildRequest(
            path: "/marketplace/actions/\(action.id)",
            method: "DELETE"
        )
        request.setValue(AnonymousUserID.current, forHTTPHeaderField: "X-User-ID")

        let (_, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        actions.removeAll { $0.id == action.id }
    }

    public func incrementDownloadCount(for action: MarketplaceAction) {
        Task {
            do {
                let request = buildRequest(
                    path: "/marketplace/actions/\(action.id)/download",
                    method: "POST"
                )
                let (data, _) = try await session.data(for: request)
                let result = try Self.decoder.decode(DownloadResponse.self, from: data)

                if let index = actions.firstIndex(where: { $0.id == action.id }) {
                    actions[index].downloadCount = result.downloadCount
                }
            } catch {
                // Download count increment is best-effort
            }
        }
    }

    public func isOwnedByCurrentUser(_ action: MarketplaceAction) -> Bool {
        guard let creatorId = action.creatorId else { return false }
        return creatorId == AnonymousUserID.current
    }

    public func ensureUserRecordFetched() async {
        // No-op: anonymous user ID is available synchronously via AnonymousUserID.current
    }

    // MARK: - Private

    private func performFetch(
        searchText: String,
        category: MarketplaceCategory?,
        sortBy: MarketplaceSortOption,
        page: Int
    ) async throws -> ListResponse {
        var components = URLComponents(
            url: CloudServiceConstants.endpoint.appendingPathComponent("marketplace/actions"),
            resolvingAgainstBaseURL: false
        )!

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(Self.pageSize))
        ]

        if !searchText.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: searchText))
        }
        if let category {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }

        let sortValue = sortBy == .popular ? "popular" : "newest"
        queryItems.append(URLQueryItem(name: "sort", value: sortValue))

        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let path = "/marketplace/actions"
        CloudAuthHelper.applyAuth(to: &request, path: path)
        request.setValue(AnonymousUserID.current, forHTTPHeaderField: "X-User-ID")

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        return try Self.decoder.decode(ListResponse.self, from: data)
    }

    private func buildRequest(path: String, method: String) -> URLRequest {
        let url = CloudServiceConstants.endpoint.appendingPathComponent(
            path.hasPrefix("/") ? String(path.dropFirst()) : path
        )
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        CloudAuthHelper.applyAuth(to: &request, path: path)
        request.setValue(AnonymousUserID.current, forHTTPHeaderField: "X-User-ID")

        return request
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MarketplaceError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw MarketplaceError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Response DTOs

private struct ListResponse: Codable {
    let actions: [MarketplaceAction]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case actions
        case hasMore = "has_more"
    }
}

private struct CreateResponse: Codable {
    let action: MarketplaceAction
}

private struct DownloadResponse: Codable {
    let downloadCount: Int64

    enum CodingKeys: String, CodingKey {
        case downloadCount = "download_count"
    }
}

private struct CreateActionRequest: Codable {
    let name: String
    let prompt: String
    let actionDescription: String
    let outputType: String
    let usageScenes: Int
    let category: String
    let authorName: String

    enum CodingKeys: String, CodingKey {
        case name, prompt, category
        case actionDescription = "action_description"
        case outputType = "output_type"
        case usageScenes = "usage_scenes"
        case authorName = "author_name"
    }
}

// MARK: - Errors

public enum MarketplaceError: LocalizedError {
    case invalidRecord
    case invalidResponse
    case httpError(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidRecord:
            return String(localized: "Failed to process marketplace action.", comment: "Marketplace error")
        case .invalidResponse:
            return String(localized: "Invalid server response.", comment: "Marketplace error")
        case let .httpError(statusCode):
            return String(localized: "Server error (\(statusCode)).", comment: "Marketplace error")
        }
    }
}
