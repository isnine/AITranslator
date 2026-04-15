//
//  ModelsView.swift
//  TLingo
//
//  Created by Codex on 2025/01/28.
//

import ShareCore
import SwiftUI
#if canImport(Translation)
    import Translation
#endif

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
    @State private var showHiddenFreeModels = false
    @State private var showHiddenPremiumModels = false
    @State private var showInstalledLanguages = false
    @State private var showDownloadLanguagesGuide = false

    private let freeModelLimit = 2

    private var hasReachedFreeLimit: Bool {
        guard !storeManager.isPremium else { return false }
        let freeModelIDs = Set(models.filter { !$0.isPremium }.map(\.id))
        // Apple Translate doesn't count toward the free cloud model limit.
        let activeFreeCount = enabledModelIDs.intersection(freeModelIDs)
            .subtracting([ModelConfig.appleTranslateID]).count
        #if DEBUG
        print("[ModelsView] enabledModelIDs=\(enabledModelIDs), freeModelIDs=\(freeModelIDs), activeFreeCount=\(activeFreeCount), isPremium=\(storeManager.isPremium)")
        #endif
        return activeFreeCount >= freeModelLimit
    }

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    private var freeModels: [ModelConfig] {
        models.filter { !$0.isPremium && !$0.hidden }
    }

    private var hiddenFreeModels: [ModelConfig] {
        models.filter { !$0.isPremium && $0.hidden }
    }

    private var premiumModels: [ModelConfig] {
        models.filter { $0.isPremium && !$0.hidden }
    }

    private var hiddenPremiumModels: [ModelConfig] {
        models.filter { $0.isPremium && $0.hidden }
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
                #if DEBUG
                print("[ModelsView] onAppear enabledModelIDs=\(enabledModelIDs)")
                #endif
                loadModels()
                // Refresh installed languages if Apple Translate is enabled.
                if enabledModelIDs.contains(ModelConfig.appleTranslateID) {
                    refreshInstalledLanguagesInBackground()
                }
            }
            .onChange(of: preferences.enabledModelIDs) { _, newValue in
                enabledModelIDs = newValue
                #if DEBUG
                print("[ModelsView] onChange(preferences.enabledModelIDs) → \(newValue)")
                #endif
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showDownloadLanguagesGuide) {
                DownloadLanguagesGuideView()
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

            // On-device models render independently of cloud config state
            if AppleTranslationService.shared.isAvailable {
                onDeviceModelSection
            }

            if let error = errorMessage {
                errorView(error)
            } else if models.isEmpty && !isLoading {
                emptyState
            } else {
                // Free models section
                if !freeModels.isEmpty || !hiddenFreeModels.isEmpty {
                    modelGroupSection(
                        title: "FREE MODELS",
                        icon: "cpu",
                        models: freeModels,
                        hiddenModels: hiddenFreeModels,
                        isExpanded: $showHiddenFreeModels,
                        isPremiumSection: false
                    )
                }

                // Premium models section
                if !premiumModels.isEmpty || !hiddenPremiumModels.isEmpty {
                    modelGroupSection(
                        title: "PREMIUM MODELS",
                        icon: "crown.fill",
                        models: premiumModels,
                        hiddenModels: hiddenPremiumModels,
                        isExpanded: $showHiddenPremiumModels,
                        isPremiumSection: true
                    )
                }
            }

            infoFooter
        }
    }

    // MARK: - On-Device Models

    private var onDeviceModelSection: some View {
        let model = ModelConfig.appleTranslate
        let isEnabled = enabledModelIDs.contains(model.id)
        let installedLangs = installedLanguageOptions

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                Text("ON-DEVICE")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                Button {
                    #if DEBUG
                    print("[ModelsView] AppleTranslate TAPPED: isEnabled=\(isEnabled)")
                    #endif
                    toggleAppleTranslate()
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

                                Text("On-Device")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15))
                                    .clipShape(Capsule())
                            }

                            Text("Private & On-Device")
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

                // Installed languages summary & expandable list
                if isEnabled {
                    Divider()
                        .padding(.leading, 50)

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showInstalledLanguages.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: showInstalledLanguages ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(colors.textSecondary.opacity(0.5))
                            Text("\(installedLangs.count) languages downloaded")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colors.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showInstalledLanguages {
                        ForEach(installedLangs) { lang in
                            Divider()
                                .padding(.leading, 50)

                            HStack(spacing: 8) {
                                Text(lang.nativeName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(colors.textPrimary)
                                Text(lang.englishName)
                                    .font(.system(size: 13))
                                    .foregroundColor(colors.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }

                        Divider()
                            .padding(.leading, 50)

                        Button {
                            showDownloadLanguagesGuide = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 14))
                                Text("How to Download More Languages")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(cardBackground)
        }
    }

    private var installedLanguageOptions: [TargetLanguageOption] {
        let installed = preferences.appleTranslateInstalledLanguages
        return TargetLanguageOption.filteredSelectionOptions(appleTranslateEnabled: true, installedLanguages: installed)
            .filter { $0 != .appLanguage }
    }

    private func toggleAppleTranslate() {
        let id = ModelConfig.appleTranslateID
        var newSet = enabledModelIDs
        let wasEnabled = newSet.contains(id)

        if wasEnabled {
            newSet.remove(id)
            AppPreferences.shared.setAppleTranslateInstalledLanguages([])
        } else {
            // Language packs will be downloaded on-demand
            // when the user actually translates (via .translationTask in HomeView).
            newSet.insert(id)
            refreshInstalledLanguagesInBackground()
        }

        #if DEBUG
        print("[ModelsView] toggleAppleTranslate: \(wasEnabled ? "OFF" : "ON"), before=\(enabledModelIDs), after=\(newSet)")
        #endif

        enabledModelIDs = newSet
        preferences.setEnabledModelIDs(newSet)
    }

    private func refreshInstalledLanguagesInBackground() {
        Task {
            let installed = await fetchInstalledLanguages()
            await MainActor.run {
                AppPreferences.shared.setAppleTranslateInstalledLanguages(Set(installed.map(\.rawValue)))
            }
        }
    }

    private func fetchInstalledLanguages() async -> Set<TargetLanguageOption> {
        guard AppleTranslationService.shared.isAvailable else { return [] }
        if #available(iOS 17.4, macOS 14.4, *) {
            return await AppleTranslationService.shared.refreshInstalledLanguages()
        }
        return []
    }

    // MARK: - Cloud Model Sections

    private func modelGroupSection(
        title: String,
        icon: String,
        models: [ModelConfig],
        hiddenModels: [ModelConfig] = [],
        isExpanded: Binding<Bool>,
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

                    if index < models.count - 1 || !hiddenModels.isEmpty {
                        Divider()
                            .padding(.leading, 56)
                    }
                }

                if !hiddenModels.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isExpanded.wrappedValue.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(colors.textSecondary.opacity(0.5))
                            Text("\(hiddenModels.count) more models")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colors.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isExpanded.wrappedValue {
                        ForEach(Array(hiddenModels.enumerated()), id: \.element.id) { index, model in
                            Divider()
                                .padding(.leading, 56)
                            modelRow(model: model)
                        }
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
            #if DEBUG
            print("[ModelsView] modelRow TAPPED: \(model.id), isEnabled=\(isEnabled), isLocked=\(isLocked), isDisabledByLimit=\(isDisabledByLimit)")
            #endif
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

                        ForEach(model.tags, id: \.self) { tag in
                            Text(tag.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
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
        let wasEnabled = newSet.contains(model.id)
        let isLocked = model.isPremium && !storeManager.isPremium

        #if DEBUG
        print("[ModelsView] toggleModel(\(model.id)): wasEnabled=\(wasEnabled), isLocked=\(isLocked), hasReachedFreeLimit=\(hasReachedFreeLimit), before=\(enabledModelIDs)")
        #endif

        if wasEnabled {
            newSet.remove(model.id)
        } else {
            if hasReachedFreeLimit {
                #if DEBUG
                print("[ModelsView] toggleModel(\(model.id)): BLOCKED by free limit")
                #endif
                withAnimation(.spring(duration: 0.3)) {
                    showLimitBanner = true
                }
                return
            }
            newSet.insert(model.id)
        }

        #if DEBUG
        print("[ModelsView] toggleModel(\(model.id)): \(wasEnabled ? "OFF" : "ON"), after=\(newSet)")
        #endif

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
                        #if DEBUG
                        print("[ModelsView] loadModels: set defaults → \(enabledModelIDs)")
                        #endif
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

// MARK: - Download Languages Guide Sheet

private struct DownloadLanguagesGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    #if os(iOS)
                    iosGuide
                    #else
                    macGuide
                    #endif
                }
                .padding(24)
            }
            .background(colors.background.ignoresSafeArea())
            .navigationTitle("Download More Languages")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    #if os(iOS)
    private var iosGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            guideHeader(
                icon: "iphone",
                title: "On iPhone / iPad",
                subtitle: "Go to Settings to download language packs for offline use."
            )

            VStack(alignment: .leading, spacing: 12) {
                guideStep(number: 1, text: "Open the **Settings** app")
                guideStep(number: 2, text: "Tap **Apps** → **Translate**")
                guideStep(number: 3, text: "Tap **Languages**")
                guideStep(number: 4, text: "Toggle on the languages you want to use offline")
            }
        }
    }
    #endif

    #if os(macOS)
    private var macGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            guideHeader(
                icon: "laptopcomputer",
                title: "On Mac",
                subtitle: "Download language packs from System Settings."
            )

            VStack(alignment: .leading, spacing: 12) {
                guideStep(number: 1, text: "Open **System Settings**")
                guideStep(number: 2, text: "Click **General** → **Language & Region**")
                guideStep(number: 3, text: "Scroll down to **Translation Languages**")
                guideStep(number: 4, text: "Click **+** to add the languages you need")
            }
        }
    }
    #endif

    private func guideHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(colors.accent)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)
            }
        }
    }

    private func guideStep(number: Int, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(colors.accent)
                .clipShape(Circle())

            Text(text)
                .font(.system(size: 15))
                .foregroundColor(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }}

#Preview {
    ModelsView()
        .preferredColorScheme(.dark)
}
