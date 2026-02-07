import SwiftUI

/// A chat bubble view for displaying messages in the conversation.
/// Supports system (collapsed/expandable), user (right-aligned), and assistant (left-aligned with TTS + copy buttons) roles.
public struct MessageBubbleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var ttsService = TTSPreviewService.shared
    @State private var isSystemExpanded: Bool = false

    let message: ChatMessage
    let isStreaming: Bool

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    public init(message: ChatMessage, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }

    public var body: some View {
        switch message.role {
        case "system":
            systemBubble
        case "user":
            userBubble
        case "assistant":
            assistantBubble
        default:
            EmptyView()
        }
    }

    // MARK: - System Bubble (tap to expand)

    private var systemBubble: some View {
        Text(message.content)
            .font(.system(size: 12))
            .foregroundColor(colors.textSecondary)
            .lineLimit(isSystemExpanded ? nil : 1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSystemExpanded.toggle()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }

    // MARK: - User Bubble (right-aligned)

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.content)
                .font(.system(size: 15))
                .foregroundColor(colors.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colors.accent.opacity(0.15))
                )
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Assistant Bubble (left-aligned with TTS + copy buttons)

    private var isSpeakingThis: Bool {
        ttsService.isSpeaking(textID: message.id.uuidString)
    }

    private var assistantBubble: some View {
        HStack {
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !isStreaming {
                    HStack(spacing: 12) {
                        Spacer()

                        // TTS button
                        Button {
                            if isSpeakingThis {
                                ttsService.stopPlayback()
                            } else {
                                Task {
                                    await ttsService.speak(text: message.content, textID: message.id.uuidString)
                                }
                            }
                        } label: {
                            Image(systemName: isSpeakingThis ? "stop.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 11))
                                .foregroundColor(isSpeakingThis ? .red : colors.textSecondary)
                        }
                        .buttonStyle(.plain)

                        // Copy button
                        Button {
                            PasteboardHelper.copy(message.content)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundColor(colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colors.cardBackground)
            )

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 8)
    }
}

/// A streaming text bubble that shows partial text while the model is generating.
public struct StreamingBubbleView: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String

    public init(text: String) {
        self.text = text
    }

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    public var body: some View {
        HStack {
            VStack(alignment: .trailing, spacing: 4) {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 15))
                    .foregroundColor(colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colors.cardBackground)
            )
            .overlay(alignment: .bottomTrailing) {
                StreamingIndicator(colors: colors)
                    .padding(8)
            }

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 8)
    }
}

private struct StreamingIndicator: View {
    let colors: AppColorPalette
    @State private var opacity: Double = 0.3

    var body: some View {
        Circle()
            .fill(colors.accent)
            .frame(width: 6, height: 6)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    opacity = 1.0
                }
            }
    }
}
