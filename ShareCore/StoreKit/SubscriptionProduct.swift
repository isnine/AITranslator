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
    public static let allIdentifiers: Set<String> =
        Set(allCases.map(\.rawValue))
}

/// Product identifiers for one-time purchases.
public enum LifetimeProduct: String, Sendable {
    case lifetime = "com.zanderwang.AITranslator.lifetime"
}

/// All premium product identifiers (subscriptions + lifetime).
public enum PremiumProduct {
    public static let allIdentifiers: Set<String> =
        SubscriptionProduct.allIdentifiers.union([LifetimeProduct.lifetime.rawValue])
}
