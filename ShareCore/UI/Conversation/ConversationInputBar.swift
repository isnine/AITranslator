import SwiftUI

/// Bottom input bar for the conversation view.
/// Contains a text field, model selector row, and a send/stop button
/// all within a single rounded-rect stroke container.
public struct ConversationInputBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    @Binding var selectedModel: ModelConfig
    let isStreaming: Bool
    let canSend: Bool
    let availableModels: [ModelConfig]
    let onSend: () -> Void
    let onStop: () -> Void

    private var colors: AppColorPalette {
        AppColors.palette(for: colorScheme)
    }

    public init(
        text: Binding<String>,
        selectedModel: Binding<ModelConfig>,
        isStreaming: Bool,
        canSend: Bool,
        availableModels: [ModelConfig] = [],
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        _text = text
        _selectedModel = selectedModel
        self.isStreaming = isStreaming
        self.canSend = canSend
        self.availableModels = availableModels
        self.onSend = onSend
        self.onStop = onStop
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Text input area
            TextField("Ask for follow-up changes", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1 ... 5)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, availableModels.isEmpty && !isStreaming ? 10 : 6)
                .onSubmit {
                    if canSend {
                        onSend()
                    }
                }

            // Bottom toolbar row
            HStack(spacing: 0) {
                if !availableModels.isEmpty {
                    modelPicker
                }

                Spacer()

                actionButton
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(colors.textSecondary.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Model Picker

    private var modelPicker: some View {
        Menu {
            ForEach(availableModels) { model in
                Button {
                    selectedModel = model
                } label: {
                    HStack {
                        Text(model.displayName)
                        if model.id == selectedModel.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedModel.displayName)
                    .font(.system(size: 12))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Send / Stop Button

    private var actionButton: some View {
        Group {
            if isStreaming {
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(colors.error)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(canSend ? colors.accent : colors.textSecondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
    }
}
