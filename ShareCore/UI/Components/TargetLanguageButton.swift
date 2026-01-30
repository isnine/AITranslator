import SwiftUI

public struct TargetLanguageButton<Background: View>: View {
    let title: String
    let action: () -> Void
    let foregroundColor: Color
    let spacing: CGFloat
    let globeFont: Font
    let textFont: Font
    let chevronSystemName: String
    let chevronFont: Font
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let background: Background

    public init(
        title: String,
        action: @escaping () -> Void,
        foregroundColor: Color,
        spacing: CGFloat = 4,
        globeFont: Font = .system(size: 10),
        textFont: Font = .system(size: 11),
        chevronSystemName: String = "chevron.up.chevron.down",
        chevronFont: Font = .system(size: 8),
        horizontalPadding: CGFloat = 0,
        verticalPadding: CGFloat = 0,
        @ViewBuilder background: () -> Background = { EmptyView() }
    ) {
        self.title = title
        self.action = action
        self.foregroundColor = foregroundColor
        self.spacing = spacing
        self.globeFont = globeFont
        self.textFont = textFont
        self.chevronSystemName = chevronSystemName
        self.chevronFont = chevronFont
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.background = background()
    }

    public var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: spacing) {
                Image(systemName: "globe")
                    .font(globeFont)
                Text(title)
                    .font(textFont)
                Image(systemName: chevronSystemName)
                    .font(chevronFont)
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(background)
        }
        .buttonStyle(.plain)
    }
}
