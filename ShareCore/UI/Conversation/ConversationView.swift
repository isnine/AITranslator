import SwiftUI

/// Standalone conversation content without NavigationStack wrapper.
/// Used by the macOS inspector panel and can be embedded in any container.
public struct ConversationContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: ConversationViewModel

    private let onDismiss: (() -> Void)?

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    public init(session: ConversationSession, onDismiss: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: ConversationViewModel(session: session))
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            header

            Divider()
                .foregroundColor(colors.divider)
            #endif

            messageList

            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            Divider()
                .foregroundColor(colors.divider)

            ConversationInputBar(
                text: $viewModel.inputText,
                selectedModel: $viewModel.model,
                isStreaming: viewModel.isStreaming,
                canSend: viewModel.canSend,
                availableModels: viewModel.availableModels,
                images: viewModel.attachedImages,
                onRemoveImage: { id in viewModel.removeImage(id: id) },
                onAddImages: { platformImages in
                    for img in platformImages {
                        #if os(macOS)
                            if let attachment = ImageAttachment.from(nsImage: img) {
                                viewModel.addImage(attachment)
                            }
                        #else
                            if let attachment = ImageAttachment.from(uiImage: img) {
                                viewModel.addImage(attachment)
                            }
                        #endif
                    }
                },
                onSend: { viewModel.send() },
                onStop: { viewModel.stopStreaming() }
            )
        }
        .background(colors.background)
        #if os(macOS)
        .onKeyPress(.tab) {
            viewModel.cycleModel()
            return .handled
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(viewModel.action.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)

            Spacer()

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }

                    if viewModel.isStreaming {
                        StreamingBubbleView(text: viewModel.streamingText)
                            .id("streaming")
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.streamingText) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if viewModel.isStreaming {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let lastMessage = viewModel.messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(colors.error)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(colors.error)
                .lineLimit(2)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colors.error.opacity(0.1))
    }
}

// MARK: - Sheet Wrapper

/// Conversation view presented as a sheet (iOS).
/// Users dismiss by dragging the sheet down.
public struct ConversationView: View {
    private let session: ConversationSession

    public init(session: ConversationSession) {
        self.session = session
    }

    public var body: some View {
        ConversationContentView(session: session)
    }
}
