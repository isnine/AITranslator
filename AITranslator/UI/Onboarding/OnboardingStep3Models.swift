//
//  OnboardingStep3Models.swift
//  TLingo
//
//  Step 3 of first-launch onboarding: choose default translation models.
//

#if os(macOS)
    import ShareCore
    import SwiftUI

    struct OnboardingStep3Models: View {
        @Binding var selectedModelIDs: Set<String>
        let colors: AppColorPalette

        private let models: [ModelConfig] = [.googleTranslate, .appleTranslate]

        var body: some View {
            VStack(spacing: 20) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(colors.accent)

                VStack(spacing: 8) {
                    Text("Choose Translation Models")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(colors.textPrimary)

                    Text("Select which engines TLingo uses by default. You can change this later in Settings.")
                        .font(.system(size: 14))
                        .foregroundColor(colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                VStack(spacing: 10) {
                    ForEach(models, id: \.id) { model in
                        modelRow(model)
                    }
                }
                .padding(.top, 4)

                if selectedModelIDs.isEmpty {
                    Text("Select at least one model to continue.")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }

                Spacer(minLength: 0)

                Text("Tip: Google Translate works universally without any setup.")
                    .font(.system(size: 11))
                    .foregroundColor(colors.textSecondary.opacity(0.8))
            }
        }

        private func modelRow(_ model: ModelConfig) -> some View {
            HStack(spacing: 14) {
                Image(systemName: iconName(for: model))
                    .font(.system(size: 20))
                    .foregroundColor(colors.accent)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                    Text(subtitle(for: model))
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                Toggle("", isOn: binding(for: model.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(colors.cardBackground)
            )
        }

        private func binding(for id: String) -> Binding<Bool> {
            Binding(
                get: { selectedModelIDs.contains(id) },
                set: { isOn in
                    if isOn {
                        selectedModelIDs.insert(id)
                    } else {
                        selectedModelIDs.remove(id)
                    }
                }
            )
        }

        private func iconName(for model: ModelConfig) -> String {
            if model.id == ModelConfig.appleTranslateID { return "apple.logo" }
            if model.id == ModelConfig.googleTranslateID { return "globe" }
            return "cpu"
        }

        private func subtitle(for model: ModelConfig) -> LocalizedStringKey {
            if model.id == ModelConfig.appleTranslateID {
                return "On-device, private, no network needed"
            }
            if model.id == ModelConfig.googleTranslateID {
                return "Free, fast, universal coverage"
            }
            return ""
        }
    }
#endif
