//
//  ModelsView.swift
//  TLingo
//
//  Created by Codex on 2025/01/28.
//

import ShareCore
import SwiftUI

struct ModelsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var storeManager = StoreManager.shared

    @State private var models: [ModelConfig] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var enabledModelIDs: Set<String> = []
    @State private var showPaywall = false
    @State private var showLimitBanner = false

    private let freeModelLimit = 2

    private var hasReachedFreeLimit: Bool {
        guard !storeManager.isPremium else { return false }
        let freeModelIDs = Set(models.filter { !$0.isPremium }.map(\.id))
        let activeFreeCount = enabledModelIDs.intersection(freeModelIDs).count
        print("[ModelsView] enabledModelIDs=\(enabledModelIDs), freeModelIDs=\(freeModelIDs), activeFreeCount=\(activeFreeCount), isPremium=\(storeManager.isPremium)")
        return activeFreeCount >= freeModelLimit
    }

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    private var freeModels: [ModelConfig] {
        models.filter { !$0.isPremium }
    }

    private var premiumModels: [ModelConfig] {
        models.filter { $0.isPremium }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    headerSection
                    if showLimitBanner {
                        freeModelLimitBanner
                    }
                    modelsSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
            .background(colors.background.ignoresSafeArea())
        }
        .tint(colors.accent)
        #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
        #endif
            .onAppear {
                enabledModelIDs = preferences.enabledModelIDs
                print("[ModelsView] onAppear enabledModelIDs=\(enabledModelIDs)")
                loadModels()
            }
            .onChange(of: preferences.enabledModelIDs) { _, newValue in
                enabledModelIDs = newValue
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Models")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(colors.textPrimary)
            Text("Select models to use for translation")
                .font(.system(size: 16))
                .foregroundColor(colors.textSecondary)
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Loading indicator
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.7)
                    Spacer()
                }
            }

            if let error = errorMessage {
                errorView(error)
            } else if models.isEmpty && !isLoading {
                emptyState
            } else {
                // Free models section
                if !freeModels.isEmpty {
                    modelGroupSection(
                        title: "FREE MODELS",
                        icon: "cpu",
                        models: freeModels,
                        isPremiumSection: false
                    )
                }

                // Premium models section
                if !premiumModels.isEmpty {
                    modelGroupSection(
                        title: "PREMIUM MODELS",
                        icon: "crown.fill",
                        models: premiumModels,
                        isPremiumSection: true
                    )
                }
            }

            infoFooter
        }
    }

    private func modelGroupSection(
        title: String,
        icon: String,
        models: [ModelConfig],
        isPremiumSection: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isPremiumSection ? .orange : colors.textSecondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isPremiumSection ? .orange : colors.textSecondary)

                if isPremiumSection && !storeManager.isPremium {
                    Spacer()
                    Button {
                        showPaywall = true
                    } label: {
                        Text("Upgrade")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                LinearGradient(
                                    colors: [.orange, .yellow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    modelRow(model: model)

                    if index < models.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .background(cardBackground)
        }
    }

    private func modelRow(model: ModelConfig) -> some View {
        let isEnabled = enabledModelIDs.contains(model.id)
        let isLocked = model.isPremium && !storeManager.isPremium
        let isDisabledByLimit = hasReachedFreeLimit && !isEnabled && !isLocked

        return Button {
            if isLocked {
                showPaywall = true
            } else {
                toggleModel(model)
            }
        } label: {
            HStack(spacing: 12) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18))
                        .foregroundColor(colors.textSecondary.opacity(0.4))
                        .frame(width: 22)
                } else {
                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(isEnabled ? colors.accent : colors.textSecondary.opacity(0.4))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isLocked || isDisabledByLimit ? colors.textSecondary : colors.textPrimary)

                        if model.isDefault {
                            Text("Default")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(colors.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colors.accent.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        if model.isPremium {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }

                    Text(model.id)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .opacity(isDisabledByLimit ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 32))
                .foregroundColor(colors.textSecondary.opacity(0.5))
            Text("No models available")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(cardBackground)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(colors.error)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                loadModels()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(cardBackground)
    }

    private static let privacyPolicyURL = URL(
        string: "https://isnine.notion.site/Privacy-Policy-TLing-304096d1267280fcbea4edac5f95ccda"
    )!

    private var infoFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundColor(colors.success)
                Text("Powered by Built-in Cloud - No API key required")
                    .font(.system(size: 13))
                    .foregroundColor(colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14))
                        .foregroundColor(colors.textSecondary.opacity(0.6))
                    Text("Your translation text is sent to Microsoft Azure OpenAI Service for processing. Data is encrypted in transit and not stored after processing.")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary.opacity(0.8))
                }

                Link(destination: Self.privacyPolicyURL) {
                    HStack(spacing: 4) {
                        Text("Privacy Policy")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 12))
                }
                .padding(.leading, 22)
            }
        }
        .padding(.top, 8)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(colors.divider, lineWidth: 1)
            )
    }

    private var freeModelLimitBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.orange)

            Text("Free users can select up to \(freeModelLimit) models")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.textPrimary)

            Spacer()

            Button {
                withAnimation(.spring(duration: 0.3)) {
                    showLimitBanner = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.spring(duration: 0.3)) {
                    showLimitBanner = false
                }
            }
        }
    }

    private func toggleModel(_ model: ModelConfig) {
        var newSet = enabledModelIDs
        if newSet.contains(model.id) {
            newSet.remove(model.id)
        } else {
            if hasReachedFreeLimit {
                withAnimation(.spring(duration: 0.3)) {
                    showLimitBanner = true
                }
                return
            }
            newSet.insert(model.id)
        }
        enabledModelIDs = newSet
        preferences.setEnabledModelIDs(newSet)
    }

    private func loadModels() {
        errorMessage = nil

        // Show cached models immediately (if any), then refresh in the background.
        if let cached = ModelsService.shared.getCachedModels(), !cached.isEmpty {
            models = cached
            isLoading = true
        } else {
            isLoading = true
        }

        Task {
            do {
                let fetchedModels = try await ModelsService.shared.fetchModels(forceRefresh: true)
                await MainActor.run {
                    models = fetchedModels
                    isLoading = false

                    if enabledModelIDs.isEmpty {
                        let defaultModels = fetchedModels.filter { $0.isDefault }
                        enabledModelIDs = Set(defaultModels.map { $0.id })
                        preferences.setEnabledModelIDs(enabledModelIDs)
                    }
                }
            } catch {
                await MainActor.run {
                    // Keep showing cached models (if any) and surface the error.
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    ModelsView()
        .preferredColorScheme(.dark)
}
