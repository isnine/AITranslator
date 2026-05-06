//
//  OnboardingView.swift
//  TLingo
//
//  First-launch onboarding wizard (macOS-only).
//

#if os(macOS)
    import ShareCore
    import SwiftUI

    struct OnboardingView: View {
        @Binding var isPresented: Bool
        @Environment(\.colorScheme) private var colorScheme

        #if DEBUG
            @StateObject private var permissionManager = AccessibilityPermissionManager()
        #endif
        @ObservedObject private var prefs = AppPreferences.shared
        @ObservedObject private var hotKeyManager = HotKeyManager.shared

        @State private var step: Int = OnboardingView.firstStep
        @State private var selectedModelIDs: Set<String> = [ModelConfig.googleTranslateID]
        @State private var isRecordingHotKey = false
        @State private var hotKeyMonitor: Any?

        // Step IDs are stable across configurations: 0=text selection, 1=hotkey, 2=models.
        // Release skips step 0 entirely because Accessibility-based features are DEBUG-only.
        #if DEBUG
            private static let firstStep = 0
        #else
            private static let firstStep = 1
        #endif

        private static let lastStep = 2

        private var colors: AppColorPalette {
            AppColors.Palette(colorScheme: colorScheme, accentTheme: prefs.accentTheme)
        }

        var body: some View {
            VStack(spacing: 20) {
                ProgressDotsView(
                    current: step - Self.firstStep,
                    total: Self.lastStep - Self.firstStep + 1,
                    colors: colors
                )
                .padding(.top, 20)

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.25), value: step)

                footer
            }
            .padding(24)
            .frame(width: 520, height: 540)
            .background(colors.background)
            .interactiveDismissDisabled(true)
        }

        @ViewBuilder
        private var stepContent: some View {
            switch step {
            #if DEBUG
                case 0:
                    OnboardingStep1TextSelection(
                        permissionManager: permissionManager,
                        colors: colors
                    )
            #endif
            case 1:
                OnboardingStep2Hotkey(
                    hotKeyManager: hotKeyManager,
                    isRecording: $isRecordingHotKey,
                    monitor: $hotKeyMonitor,
                    colors: colors
                )
            default:
                OnboardingStep3Models(
                    selectedModelIDs: $selectedModelIDs,
                    colors: colors
                )
            }
        }

        private var footer: some View {
            HStack(spacing: 12) {
                if step > Self.firstStep {
                    Button {
                        withAnimation { step -= 1 }
                    } label: {
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if step < Self.lastStep {
                    Button {
                        handleSkip()
                    } label: {
                        Text("Skip")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    handlePrimary()
                } label: {
                    Text(primaryButtonTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 28)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(primaryButtonEnabled ? colors.accent : colors.accent.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!primaryButtonEnabled)
            }
        }

        private var primaryButtonTitle: LocalizedStringKey {
            switch step {
            #if DEBUG
                case 0:
                    return permissionManager.isAccessibilityGranted ? "Enable" : "Open System Settings"
            #endif
            case 1:
                return "Continue"
            default:
                return "Get Started"
            }
        }

        private var primaryButtonEnabled: Bool {
            switch step {
            #if DEBUG
                case 0:
                    return true
            #endif
            case 1:
                return !hotKeyManager.quickTranslateConfiguration.isEmpty
            default:
                return !selectedModelIDs.isEmpty
            }
        }

        private func handlePrimary() {
            switch step {
            #if DEBUG
                case 0:
                    if permissionManager.isAccessibilityGranted {
                        prefs.setTextSelectionTranslationEnabled(true)
                        withAnimation { step = 1 }
                    } else {
                        permissionManager.openAccessibilitySettings()
                    }
            #endif
            case 1:
                withAnimation { step = 2 }
            default:
                finish()
            }
        }

        private func handleSkip() {
            switch step {
            #if DEBUG
                case 0:
                    withAnimation { step = 1 }
            #endif
            case 1:
                hotKeyManager.clearConfiguration(for: .quickTranslate)
                withAnimation { step = 2 }
            default:
                break
            }
        }

        private func finish() {
            prefs.setEnabledModelIDs(selectedModelIDs)
            prefs.setHasCompletedOnboarding(true)
            isPresented = false
        }
    }

    private struct ProgressDotsView: View {
        let current: Int
        let total: Int
        let colors: AppColorPalette

        var body: some View {
            HStack(spacing: 10) {
                ForEach(0..<total, id: \.self) { index in
                    Circle()
                        .fill(index <= current ? colors.accent : colors.textSecondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: current)
                }
            }
        }
    }
#endif
