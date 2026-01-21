//
//  ProviderDetailView.swift
//  TLingo
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
    @State private var baseEndpoint: String
    @State private var apiVersion: String
    @State private var token: String
    @State private var authHeaderName: String
    @State private var category: ProviderCategory
    @State private var deploymentsText: String  // comma-separated input
    @State private var enabledDeploymentsSet: Set<String>  // Track which deployments are enabled
    @State private var showDeleteConfirmation = false

    // Test states
    @State private var testResults: [DeploymentTestResult] = []
    @State private var isTesting = false
    @State private var showDebugSheet = false
    @State private var debugInfo: DebugInfo?

    // Validation error state
    @State private var showValidationError = false
    @State private var validationErrorMessage = ""

    struct DeploymentTestResult: Identifiable {
        let id = UUID()
        let deploymentName: String
        var status: TestStatus
        var isEnabled: Bool
        var debugInfo: DebugInfo?
        var latency: TimeInterval?

        enum TestStatus {
            case pending
            case testing
            case success
            case failure(String)
        }
    }

    struct DebugInfo {
        let requestURL: String
        let requestHeaders: [String: String]
        let requestBody: String
        let responseStatusCode: Int?
        let responseBody: String
    }

    init(
        provider: ProviderConfig?,
        configurationStore: AppConfigurationStore
    ) {
        self._configurationStore = ObservedObject(wrappedValue: configurationStore)

        if let provider = provider {
            self.providerID = provider.id
            self.isNewProvider = false
            _displayName = State(initialValue: provider.displayName)
            _baseEndpoint = State(initialValue: provider.baseEndpoint.absoluteString)
            _apiVersion = State(initialValue: provider.apiVersion)
            _token = State(initialValue: provider.token)
            _authHeaderName = State(initialValue: provider.authHeaderName)
            _category = State(initialValue: provider.category)
            _deploymentsText = State(initialValue: provider.deployments.joined(separator: ", "))
            _enabledDeploymentsSet = State(initialValue: provider.enabledDeployments)
        } else {
            self.providerID = UUID()
            self.isNewProvider = true
            // Default to Built-in Cloud for new providers
            _displayName = State(initialValue: "Built-in Cloud")
            _baseEndpoint = State(initialValue: "")
            _apiVersion = State(initialValue: "2024-02-15-preview")
            _token = State(initialValue: "")
            _authHeaderName = State(initialValue: "api-key")
            _category = State(initialValue: .builtInCloud)
            _deploymentsText = State(initialValue: ProviderConfig.builtInCloudAvailableModels.joined(separator: ", "))
            _enabledDeploymentsSet = State(initialValue: Set(ProviderConfig.builtInCloudAvailableModels))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    categorySection

                    if category == .builtInCloud {
                        builtInCloudSection
                    } else {
                        basicInfoSection
                        connectionSection
                        deploymentsSection
                    }

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
        .sheet(isPresented: $showDebugSheet) {
            debugSheet
        }
        .alert("Validation Failed", isPresented: $showValidationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationErrorMessage)
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
        if category == .builtInCloud {
            // Built-in Cloud needs at least one model enabled
            return !enabledDeploymentsSet.isEmpty
        }
        return !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !baseEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            URL(string: baseEndpoint) != nil &&
            hasEnabledDeployments
    }

    private var hasEnabledDeployments: Bool {
        // Either we have test results with enabled deployments, or we have deployments text and haven't tested yet
        if testResults.isEmpty {
            return !deploymentsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return testResults.contains { $0.isEnabled }
    }

    private var basicInfoSection: some View {
        section(title: "Basic Info") {
            labeledField(title: "Display Name", text: $displayName, placeholder: "e.g., Azure OpenAI")
        }
    }

    private var connectionSection: some View {
        section(title: "Connection") {
            labeledField(
                title: "Base Endpoint",
                text: $baseEndpoint,
                placeholder: "https://xxx.openai.azure.com/openai/deployments"
            )

            labeledField(
                title: "API Version",
                text: $apiVersion,
                placeholder: "e.g., 2025-01-01-preview"
            )

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

    /// Current parsed deployments from the text field
    private var currentDeployments: [String] {
        deploymentsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var deploymentsSection: some View {
        section(title: "Deployments") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Deployment Names")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.textSecondary)

                    TextField("e.g., model-router, gpt-5, gpt-4o", text: $deploymentsText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .foregroundColor(colors.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(colors.inputBackground)
                        )
                        .onChange(of: deploymentsText) { _, newValue in
                            // Clear test results when deployments change
                            testResults = []
                            // Update enabledDeploymentsSet: new deployments are enabled by default
                            let newDeployments = newValue
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            // Keep existing enabled state for deployments that still exist
                            // Enable new deployments by default
                            let newSet = Set(newDeployments)
                            let stillEnabled = enabledDeploymentsSet.intersection(newSet)
                            let newlyAdded = newSet.subtracting(enabledDeploymentsSet)
                            enabledDeploymentsSet = stillEnabled.union(newlyAdded)
                        }

                    Text("Separate multiple deployments with commas")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                }

                // Test button
                Button {
                    Task {
                        await runDeploymentTests()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isTesting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                        }
                        Text(isTesting ? "Testing..." : "Test Deployments")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(canTest ? colors.accent : colors.accent.opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canTest || isTesting)

                // Test results list (shown after testing)
                if !testResults.isEmpty {
                    VStack(spacing: 8) {
                        ForEach($testResults) { $result in
                            deploymentResultRow(result: $result)
                        }
                    }
                    .padding(.top, 8)
                }
                // Enabled deployments list (shown when not testing)
                else if !currentDeployments.isEmpty {
                    enabledDeploymentsListSection
                }
            }
        }
    }

    /// UI section for toggling which deployments are enabled
    private var enabledDeploymentsListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enabled Deployments")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.textSecondary)
                .padding(.top, 8)

            VStack(spacing: 8) {
                ForEach(currentDeployments, id: \.self) { deployment in
                    deploymentToggleRow(deployment: deployment)
                }
            }
        }
    }

    /// A single row with toggle for enabling/disabling a deployment
    private func deploymentToggleRow(deployment: String) -> some View {
        let isEnabled = enabledDeploymentsSet.contains(deployment)
        return HStack(spacing: 12) {
            Button {
                if isEnabled {
                    enabledDeploymentsSet.remove(deployment)
                } else {
                    enabledDeploymentsSet.insert(deployment)
                }
            } label: {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isEnabled ? colors.accent : colors.textSecondary)
            }
            .buttonStyle(.plain)

            Text(deployment)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(colors.textPrimary)

            Spacer()

            Text(isEnabled ? "Enabled" : "Disabled")
                .font(.system(size: 12))
                .foregroundColor(isEnabled ? colors.success : colors.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(deploymentRowBackground)
    }

    @ViewBuilder
    private var deploymentRowBackground: some View {
        if #available(iOS 26, macOS 26, *) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colors.cardBackground)
        }
    }

    private var canTest: Bool {
        !deploymentsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !baseEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        URL(string: baseEndpoint) != nil &&
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func deploymentResultRow(result: Binding<DeploymentTestResult>) -> some View {
        HStack(spacing: 12) {
            // Checkbox (only for successful tests)
            switch result.wrappedValue.status {
            case .success:
                Button {
                    result.wrappedValue.isEnabled.toggle()
                } label: {
                    Image(systemName: result.wrappedValue.isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(result.wrappedValue.isEnabled ? colors.accent : colors.textSecondary)
                }
                .buttonStyle(.plain)
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(colors.error)
            case .testing:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)
            case .pending:
                Image(systemName: "circle.dotted")
                    .font(.system(size: 22))
                    .foregroundColor(colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result.wrappedValue.deploymentName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colors.textPrimary)

                switch result.wrappedValue.status {
                case .success:
                    if let latency = result.wrappedValue.latency {
                        Text("Connection successful (\(String(format: "%.0f", latency * 1000))ms)")
                            .font(.system(size: 12))
                            .foregroundColor(colors.success)
                    } else {
                        Text("Connection successful")
                            .font(.system(size: 12))
                            .foregroundColor(colors.success)
                    }
                case .failure(let message):
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(colors.error)
                        .lineLimit(1)
                case .testing:
                    Text("Testing...")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                case .pending:
                    Text("Waiting...")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                }
            }

            Spacer()

            // Debug button for failed tests
            if case .failure = result.wrappedValue.status,
               result.wrappedValue.debugInfo != nil {
                Button {
                    debugInfo = result.wrappedValue.debugInfo
                    showDebugSheet = true
                } label: {
                    Text("Debug")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(colors.accent.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(deploymentResultRowBackground)
    }

    @ViewBuilder
    private var deploymentResultRowBackground: some View {
        if #available(iOS 26, macOS 26, *) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colors.cardBackground)
        }
    }

    private var debugSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let info = debugInfo {
                        debugSection(title: "Request URL", content: info.requestURL)

                        debugSection(title: "Request Headers") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(info.requestHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(key):")
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                            .foregroundColor(colors.textPrimary)
                                        Text(value)
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(colors.textSecondary)
                                    }
                                }
                            }
                        }

                        debugSection(title: "Request Body", content: info.requestBody)

                        if let statusCode = info.responseStatusCode {
                            debugSection(title: "Response Status", content: "\(statusCode)")
                        }

                        debugSection(title: "Response Body", content: info.responseBody)
                    }
                }
                .padding(20)
            }
            .background(colors.background.ignoresSafeArea())
            .navigationTitle("Debug Info")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showDebugSheet = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func debugSection(title: String, content: String) -> some View {
        debugSection(title: title) {
            Text(content)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(colors.textPrimary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func debugSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(colors.textPrimary)

            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colors.cardBackground)
                )
        }
    }

    private var categorySection: some View {
        section(title: "Provider Type") {
            VStack(spacing: 12) {
                ForEach(ProviderCategory.editableCategories, id: \.self) { cat in
                    categoryRow(cat)
                }
            }
        }
    }

    private func categoryRow(_ cat: ProviderCategory) -> some View {
        let isSelected = category == cat
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                category = cat
                // Reset fields when switching categories
                if cat == .builtInCloud {
                    displayName = "Built-in Cloud"
                    deploymentsText = ProviderConfig.builtInCloudAvailableModels.joined(separator: ", ")
                    enabledDeploymentsSet = Set(ProviderConfig.builtInCloudAvailableModels)
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cat.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text(cat.categoryDescription)
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
            .background(selectionRowBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }

    private var builtInCloudSection: some View {
        section(title: "Model Selection") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Select the models you want to use")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.textSecondary)

                ForEach(ProviderConfig.builtInCloudAvailableModels, id: \.self) { model in
                    builtInCloudModelRow(model: model)
                }

                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundColor(colors.success)
                    Text("Ready to use - No API key required")
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }
                .padding(.top, 8)
            }
        }
    }

    private func builtInCloudModelRow(model: String) -> some View {
        let isEnabled = enabledDeploymentsSet.contains(model)
        let modelDescription: String = {
            switch model {
            case "model-router":
                return "Smart routing - automatically selects the best model"
            case "gpt-4.1-nano":
                return "Fast & efficient - optimized for quick responses"
            default:
                return model
            }
        }()

        return Button {
            if isEnabled {
                enabledDeploymentsSet.remove(model)
            } else {
                enabledDeploymentsSet.insert(model)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isEnabled ? colors.accent : colors.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text(modelDescription)
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(builtInCloudModelRowBackground(isEnabled: isEnabled))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func builtInCloudModelRowBackground(isEnabled: Bool) -> some View {
        if #available(iOS 26, macOS 26, *) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.clear)
                .glassEffect(isEnabled ? .regular : .regular.interactive(), in: .rect(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isEnabled ? colors.accent : .clear, lineWidth: 2)
                )
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isEnabled ? colors.accent : colors.cardBackground, lineWidth: 2)
                )
        }
    }

    @ViewBuilder
    private func selectionRowBackground(isSelected: Bool) -> some View {
        if #available(iOS 26, macOS 26, *) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.clear)
                .glassEffect(isSelected ? .regular : .regular.interactive(), in: .rect(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isSelected ? colors.accent : .clear, lineWidth: 2)
                )
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isSelected ? colors.accent : colors.cardBackground, lineWidth: 2)
                )
        }
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

    // MARK: - Test Logic

    private func runDeploymentTests() async {
        let deploymentNames = deploymentsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !deploymentNames.isEmpty else { return }

        isTesting = true

        // Initialize all results as testing (concurrent)
        testResults = deploymentNames.map { name in
            DeploymentTestResult(deploymentName: name, status: .testing, isEnabled: false)
        }

        // Test all deployments concurrently
        await withTaskGroup(of: (Int, DeploymentTestResult).self) { group in
            for (index, deploymentName) in deploymentNames.enumerated() {
                group.addTask {
                    let result = await self.testDeployment(deploymentName)
                    return (index, result)
                }
            }
            
            for await (index, result) in group {
                testResults[index] = result
            }
        }

        isTesting = false
    }

    private func testDeployment(_ deploymentName: String) async -> DeploymentTestResult {
        guard let baseURL = URL(string: baseEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return DeploymentTestResult(
                deploymentName: deploymentName,
                status: .failure("Invalid base endpoint URL"),
                isEnabled: false
            )
        }

        // Build URL: baseEndpoint/{deployment}/chat/completions?api-version={version}
        let path = baseURL.appendingPathComponent(deploymentName)
            .appendingPathComponent("chat/completions")
        var components = URLComponents(url: path, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "api-version", value: apiVersion)]

        guard let url = components.url else {
            return DeploymentTestResult(
                deploymentName: deploymentName,
                status: .failure("Failed to build request URL"),
                isEnabled: false
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: authHeaderName)

        let requestBody: [String: Any] = [
            "messages": [
                ["role": "user", "content": "hello"]
            ]
        ]

        let requestBodyData: Data
        let requestBodyString: String
        do {
            requestBodyData = try JSONSerialization.data(withJSONObject: requestBody, options: [.prettyPrinted])
            requestBodyString = String(data: requestBodyData, encoding: .utf8) ?? "{}"
            request.httpBody = requestBodyData
        } catch {
            return DeploymentTestResult(
                deploymentName: deploymentName,
                status: .failure("Failed to encode request body"),
                isEnabled: false
            )
        }

        // Capture request headers for debug
        var headers: [String: String] = [:]
        headers["Content-Type"] = "application/json"
        headers[authHeaderName] = "***" // Mask token

        let startTime = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latency = Date().timeIntervalSince(startTime)

            guard let httpResponse = response as? HTTPURLResponse else {
                let debug = DebugInfo(
                    requestURL: url.absoluteString,
                    requestHeaders: headers,
                    requestBody: requestBodyString,
                    responseStatusCode: nil,
                    responseBody: "Invalid response type"
                )
                return DeploymentTestResult(
                    deploymentName: deploymentName,
                    status: .failure("Invalid response"),
                    isEnabled: false,
                    debugInfo: debug
                )
            }

            let responseBody = String(data: data, encoding: .utf8) ?? ""

            if (200...299).contains(httpResponse.statusCode) {
                // Success - enable by default
                return DeploymentTestResult(
                    deploymentName: deploymentName,
                    status: .success,
                    isEnabled: true,
                    latency: latency
                )
            } else {
                let debug = DebugInfo(
                    requestURL: url.absoluteString,
                    requestHeaders: headers,
                    requestBody: requestBodyString,
                    responseStatusCode: httpResponse.statusCode,
                    responseBody: responseBody
                )
                return DeploymentTestResult(
                    deploymentName: deploymentName,
                    status: .failure("HTTP \(httpResponse.statusCode)"),
                    isEnabled: false,
                    debugInfo: debug
                )
            }
        } catch {
            let debug = DebugInfo(
                requestURL: url.absoluteString,
                requestHeaders: headers,
                requestBody: requestBodyString,
                responseStatusCode: nil,
                responseBody: error.localizedDescription
            )
            return DeploymentTestResult(
                deploymentName: deploymentName,
                status: .failure(error.localizedDescription),
                isEnabled: false,
                debugInfo: debug
            )
        }
    }

    // MARK: - Save / Delete

    private func saveProvider() {
        let updated: ProviderConfig

        if category == .builtInCloud {
            // Built-in Cloud uses built-in configuration with selected models
            updated = ProviderConfig(
                id: providerID,
                displayName: "Built-in Cloud",
                baseEndpoint: ProviderConfig.builtInCloudEndpoint,
                apiVersion: "2025-01-01-preview",
                token: "",
                authHeaderName: "api-key",
                category: .builtInCloud,
                deployments: ProviderConfig.builtInCloudAvailableModels,
                enabledDeployments: enabledDeploymentsSet
            )
        } else {
            guard let url = URL(string: baseEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return
            }

            // Get all deployments from text input
            let allDeployments = deploymentsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            // Get enabled deployments based on current state
            let enabledDeploymentSet: Set<String>
            if !testResults.isEmpty {
                // If we have test results, use them (only enable successful + user-selected ones)
                enabledDeploymentSet = Set(testResults.filter(\.isEnabled).map(\.deploymentName))
            } else {
                // Use the enabledDeploymentsSet state (respects user toggles)
                // Only include deployments that are in the current list
                enabledDeploymentSet = enabledDeploymentsSet.intersection(Set(allDeployments))
            }

            updated = ProviderConfig(
                id: providerID,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                baseEndpoint: url,
                apiVersion: apiVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                token: token.trimmingCharacters(in: .whitespacesAndNewlines),
                authHeaderName: authHeaderName.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                deployments: allDeployments,
                enabledDeployments: enabledDeploymentSet
            )
        }

        var providers = configurationStore.providers

        if let index = providers.firstIndex(where: { $0.id == providerID }) {
            providers[index] = updated
        } else {
            providers.append(updated)
        }

        if let result = configurationStore.updateProviders(providers), result.hasErrors {
            validationErrorMessage = result.errors.map(\.message).joined(separator: "\n")
            showValidationError = true
        } else {
            dismiss()
        }
    }

    private func deleteProvider() {
        var providers = configurationStore.providers
        providers.removeAll { $0.id == providerID }
        
        if let result = configurationStore.updateProviders(providers), result.hasErrors {
            validationErrorMessage = result.errors.map(\.message).joined(separator: "\n")
            showValidationError = true
        } else {
            dismiss()
        }
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
