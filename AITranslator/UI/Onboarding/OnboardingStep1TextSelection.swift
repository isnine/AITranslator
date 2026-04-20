//
//  OnboardingStep1TextSelection.swift
//  TLingo
//
//  Step 1 of first-launch onboarding: enable text selection translation.
//

#if os(macOS)
    import ShareCore
    import SwiftUI

    struct OnboardingStep1TextSelection: View {
        @ObservedObject var permissionManager: AccessibilityPermissionManager
        let colors: AppColorPalette

        var body: some View {
            VStack(spacing: 18) {
                Image(systemName: "hand.point.up.left.and.text")
                    .font(.system(size: 48))
                    .foregroundStyle(colors.accent)

                VStack(spacing: 8) {
                    Text("Text Selection Translation")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(colors.textPrimary)

                    Text("Select text in any app to instantly translate it. TLingo needs Accessibility permission to detect your text selections.")
                        .font(.system(size: 14))
                        .foregroundColor(colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                HStack(spacing: 12) {
                    Image(systemName: permissionManager.isAccessibilityGranted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(permissionManager.isAccessibilityGranted ? .green : colors.textSecondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.textPrimary)
                        Text(permissionManager.isAccessibilityGranted ? "Granted" : "Required to detect text selections")
                            .font(.system(size: 12))
                            .foregroundColor(permissionManager.isAccessibilityGranted ? .green : colors.textSecondary)
                    }

                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colors.cardBackground)
                )

                if !permissionManager.isAccessibilityGranted {
                    VStack(alignment: .leading, spacing: 8) {
                        stepRow(number: 1, text: "Click \"Open System Settings\" below")
                        stepRow(number: 2, text: "Click the + button, then add TLingo from Applications")
                        stepRow(number: 3, text: "This page will update automatically")
                    }
                    .padding(.horizontal, 8)
                }

                Spacer(minLength: 0)
            }
            .onAppear { permissionManager.startPolling() }
            .onDisappear { permissionManager.stopPolling() }
        }

        private func stepRow(number: Int, text: LocalizedStringKey) -> some View {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(colors.accent))

                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(colors.textSecondary)
            }
        }
    }
#endif
