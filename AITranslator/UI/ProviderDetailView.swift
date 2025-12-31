//
//  ProviderDetailView.swift
//  AITranslator
//
//  Created by AI Assistant on 2025/12/31.
//

import SwiftUI
import ShareCore

struct ProviderDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var configurationStore: AppConfigurationStore

    private let providerID: UUID
    private let isNewProvider: Bool
    @State private var displayName: String
    @State private var apiURL: String
    @State private var token: String
    @State private var authHeaderName: String
    @State private var category: ProviderCategory
    @State private var modelName: String
    @State private var showDeleteConfirmation = false

    init(
        provider: ProviderConfig?,
        configurationStore: AppConfigurationStore
    ) {
        self._configurationStore = ObservedObject(wrappedValue: configurationStore)
        
        if let provider = provider {
            self.providerID = provider.id
            self.isNewProvider = false
            _displayName = State(initialValue: provider.displayName)
            _apiURL = State(initialValue: provider.apiURL.absoluteString)
            _token = State(initialValue: provider.token)
            _authHeaderName = State(initialValue: provider.authHeaderName)
            _category = State(initialValue: provider.category)
            _modelName = State(initialValue: provider.modelName)
        } else {
            self.providerID = UUID()
            self.isNewProvider = true
            _displayName = State(initialValue: "")
            _apiURL = State(initialValue: "https://")
            _token = State(initialValue: "")
            _authHeaderName = State(initialValue: "api-key")
            _category = State(initialValue: .custom)
            _modelName = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    basicInfoSection
                    connectionSection
                    categorySection
                    
                    if !isNewProvider {
                        deleteSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .background(colors.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .alert("Delete Provider", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteProvider()
            }
        } message: {
            Text("Are you sure you want to delete \"\(displayName)\"? This action cannot be undone.")
        }
    }

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    private var headerBar: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(colors.textPrimary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: saveProvider) {
                Text("Save")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(canSave ? colors.accent : colors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(colors.background.opacity(0.98))
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        URL(string: apiURL) != nil
    }

    private var basicInfoSection: some View {
        section(title: "Basic Info") {
            labeledField(title: "Display Name", text: $displayName, placeholder: "e.g., Azure OpenAI")
            labeledField(title: "Model Name", text: $modelName, placeholder: "e.g., gpt-4o")
        }
    }

    private var connectionSection: some View {
        section(title: "Connection") {
            labeledField(title: "API Endpoint", text: $apiURL, placeholder: "https://api.openai.com/v1/chat/completions")
            labeledField(title: "Auth Header Name", text: $authHeaderName, placeholder: "api-key")
            
            VStack(alignment: .leading, spacing: 8) {
                Text("API Token")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.textSecondary)

                SecureField("Enter your API key", text: $token)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundColor(colors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(colors.inputBackground)
                    )
            }
        }
    }

    private var categorySection: some View {
        section(title: "Provider Category") {
            VStack(spacing: 12) {
                ForEach(ProviderCategory.allCases, id: \.self) { cat in
                    categoryRow(cat)
                }
            }
        }
    }

    private func categoryRow(_ cat: ProviderCategory) -> some View {
        let isSelected = category == cat
        return Button {
            category = cat
            if modelName.isEmpty {
                modelName = cat.defaultModelHint
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cat.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text(cat.defaultModelHint)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? colors.accent : colors.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? colors.accent : colors.cardBackground, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var deleteSection: some View {
        section(title: "Danger Zone") {
            Button {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                    Text("Delete Provider")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.red.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func section(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(colors.textPrimary)

            content()
        }
    }

    private func labeledField(title: LocalizedStringKey, text: Binding<String>, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.textSecondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(colors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(colors.inputBackground)
                )
        }
    }

    private func saveProvider() {
        guard let url = URL(string: apiURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }

        let updated = ProviderConfig(
            id: providerID,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            apiURL: url,
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            authHeaderName: authHeaderName.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
                ? category.defaultModelHint 
                : modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        var providers = configurationStore.providers

        if let index = providers.firstIndex(where: { $0.id == providerID }) {
            providers[index] = updated
        } else {
            providers.append(updated)
        }

        configurationStore.updateProviders(providers)
        dismiss()
    }

    private func deleteProvider() {
        var providers = configurationStore.providers
        providers.removeAll { $0.id == providerID }
        configurationStore.updateProviders(providers)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ProviderDetailView(
            provider: AppConfigurationStore.shared.providers.first,
            configurationStore: AppConfigurationStore.shared
        )
        .preferredColorScheme(.dark)
    }
}
