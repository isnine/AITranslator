//
//  SubscriptionProduct.swift
//  ShareCore
//
//  Created by Codex on 2025/02/07.
//

import Foundation

/// Product identifiers for premium subscriptions.
public enum SubscriptionProduct: String, CaseIterable, Sendable {
    case monthly = "com.zanderwang.AITranslator.premium.monthly"
    case annual = "com.zanderwang.AITranslator.premium.annual"

    /// All product identifiers as a set for StoreKit queries.
    public static var allIdentifiers: Set<String> {
        Set(allCases.map(\.rawValue))
    }
}
