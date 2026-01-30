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

    @State private var models: [ModelConfig] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var enabledModelIDs: Set<String> = []

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    headerSection
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
                loadModels()
            }
            .onChange(of: preferences.enabledModelIDs) { _, newValue in
                enabledModelIDs = newValue
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                Text("AVAILABLE MODELS")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.leading, 4)

            if let error = errorMessage {
                errorView(error)
            } else if models.isEmpty && !isLoading {
                emptyState
            } else {
                modelsListCard
            }

            infoFooter
        }
    }

    private var modelsListCard: some View {
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

    private func modelRow(model: ModelConfig) -> some View {
        let isEnabled = enabledModelIDs.contains(model.id)

        return Button {
            toggleModel(model)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isEnabled ? colors.accent : colors.textSecondary.opacity(0.4))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colors.textPrimary)

                        if model.isDefault {
                            Text("Default")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(colors.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colors.accent.opacity(0.15))
                                .clipShape(Capsule())
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

    private var infoFooter: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20))
                .foregroundColor(colors.success)
            Text("Powered by Built-in Cloud - No API key required")
                .font(.system(size: 13))
                .foregroundColor(colors.textSecondary)
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

    private func toggleModel(_ model: ModelConfig) {
        var newSet = enabledModelIDs
        if newSet.contains(model.id) {
            newSet.remove(model.id)
        } else {
            newSet.insert(model.id)
        }
        enabledModelIDs = newSet
        preferences.setEnabledModelIDs(newSet)
    }

    private func loadModels() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetchedModels = try await ModelsService.shared.fetchModels()
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
