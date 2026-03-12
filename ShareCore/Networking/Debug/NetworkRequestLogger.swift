//
//  NetworkRequestLogger.swift
//  ShareCore
//
//  Created by Copilot on 2026/02/28.
//

#if DEBUG

import Combine
import Foundation

/// Singleton logger that stores network request records in memory and to the app caches directory.
@MainActor
public final class NetworkRequestLogger: ObservableObject {
    public static let shared = NetworkRequestLogger()

    @Published public private(set) var records: [NetworkRequestRecord] = []

    private static let maxRecords = 500
    private let fileURL: URL?

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        self.fileURL = caches?.appendingPathComponent("debug_network_log.jsonl")
    }

    // MARK: - Public API

    /// Add a record. Can be called from any context.
    public static nonisolated func addRecord(_ record: NetworkRequestRecord) {
        Task { @MainActor in
            shared.records.append(record)
            if shared.records.count > maxRecords {
                shared.records.removeFirst(shared.records.count - maxRecords)
            }
            shared.appendToFile(record)
        }
    }

    /// Reload records from the App Group file (picks up records written by the extension).
    public func reloadFromFile() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var loaded: [NetworkRequestRecord] = []
            for line in content.components(separatedBy: "\n") where !line.isEmpty {
                if let data = line.data(using: .utf8),
                   let record = try? decoder.decode(NetworkRequestRecord.self, from: data)
                {
                    loaded.append(record)
                }
            }
            // Merge: keep unique by id, prefer file records for cross-process ones
            let existingIDs = Set(records.map(\.id))
            let newRecords = loaded.filter { !existingIDs.contains($0.id) }
            records.append(contentsOf: newRecords)
            records.sort { $0.timestamp > $1.timestamp }
            if records.count > Self.maxRecords {
                records = Array(records.prefix(Self.maxRecords))
            }
        } catch {
            Logger.debug("[NetworkRequestLogger] Failed to read log file: \(error)")
        }
    }

    /// Clear all records from memory and file.
    public func clearAll() {
        records.removeAll()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - File I/O

    private func appendToFile(_ record: NetworkRequestRecord) {
        guard let fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = []
            let data = try encoder.encode(record)
            guard var line = String(data: data, encoding: .utf8) else { return }
            line.append("\n")

            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                handle.closeFile()
            } else {
                try line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            Logger.debug("[NetworkRequestLogger] Failed to write record: \(error)")
        }
    }
}

#endif
