//
//  VoiceRecordingView.swift
//  TLingo
//

import ShareCore
import SwiftUI

struct VoiceRecordingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var speechService = SpeechRecognitionService()
    let onComplete: (String) -> Void
    let onCancel: () -> Void

    /// Debounce: ignore taps within 300ms
    @State private var lastTapTime: Date = .distantPast
    @State private var showPermissionAlert = false
    @State private var showEmptyTranscriptToast = false

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            micButton

            stateLabel

            transcriptBox

            if showEmptyTranscriptToast {
                Text("No speech detected, please try again", comment: "Empty transcript toast")
                    .font(.system(size: 14))
                    .foregroundColor(colors.error)
                    .transition(.opacity)
            }

            actionButtons

            Spacer()
        }
        .padding(24)
        .background(colors.background.ignoresSafeArea())
        .onAppear {
            startRecording()
        }
        .onChange(of: speechService.state) { _, newState in
            if newState == .processing {
                let text = speechService.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    speechService.cancelRecording()
                    withAnimation {
                        showEmptyTranscriptToast = true
                    }
                    // Auto-dismiss after 2s
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation { showEmptyTranscriptToast = false }
                    }
                } else {
                    onComplete(text)
                }
            }
        }
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button {
                #if os(iOS)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                #endif
            } label: {
                Text("Open Settings", comment: "Open system settings for permissions")
            }
            Button("Cancel", role: .cancel) {
                onCancel()
            }
        } message: {
            Text(
                "Microphone and speech recognition permissions are required. Please enable them in Settings.",
                comment: "Permission denied alert message"
            )
        }
    }

    private var micButton: some View {
        Button {
            guard Date().timeIntervalSince(lastTapTime) > 0.3 else { return }
            lastTapTime = Date()

            if speechService.state == .recording {
                speechService.stopRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        speechService.state == .recording
                            ? LinearGradient(
                                colors: [.red, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [colors.accent, colors.accent.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(speechService.state == .recording ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: speechService.state == .recording
                    )

                Image(systemName: "mic.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private var stateLabel: some View {
        Group {
            switch speechService.state {
            case .recording:
                Text("Listening...", comment: "Voice recording state")
                    .font(.system(size: 16, weight: .semibold))
            case .paused:
                Text("Paused", comment: "Voice recording paused state")
                    .font(.system(size: 16, weight: .semibold))
            case .processing:
                ProgressView()
            case .idle:
                if let error = speechService.error {
                    Text(error.localizedDescription)
                        .font(.system(size: 14))
                        .foregroundColor(colors.error)
                } else {
                    Text("Describe the action you want to create", comment: "Voice recording hint")
                        .font(.system(size: 14))
                }
            }
        }
        .foregroundColor(colors.textSecondary)
    }

    private var transcriptBox: some View {
        Group {
            if !speechService.transcript.isEmpty {
                Text(speechService.transcript)
                    .font(.system(size: 15))
                    .foregroundColor(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colors.inputBackground)
                    )
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                speechService.cancelRecording()
                onCancel()
            } label: {
                Text("Cancel", comment: "Cancel voice recording")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colors.textSecondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(colors.cardBackground)
                    )
            }
            .buttonStyle(.plain)

            if speechService.state == .recording {
                Button {
                    guard Date().timeIntervalSince(lastTapTime) > 0.3 else { return }
                    lastTapTime = Date()
                    speechService.stopRecording()
                } label: {
                    Text("Done", comment: "Finish voice recording")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [colors.accent, colors.accent.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func startRecording() {
        Task {
            let authorized = await speechService.requestAuthorization()
            guard authorized else {
                showPermissionAlert = true
                return
            }
            try? speechService.startRecording()
        }
    }
}
