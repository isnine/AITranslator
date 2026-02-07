//
//  PaywallView.swift
//  TLingo
//
//  Created by Codex on 2025/02/07.
//

import ShareCore
import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var storeManager = StoreManager.shared

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroSection
                    featuresSection
                    productsSection
                    restoreButton
                    legalFooter
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
            .background(colors.background.ignoresSafeArea())
            .navigationTitle("")
            #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(colors.textSecondary.opacity(0.6))
                        }
                    }
                }
        }
        .tint(colors.accent)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.yellow, Color.orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Upgrade to Premium")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(colors.textPrimary)

            Text("Unlock the most powerful translation models")
                .font(.system(size: 16))
                .foregroundColor(colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            featureRow(
                icon: "sparkles",
                title: "Premium Models",
                description: "GPT-4o, GPT-4.1, GPT-4.5, GPT-5, o3-mini, o4-mini"
            )
            featureRow(
                icon: "bolt.fill",
                title: "Higher Quality",
                description: "More accurate and nuanced translations"
            )
            featureRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Always Up-to-Date",
                description: "Access to the latest models as they launch"
            )
        }
        .padding(20)
        .background(cardBackground)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(colors.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)
            }
        }
    }

    // MARK: - Products

    private var productsSection: some View {
        VStack(spacing: 12) {
            if storeManager.isLoadingProducts {
                ProgressView()
                    .padding(.vertical, 20)
            } else if storeManager.products.isEmpty {
                Text("Products unavailable. Please try again later.")
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(storeManager.products, id: \.id) { product in
                    productCard(product)
                }
            }

            if let error = storeManager.purchaseError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(colors.error)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    private func productCard(_ product: Product) -> some View {
        let isAnnual = product.id == SubscriptionProduct.annual.rawValue

        return Button {
            Task {
                await storeManager.purchase(product)
                if storeManager.isPremium {
                    dismiss()
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colors.textPrimary)

                        if isAnnual, let savingsText = annualSavingsText {
                            Text(savingsText)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green)
                                .clipShape(Capsule())
                        }
                    }

                    Text(product.description)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colors.accent)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isAnnual ? colors.accent : colors.divider,
                                lineWidth: isAnnual ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(storeManager.isPurchasing)
        .opacity(storeManager.isPurchasing ? 0.6 : 1.0)
    }

    // MARK: - Savings Calculation

    private var annualSavingsText: String? {
        guard let monthly = storeManager.monthlyProduct,
              let annual = storeManager.annualProduct else {
            return nil
        }
        let annualized = monthly.price * 12
        guard annualized > annual.price else { return nil }
        let savings = (annualized - annual.price) / annualized * 100
        let percent = Int(NSDecimalNumber(decimal: savings).doubleValue)
        guard percent > 0 else { return nil }
        return "Save \(percent)%"
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task {
                await storeManager.restorePurchases()
                if storeManager.isPremium {
                    dismiss()
                }
            }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(colors.accent)
        }
    }

    // MARK: - Legal

    private var legalFooter: some View {
        VStack(spacing: 4) {
            Text("Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period.")
                .font(.system(size: 11))
                .foregroundColor(colors.textSecondary.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Shared

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(colors.divider, lineWidth: 1)
            )
    }
}

#Preview {
    PaywallView()
        .preferredColorScheme(.dark)
}
