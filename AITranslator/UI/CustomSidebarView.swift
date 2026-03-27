//
//  CustomSidebarView.swift
//  TLingo
//
//  Created by Codex on 2026/03/27.
//

import ShareCore
import SwiftUI

struct CustomSidebarView: View {
    @Binding var selection: RootTabView.TabItem
    let colors: AppColorPalette
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Header

            VStack(alignment: .leading, spacing: 2) {
                Text("TLingo")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(colors.textPrimary)
                Text("Your AI translator")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)

            // MARK: - Nav Items

            VStack(spacing: 2) {
                ForEach(RootTabView.TabItem.allCases) { item in
                    sidebarNavItem(item)
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            // MARK: - Premium Button

            premiumButton
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: 200)
        .background(colors.background)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Nav Item

    private func sidebarNavItem(_ item: RootTabView.TabItem) -> some View {
        let isSelected = selection == item
        return Button {
            selection = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(item.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(isSelected ? .white : colors.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? colors.accent : .clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar_\(item.rawValue)")
    }

    // MARK: - Premium Button

    @ViewBuilder
    private var premiumButton: some View {
        if storeManager.isPremium {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14))
                Text("Premium")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("Active")
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
            }
            .foregroundStyle(colors.accent)
            .padding(.horizontal, 10)
            .frame(height: 36)
        } else {
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14))
                    Text("Upgrade")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(colors.accent)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colors.accent.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
    }
}
