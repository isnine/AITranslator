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

    /// `true` when running via TestFlight.
    ///
    /// Detection strategy:
    /// - iOS/iPadOS: App Store receipt path contains `sandboxReceipt`.
    /// - macOS: the receipt filename is identical to Mac App Store builds, so we additionally
    ///   check for `/TestFlight/` in the bundle path and fall back to the authoritative
    ///   `AppTransaction` environment probe, whose result is cached after launch.
    public static var isTestFlight: Bool {
        #if DEBUG
            return false
        #else
            if let receiptURL = Bundle.main.appStoreReceiptURL,
               receiptURL.path.contains("sandboxReceipt") {
                return true
            }
            #if os(macOS)
                if Bundle.main.bundlePath.contains("/TestFlight/") { return true }
            #endif
            return isTestFlightEnvironmentCached
        #endif
    }

    // Cached because `isTestFlight` must stay synchronous, but the authoritative probe
    // (`AppTransaction`) is async. Written once from the @MainActor init task; the Bool
    // write is atomic on our target architectures.
    nonisolated(unsafe) private static var isTestFlightEnvironmentCached: Bool = false

    /// Whether TestFlight premium override is currently active.
    @Published public private(set) var isTestFlightOverride: Bool = false

    private static let testFlightOverrideKey = "testflight_premium_override"

    // MARK: - Init

    private init() {
        #if DEBUG
            // Auto-enable premium in development builds unless user toggled it off
            isTestFlightOverride = AppPreferences.sharedDefaults.bool(forKey: Self.testFlightOverrideKey)
            if isTestFlightOverride {
                isPremium = false
                logger.debug("DEBUG build – premium disabled via override toggle")
            } else {
                isPremium = true
                AppPreferences.sharedDefaults.set(true, forKey: Self.premiumKey)
                logger.debug("DEBUG build – premium auto-enabled")
            }

            transactionListener = listenForTransactions()
            Task {
                await loadProducts()
            }
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
                await resolveTestFlightEnvironment()
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
                for: PremiumProduct.allIdentifiers
            )

            logger.info("Loaded \(storeProducts.count) products: \(storeProducts.map(\.id).joined(separator: ", "), privacy: .public)")

            // Sort: monthly first, then annual, then lifetime
            products = storeProducts.sorted { lhs, rhs in
                let order: (Product) -> Int = { p in
                    switch p.id {
                    case SubscriptionProduct.monthly.rawValue: return 0
                    case SubscriptionProduct.annual.rawValue: return 1
                    case LifetimeProduct.lifetime.rawValue: return 2
                    default: return 3
                    }
                }
                return order(lhs) < order(rhs)
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
                if PremiumProduct.allIdentifiers.contains(transaction.productID) {
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

            if PremiumProduct.allIdentifiers.contains(transaction.productID) {
                if transaction.revocationDate == nil {
                    hasActiveSubscription = true
                }
            }
        }

        updatePremiumStatus(hasActiveSubscription)
    }

    // MARK: - TestFlight Environment Probe

    /// Authoritative TestFlight detection via `AppTransaction` (covers macOS, where the
    /// receipt filename heuristic can't distinguish TestFlight from Mac App Store).
    /// Also restores a previously saved TestFlight override that the synchronous
    /// `isTestFlight` check may have missed before this probe completed.
    private func resolveTestFlightEnvironment() async {
        do {
            let verification = try await AppTransaction.shared
            let transaction = try checkVerified(verification)
            let isSandbox = transaction.environment == .sandbox
            Self.isTestFlightEnvironmentCached = isSandbox
            logger.info("AppTransaction environment: \(String(describing: transaction.environment), privacy: .public)")

            if isSandbox {
                let storedOverride = AppPreferences.sharedDefaults.bool(forKey: Self.testFlightOverrideKey)
                if storedOverride, !isTestFlightOverride {
                    isTestFlightOverride = true
                    updatePremiumStatus(true)
                }
            }
        } catch {
            logger.error("AppTransaction probe failed: \(error, privacy: .public)")
        }
    }

    // MARK: - TestFlight Premium Toggle

    @discardableResult
    public func toggleTestFlightPremium() -> Bool {
        #if DEBUG
            let newValue = !isTestFlightOverride
            isTestFlightOverride = newValue
            AppPreferences.sharedDefaults.set(newValue, forKey: Self.testFlightOverrideKey)
            updatePremiumStatus(!newValue)
            return !newValue
        #else
            guard Self.isTestFlight else { return false }
            let newValue = !isTestFlightOverride
            isTestFlightOverride = newValue
            AppPreferences.sharedDefaults.set(newValue, forKey: Self.testFlightOverrideKey)
            updatePremiumStatus(newValue)
            if !newValue {
                Task { await checkSubscriptionStatus() }
            }
            return newValue
        #endif
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

    /// Lifetime product, if available.
    public var lifetimeProduct: Product? {
        products.first { $0.id == LifetimeProduct.lifetime.rawValue }
    }

    /// Subscription-only products (excludes lifetime).
    public var subscriptionProducts: [Product] {
        products.filter { SubscriptionProduct.allIdentifiers.contains($0.id) }
    }
}
