//
//  ModelsService.swift
//  ShareCore
//
//  Created by Codex on 2025/01/27.
//

import CryptoKit
import Foundation

public final class ModelsService: Sendable {
    public static let shared = ModelsService()

    private let urlSession: URLSession

    // MARK: - Cache

    /// In-memory cache of the most recently fetched models list.
    ///
    /// This is used to avoid a blank UI when navigating to the Models screen.
    private var cachedModels: [ModelConfig]?
    private var lastFetchDate: Date?
    private var inFlightTask: Task<[ModelConfig], Error>?
    private let lock = NSLock()

    // MARK: - Disk cache

    private struct DiskCachePayload: Codable {
        let fetchedAt: Date
        let models: [ModelConfig]
    }

    private var diskCacheURL: URL? {
        do {
            let dir = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return dir.appendingPathComponent("models-cache.json")
        } catch {
            return nil
        }
    }

    public init(urlSession: URLSession = NetworkSession.shared) {
        self.urlSession = urlSession

        // Best-effort: hydrate memory cache from disk so first launch can show something immediately.
        loadDiskCacheIntoMemoryIfNeeded()
    }

    /// Returns the cached models list if available (memory-first, then disk).
    public func getCachedModels() -> [ModelConfig]? {
        lock.lock()
        let inMemory = cachedModels
        lock.unlock()
        if let inMemory, !inMemory.isEmpty {
            return inMemory
        }

        loadDiskCacheIntoMemoryIfNeeded()

        lock.lock()
        defer { lock.unlock() }
        return cachedModels
    }

    private func loadDiskCacheIntoMemoryIfNeeded() {
        lock.lock()
        let alreadyLoaded = cachedModels != nil
        lock.unlock()
        guard !alreadyLoaded else { return }

        guard let url = diskCacheURL else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        guard let payload = try? JSONDecoder().decode(DiskCachePayload.self, from: data) else { return }

        lock.lock()
        cachedModels = payload.models
        lastFetchDate = payload.fetchedAt
        lock.unlock()
    }

    private func persistToDisk(models: [ModelConfig]) {
        guard let url = diskCacheURL else { return }
        let payload = DiskCachePayload(fetchedAt: Date(), models: models)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    /// Fetches models from the server, with optional cache usage.
    ///
    /// - Parameters:
    ///   - forceRefresh: If `false`, returns cached models when available and skips the network request.
    ///   - minimumRefreshInterval: When `forceRefresh` is `true`, suppress refreshes that occur too frequently
    ///     (helps when users quickly switch tabs).
    public func fetchModels(
        forceRefresh: Bool,
        minimumRefreshInterval: TimeInterval = 30
    ) async throws -> [ModelConfig] {
        // If we don't want to refresh, return the cache immediately when available.
        if !forceRefresh, let cached = getCachedModels(), !cached.isEmpty {
            return cached
        }

        // If we have a recent cache and refreshes are happening too frequently, return the cache.
        lock.lock()
        let cached = cachedModels
        let lastFetch = lastFetchDate
        let inFlight = inFlightTask
        lock.unlock()

        if let cached, !cached.isEmpty, let lastFetch, Date().timeIntervalSince(lastFetch) < minimumRefreshInterval {
            return cached
        }

        // Coalesce concurrent refreshes.
        if let inFlight {
            return try await inFlight.value
        }

        let task = Task { [urlSession] in
            defer {
                self.lock.lock()
                self.inFlightTask = nil
                self.lock.unlock()
            }

            var url = CloudServiceConstants.endpoint.appendingPathComponent("models")
            url.append(queryItems: [URLQueryItem(name: "premium", value: "1")])
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await urlSession.data(for: request)

            let httpResponse = try response.asHTTP(or: ModelsServiceError.invalidResponse)

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8)
                throw ModelsServiceError.httpError(statusCode: httpResponse.statusCode, body: body)
            }

            let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)

            self.lock.lock()
            self.cachedModels = modelsResponse.models
            self.lastFetchDate = Date()
            self.lock.unlock()

            self.persistToDisk(models: modelsResponse.models)

            return modelsResponse.models
        }

        lock.lock()
        inFlightTask = task
        lock.unlock()

        return try await task.value
    }

    /// Backwards-compatible entry point (always refresh).
    public func fetchModels() async throws -> [ModelConfig] {
        try await fetchModels(forceRefresh: true)
    }
}

public enum ModelsServiceError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String?)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case let .httpError(statusCode, body):
            if let body {
                return "HTTP \(statusCode): \(body)"
            }
            return "HTTP error \(statusCode)"
        }
    }
}
