//
//  StoreManager.swift
//  ShareCore
//
//  Created by Codex on 2025/02/07.
//

import Combine
import Foundation
import os
import StoreKit

private let logger = os.Logger(subsystem: "com.zanderwang.AITranslator", category: "StoreManager")

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

    /// `true` when running via TestFlight (sandbox receipt in a non-DEBUG, non-App-Store build).
    public static var isTestFlight: Bool {
        #if DEBUG
            return false
        #else
            guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
            // iOS TestFlight uses "sandboxReceipt" as the receipt filename.
            // macOS TestFlight receipt lives under a path containing "sandboxReceipt".
            return receiptURL.path.contains("sandboxReceipt")
        #endif
    }

    /// Whether TestFlight premium override is currently active.
    @Published public private(set) var isTestFlightOverride: Bool = false

    private static let testFlightOverrideKey = "testflight_premium_override"

    // MARK: - Init

    private init() {
        #if DEBUG
            // Auto-enable premium in development builds
            isPremium = true
            AppPreferences.sharedDefaults.set(true, forKey: Self.premiumKey)
            logger.debug("DEBUG build – premium auto-enabled")
        #else
            // Read cached premium status from App Group defaults
            isPremium = AppPreferences.sharedDefaults.bool(forKey: Self.premiumKey)

            // Restore TestFlight override if previously enabled
            if Self.isTestFlight {
                isTestFlightOverride = AppPreferences.sharedDefaults.bool(forKey: Self.testFlightOverrideKey)
                if isTestFlightOverride {
                    isPremium = true
                    logger.debug("TestFlight override restored – premium enabled")
                }
            } else {
                // Clean up any stale TF override from a previous TestFlight install
                AppPreferences.sharedDefaults.removeObject(forKey: Self.testFlightOverrideKey)
            }

            // Start listening for transaction updates
            transactionListener = listenForTransactions()

            // Check current entitlements on launch
            Task {
                await checkSubscriptionStatus()
                await loadProducts()
            }
        #endif
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

        } catch {
            logger.error("Failed to load products: \(error, privacy: .public)")
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
                // Directly grant premium for verified subscription purchases,
                // as Transaction.currentEntitlements may lag behind.
                if SubscriptionProduct.allIdentifiers.contains(transaction.productID) {
                    updatePremiumStatus(true)
                }
                await checkSubscriptionStatus()
                logger.info("Purchase successful: \(product.id, privacy: .public)")

            case .userCancelled:
                logger.debug("Purchase cancelled by user")

            case .pending:
                logger.debug("Purchase pending")

            @unknown default:
                logger.debug("Unknown purchase result")
            }
        } catch {
            purchaseError = error.localizedDescription
            logger.error("Purchase failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Restore Purchases

    public func restorePurchases() async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await checkSubscriptionStatus()
            logger.info("Restore completed")
        } catch {
            purchaseError = error.localizedDescription
            logger.error("Restore failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Check Subscription Status

    public func checkSubscriptionStatus() async {
        // TestFlight override takes precedence
        if isTestFlightOverride {
            updatePremiumStatus(true)
            return
        }

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

    // MARK: - TestFlight Premium Toggle

    /// Toggle TestFlight premium override. Returns the new override state.
    @discardableResult
    public func toggleTestFlightPremium() -> Bool {
        guard Self.isTestFlight else { return false }
        let newValue = !isTestFlightOverride
        isTestFlightOverride = newValue
        AppPreferences.sharedDefaults.set(newValue, forKey: Self.testFlightOverrideKey)

        if newValue {
            updatePremiumStatus(true)
        } else {
            // Immediately clear premium, then let async check correct upward if real subscription exists
            updatePremiumStatus(false)
            Task {
                await checkSubscriptionStatus()
            }
        }

        logger.debug("TestFlight override toggled: \(newValue, privacy: .public)")
        return newValue
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
        logger.info("Premium status updated: \(newValue, privacy: .public)")
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
