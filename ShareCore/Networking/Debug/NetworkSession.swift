//
//  NetworkSession.swift
//  ShareCore
//
//  Created by Copilot on 2026/02/28.
//

import Foundation

/// Provides a URLSession configured for the current build environment.
/// In DEBUG builds, requests are automatically intercepted by DebugNetworkProtocol.
public enum NetworkSession {
    public static let shared: URLSession = {
        #if DEBUG
            let config = URLSessionConfiguration.default
            config.protocolClasses = [DebugNetworkProtocol.self] + (config.protocolClasses ?? [])
            return URLSession(configuration: config)
        #else
            return URLSession.shared
        #endif
    }()
}
