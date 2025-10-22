//
//  HomeView.swift
//  AITranslator
//
//  Created by Zander Wang on 2025/10/19.
//

import SwiftUI
import UIKit
import TranslationUIProvider
import WebKit

public struct HomeView: View {
  @Environment(\.colorScheme) private var colorScheme
  @StateObject private var viewModel: HomeViewModel
  @State private var hasTriggeredAutoRequest = false
  @State private var isInputExpanded: Bool
  var openFromExtension: Bool {
    context != nil
  }
  let context: TranslationUIProviderContext?

  private var colors: AppColorPalette {
    AppColors.palette(for: colorScheme)
  }

  private var usageScene: ActionConfig.UsageScene {
    guard let context else { return .app }
    return context.allowsReplacement ? .contextEdit : .contextRead
  }


  public init(context: TranslationUIProviderContext?) {
    self.context = context
    let initialScene: ActionConfig.UsageScene
    if let context {
      initialScene = context.allowsReplacement ? .contextEdit : .contextRead
    } else {
      initialScene = .app
    }
    _viewModel = StateObject(wrappedValue: HomeViewModel(usageScene: initialScene))
    _isInputExpanded = State(initialValue: context == nil)
  }

  public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
              if !openFromExtension {
                header
                defaultAppCard
              }
                inputComposer
                actionChips
                if viewModel.providerRuns.isEmpty {
                    hintLabel
                } else {
                    providerResultsSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .background(colors.background.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .onAppear {
          viewModel.updateUsageScene(usageScene)
          guard openFromExtension, !hasTriggeredAutoRequest else { return }
          if let inputText = context?.inputText {
            viewModel.inputText = String(inputText.characters)
          }
          hasTriggeredAutoRequest = true
          viewModel.performSelectedAction()
        }
        .onChange(of: openFromExtension) { _ in
          viewModel.updateUsageScene(usageScene)
        }
        .onChange(of: context?.allowsReplacement ?? false) { _ in
          viewModel.updateUsageScene(usageScene)
        }
    }

    private var header: some View {
        Text("AITranslator")
            .font(.system(size: 28, weight: .semibold))
            .foregroundColor(colors.textPrimary)
    }

    private var defaultAppCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(colors.accent)
                    .font(.system(size: 20))

                Text("将 AITranslator 设为系统默认翻译应用")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.textPrimary)

                Button(action: viewModel.openAppSettings) {
                    Text("设置")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.cardBackground)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(colors.accent)
                        )
                }
                .buttonStyle(.plain)
            }

        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colors.cardBackground)
        )
    }

    private var inputComposer: some View {
        let isCollapsed = openFromExtension && !isInputExpanded

        return ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colors.inputBackground)

            VStack(alignment: .leading, spacing: 0) {
                if isCollapsed {
                    collapsedInputSummary
                } else {
                    expandedInputEditor
                }

                if !isCollapsed {
                    Spacer(minLength: 0)
                }
            }
            .padding(.bottom, isCollapsed ? 0 : 48)

            VStack {
                Spacer()
                HStack {
                    if openFromExtension && !isCollapsed {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isInputExpanded = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("收起")
                                    .font(.system(size: 14, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(colors.textSecondary)
                    }

                    Spacer()

                    if !isCollapsed {
                        Button {
                            viewModel.performSelectedAction()
                        } label: {
                            HStack(spacing: 6) {
                                Text("发送")
                                    .font(.system(size: 15, weight: .semibold))
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .foregroundColor(colors.chipPrimaryText)
                            .background(
                                Capsule()
                                    .fill(colors.accent)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, isCollapsed ? 0 : 12)
            }
        }
        .frame(maxWidth: .infinity)
//        .frame(minHeight: isCollapsed ? 16 : 170)
        .animation(.easeInOut(duration: 0.2), value: isInputExpanded)
    }

    private var collapsedInputSummary: some View {
        let displayText = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isInputExpanded = true
            }
        } label: {
            HStack(spacing: 12) {
                Text(displayText.isEmpty ? viewModel.inputPlaceholder : displayText)
                    .font(.system(size: 15))
                    .foregroundColor(displayText.isEmpty ? colors.textSecondary : colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedInputEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if viewModel.inputText.isEmpty {
                    Text(viewModel.inputPlaceholder)
                        .foregroundColor(colors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }

                TextEditor(text: $viewModel.inputText)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(colors.textPrimary)
                    .padding(12)
                    .frame(minHeight: 140, maxHeight: 160)
            }
        }
    }

    private var actionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.actions) { action in
                    chip(for: action, isSelected: action.id == viewModel.selectedAction?.id)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(for action: ActionConfig, isSelected: Bool) -> some View {
        Button {
            if viewModel.selectAction(action) {
                viewModel.performSelectedAction()
            }
        } label: {
            Text(action.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? colors.chipPrimaryText : colors.chipSecondaryText)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? colors.chipPrimaryBackground : colors.chipSecondaryBackground)
                )
        }
        .buttonStyle(.plain)
    }

    private var hintLabel: some View {
        Text(viewModel.placeholderHint)
            .font(.system(size: 14))
            .foregroundColor(colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    private var providerResultsSection: some View {
        VStack(spacing: 16) {
            ForEach(viewModel.providerRuns) { run in
                providerResultCard(for: run)
            }
        }
    }

    private func providerResultCard(for run: HomeViewModel.ProviderRunViewState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                statusIndicator(for: run.status)

                VStack(alignment: .leading, spacing: 2) {
                    Text(run.provider.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                    Text(run.provider.modelName)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                if let duration = run.durationText {
                    Text(duration)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
            }

            content(for: run.status, providerName: run.provider.displayName)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colors.cardBackground)
        )
    }

    @ViewBuilder
    private func content(
        for status: HomeViewModel.ProviderRunViewState.Status,
        providerName: String
    ) -> some View {
        switch status {
        case .idle, .running:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(colors.skeleton)
                        .frame(height: 10)
                }
            }
        case let .streaming(text, _):
            VStack(alignment: .leading, spacing: 12) {
                if text.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(colors.skeleton)
                                .frame(height: 10)
                        }
                    }
                } else {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(colors.textPrimary)
                }

                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(colors.accent)
                    Text("正在生成…")
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }
            }
        case let .success(text, _, diff):
            VStack(alignment: .leading, spacing: 12) {
                if let diff {
                    VStack(alignment: .leading, spacing: 8) {
                        if diff.hasRemovals {
                            let originalText = TextDiffBuilder.attributedString(
                                for: diff.originalSegments,
                                palette: colors,
                                colorScheme: colorScheme
                            )
                            Text(originalText)
                                .font(.system(size: 14))
                        }

                        if diff.hasAdditions || (!diff.hasRemovals && !diff.hasAdditions) {
                            let revisedText = TextDiffBuilder.attributedString(
                                for: diff.revisedSegments,
                                palette: colors,
                                colorScheme: colorScheme
                            )
                            Text(revisedText)
                                .font(.system(size: 14))
                        }
                    }
                } else {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(colors.textPrimary)
                }
                HStack(spacing: 16) {
                    if let context, context.allowsReplacement {
                        Button {
                            context.finish(translation: AttributedString(text))
                        } label: {
                            Label("替换", systemImage: "arrow.left.arrow.right")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(colors.accent)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = text
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc")
                                Text("复制")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, openFromExtension ? 18 : 0)
                            .padding(.vertical, openFromExtension ? 10 : 0)
                            .foregroundColor(openFromExtension ? colors.chipPrimaryText : colors.accent)
                            .background(
                                Group {
                                    if openFromExtension {
                                        Capsule()
                                            .fill(colors.accent)
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(openFromExtension ? colors.chipPrimaryText : colors.accent)
                    } else {
                        Button {
                            UIPasteboard.general.string = text
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(colors.accent)
                    }
                }
            }
        case let .failure(message, _):
            VStack(alignment: .leading, spacing: 10) {
                Text("请求失败")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colors.error)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func statusIndicator(
        for status: HomeViewModel.ProviderRunViewState.Status
    ) -> some View {
        switch status {
        case .idle, .running, .streaming:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(colors.accent)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(colors.success)
                .font(.system(size: 18))
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(colors.error)
                .font(.system(size: 18))
        }
    }
}

#Preview {
  HomeView(context: nil)
        .preferredColorScheme(.dark)
}
