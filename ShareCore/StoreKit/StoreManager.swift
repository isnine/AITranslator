//
//  StoreManager.swift
//  ShareCore
//
//  Created by Codex on 2025/02/07.
//

import Combine
import Foundation
import StoreKit

/// Manages StoreKit 2 subscription state and purchasing.
@MainActor
public final class StoreManager: ObservableObject {
    public static let shared = StoreManager()

    // MARK: - Published State

    @Published public private(set) var isPremium: Bool = false
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var purchaseError: String?
    @Published public private(set) var isLoadingProducts: Bool = false
    @Published public private(set) var isPurchasing: Bool = false

    // MARK: - Private

    private var transactionListener: Task<Void, Never>?
    private static let premiumKey = "is_premium_subscriber"

    // MARK: - Init

    private init() {
        // Read cached premium status from App Group defaults
        isPremium = AppPreferences.sharedDefaults.bool(forKey: Self.premiumKey)

        // Start listening for transaction updates
        transactionListener = listenForTransactions()

        // Check current entitlements on launch
        Task {
            await checkSubscriptionStatus()
            await loadProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    public func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let storeProducts = try await Product.products(
                for: SubscriptionProduct.allIdentifiers
            )

            // Sort: monthly first, then annual
            products = storeProducts.sorted { lhs, rhs in
                let lhsIsMonthly = lhs.id == SubscriptionProduct.monthly.rawValue
                let rhsIsMonthly = rhs.id == SubscriptionProduct.monthly.rawValue
                if lhsIsMonthly != rhsIsMonthly { return lhsIsMonthly }
                return lhs.price < rhs.price
            }

            Logger.debug("[StoreManager] Loaded \(products.count) products")
        } catch {
            Logger.debug("[StoreManager] Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase

    public func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()

            switch result {
            case let .success(verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await checkSubscriptionStatus()
                Logger.debug("[StoreManager] Purchase successful: \(product.id)")

            case .userCancelled:
                Logger.debug("[StoreManager] Purchase cancelled by user")

            case .pending:
                Logger.debug("[StoreManager] Purchase pending")

            @unknown default:
                Logger.debug("[StoreManager] Unknown purchase result")
            }
        } catch {
            purchaseError = error.localizedDescription
            Logger.debug("[StoreManager] Purchase failed: \(error)")
        }
    }

    // MARK: - Restore Purchases

    public func restorePurchases() async {
        do {
            try await AppStore.sync()
            await checkSubscriptionStatus()
            Logger.debug("[StoreManager] Restore completed")
        } catch {
            purchaseError = error.localizedDescription
            Logger.debug("[StoreManager] Restore failed: \(error)")
        }
    }

    // MARK: - Check Subscription Status

    public func checkSubscriptionStatus() async {
        var hasActiveSubscription = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }

            if SubscriptionProduct.allIdentifiers.contains(transaction.productID) {
                if transaction.revocationDate == nil {
                    hasActiveSubscription = true
                }
            }
        }

        updatePremiumStatus(hasActiveSubscription)
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? await self.checkVerified(result) {
                    await transaction.finish()
                    await self.checkSubscriptionStatus()
                }
            }
        }
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .unverified(_, error):
            throw error
        case let .verified(safe):
            return safe
        }
    }

    private func updatePremiumStatus(_ newValue: Bool) {
        guard isPremium != newValue else { return }
        isPremium = newValue
        AppPreferences.sharedDefaults.set(newValue, forKey: Self.premiumKey)
        AppPreferences.sharedDefaults.synchronize()
        Logger.debug("[StoreManager] Premium status updated: \(newValue)")
    }

    // MARK: - Convenience

    /// Monthly product, if available.
    public var monthlyProduct: Product? {
        products.first { $0.id == SubscriptionProduct.monthly.rawValue }
    }

    /// Annual product, if available.
    public var annualProduct: Product? {
        products.first { $0.id == SubscriptionProduct.annual.rawValue }
    }
}
