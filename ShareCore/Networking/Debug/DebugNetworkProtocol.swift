//
//  DebugNetworkProtocol.swift
//  ShareCore
//
//  Created by Copilot on 2026/02/28.
//

#if DEBUG

import Foundation

/// Custom URLProtocol that intercepts HTTP(S) requests and logs them to NetworkRequestLogger.
public final class DebugNetworkProtocol: URLProtocol, URLSessionDataDelegate {
    private static let handledKey = "com.zanderwang.DebugNetworkProtocol.handled"

    private var innerSession: URLSession?
    private var innerTask: URLSessionDataTask?
    private var responseData = Data()
    private var startTime: Date?
    private var httpResponse: HTTPURLResponse?

    // MARK: - URLProtocol Overrides

    override public class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme, ["http", "https"].contains(scheme) else {
            return false
        }
        if URLProtocol.property(forKey: handledKey, in: request) != nil {
            return false
        }
        return true
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override public func startLoading() {
        startTime = Date()

        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)

        let config = URLSessionConfiguration.default
        innerSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        innerTask = innerSession?.dataTask(with: mutableRequest as URLRequest)
        innerTask?.resume()
    }

    override public func stopLoading() {
        innerTask?.cancel()
        innerTask = nil
        innerSession?.invalidateAndCancel()
        innerSession = nil
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        httpResponse = response as? HTTPURLResponse
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData.append(data)
        client?.urlProtocol(self, didLoad: data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            logRecord(error: error)
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            logRecord(error: nil)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    // MARK: - Logging

    private func logRecord(error: Error?) {
        let latency = startTime.map { Date().timeIntervalSince($0) }
        let source: NetworkRequestRecord.Source = {
            let bundleID = Bundle.main.bundleIdentifier ?? ""
            return bundleID.contains("TranslationUI") ? .extension : .app
        }()

        let requestHeaders = request.allHTTPHeaderFields ?? [:]

        var requestBody = request.httpBody
        if requestBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
                stream.close()
            }
            while stream.hasBytesAvailable {
                let bytesRead = stream.read(buffer, maxLength: bufferSize)
                if bytesRead > 0 {
                    data.append(buffer, count: bytesRead)
                }
            }
            if !data.isEmpty {
                requestBody = data
            }
        }

        var responseHeaders: [String: String]?
        if let headers = httpResponse?.allHeaderFields as? [String: String] {
            responseHeaders = headers
        }

        let record = NetworkRequestRecord(
            source: source,
            httpMethod: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "",
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            statusCode: httpResponse?.statusCode,
            responseHeaders: responseHeaders,
            responseBody: responseData.isEmpty ? nil : responseData,
            latency: latency,
            errorDescription: error?.localizedDescription
        )

        NetworkRequestLogger.addRecord(record)
    }
}

#endif
