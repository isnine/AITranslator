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

    private var hasUpgradeOptions: Bool {
        currentTierPriority < 2
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroSection
                    if hasUpgradeOptions {
                        featuresSection
                        productsSection
                        subscribeButton
                        legalFooter
                    } else {
                        featuresSection
                        currentPlanBadge
                    }
                }
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
        .onChange(of: storeManager.activePremiumProductID) { _, newID in
            if newID != nil {
                Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    dismiss()
                }
            }
        }
    }

    // MARK: - Products

    @State private var selectedProduct: Product?

    private var currentTierPriority: Int {
        guard let productID = storeManager.activePremiumProductID else { return -1 }
        return PremiumProduct.tierPriority(for: productID)
    }

    private func isUpgrade(_ product: Product) -> Bool {
        PremiumProduct.tierPriority(for: product.id) > currentTierPriority
    }

    private var productsSection: some View {
        VStack(spacing: 0) {
            let lifetime = storeManager.lifetimeProduct.flatMap { isUpgrade($0) ? $0 : nil }
            let annual = storeManager.annualProduct.flatMap { isUpgrade($0) ? $0 : nil }
            let monthly = storeManager.monthlyProduct.flatMap { isUpgrade($0) ? $0 : nil }

            if let lifetime {
                productRow(
                    product: lifetime,
                    title: "Lifetime",
                    subtitle: "One-time purchase, forever yours",
                    priceLabel: lifetime.displayPrice,
                    periodLabel: nil,
                    badge: "BEST VALUE"
                )
            }

            if lifetime != nil, annual != nil { sectionDivider }

            if let annual {
                productRow(
                    product: annual,
                    title: "Annual",
                    subtitle: monthlySavingsText(annual: annual),
                    priceLabel: annual.displayPrice,
                    periodLabel: "/ year",
                    badge: nil
                )
            }

            if (lifetime != nil || annual != nil), monthly != nil { sectionDivider }

            if let monthly {
                productRow(
                    product: monthly,
                    title: "Monthly",
                    subtitle: "Cancel anytime",
                    priceLabel: monthly.displayPrice,
                    periodLabel: "/ month",
                    badge: nil
                )
            }
        }
        .background(cardBackground)
        .padding(.horizontal, 20)
        .onAppear {
            let upgradeable = [storeManager.lifetimeProduct, storeManager.annualProduct, storeManager.monthlyProduct]
                .compactMap { $0 }
                .filter { isUpgrade($0) }
            selectedProduct = upgradeable.first
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(colors.divider)
            .frame(height: 0.5)
            .padding(.leading, 56)
    }

    private func monthlySavingsText(annual: Product) -> String {
        let perMonth = (annual.price / 12).formatted(annual.priceFormatStyle)
        return "\(perMonth)/mo — save vs. monthly"
    }

    private func productRow(
        product: Product,
        title: String,
        subtitle: String,
        priceLabel: String,
        periodLabel: String?,
        badge: String?
    ) -> some View {
        let isSelected = selectedProduct?.id == product.id

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedProduct = product
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? colors.accent : colors.divider, lineWidth: isSelected ? 6 : 1.5)
                        .frame(width: 22, height: 22)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colors.textPrimary)

                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(
                                        LinearGradient(
                                            colors: [Color.orange, Color.yellow],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                )
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text(priceLabel)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(colors.textPrimary)
                    if let periodLabel {
                        Text(periodLabel)
                            .font(.system(size: 11))
                            .foregroundColor(colors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        Button {
            guard let product = selectedProduct else { return }
            Task { await storeManager.purchase(product) }
        } label: {
            Group {
                if storeManager.isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colors.accent)
            )
        }
        .disabled(selectedProduct == nil || storeManager.isPurchasing)
        .padding(.horizontal, 20)
    }

    // MARK: - Current Plan Badge (Lifetime)

    private var currentPlanBadge: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)

            Text("You have the best plan")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(colors.textPrimary)

            if let productID = storeManager.activePremiumProductID,
               let tier = PremiumProduct.tierDisplayName(for: productID)
            {
                Text("Current plan: \(tier)")
                    .font(.system(size: 15))
                    .foregroundColor(colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(cardBackground)
        .padding(.horizontal, 20)
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

            Text(hasUpgradeOptions
                ? (storeManager.isPremium ? "Upgrade Your Plan" : "Upgrade to Premium")
                : "Premium Active")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(colors.textPrimary)

            Text(hasUpgradeOptions
                ? (storeManager.isPremium
                    ? "Switch to a higher tier for even more value"
                    : "Unlock the most powerful translation models")
                : "Thank you for your support!")
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
                description: "GPT-5.4, GPT-5, GPT-4.1, o3-mini, o4-mini"
            )
            featureRow(
                icon: "bolt.fill",
                title: "Higher Quality",
                description: "More accurate and nuanced translations"
            )
            featureRow(
                icon: "text.badge.checkmark",
                title: "Unlimited Models",
                description: "Select as many models as you need"
            )
            featureRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Always Up-to-Date",
                description: "Access to the latest models as they launch"
            )
            featureRow(
                icon: "macbook.and.iphone",
                title: "Works on iPhone & Mac",
                description: "One subscription, all your Apple devices"
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

    // MARK: - Legal

    private static let privacyPolicyURL = URL(
        string: "https://www.notion.so/isnine/Privacy-Policy-6ab3eecbf72f4e14b6ed8df977a84b43"
    )!
    private static let termsOfUseURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!

    private var legalFooter: some View {
        VStack(spacing: 12) {
            Button("Restore Purchases") {
                Task { await storeManager.restorePurchases() }
            }
            .font(.system(size: 13))
            .foregroundColor(colors.accent)

            HStack(spacing: 16) {
                Link("Terms of Use", destination: Self.termsOfUseURL)
                Link("Privacy Policy", destination: Self.privacyPolicyURL)
            }
            .font(.system(size: 11))
            .foregroundColor(colors.textSecondary.opacity(0.6))

            Text(
                "Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period."
            )
            .font(.system(size: 11))
            .foregroundColor(colors.textSecondary.opacity(0.6))
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
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
