import SwiftUI

struct TextDiffSegment {
    enum Kind {
        case equal
        case added
        case removed
    }

    var kind: Kind
    var text: String
}

struct TextDiffPresentation {
    let originalSegments: [TextDiffSegment]
    let revisedSegments: [TextDiffSegment]
    let hasRemovals: Bool
    let hasAdditions: Bool
}

enum TextDiffBuilder {
    static func build(original: String, revised: String) -> TextDiffPresentation? {
        guard original != revised else {
            return nil
        }

        let originalChars = Array(original)
        let revisedChars = Array(revised)
        guard !originalChars.isEmpty || !revisedChars.isEmpty else {
            return nil
        }

        let lcsMatrix = buildLCSMatrix(original: originalChars, revised: revisedChars)

        var segments: [TextDiffSegment] = []
        var i = originalChars.count
        var j = revisedChars.count
        var addedBuffer: [Character] = []
        var removedBuffer: [Character] = []

        func flushAdded() {
            guard !addedBuffer.isEmpty else { return }
            let text = String(addedBuffer.reversed())
            segments.append(.init(kind: .added, text: text))
            addedBuffer.removeAll(keepingCapacity: true)
        }

        func flushRemoved() {
            guard !removedBuffer.isEmpty else { return }
            let text = String(removedBuffer.reversed())
            segments.append(.init(kind: .removed, text: text))
            removedBuffer.removeAll(keepingCapacity: true)
        }

        while i > 0 || j > 0 {
            if i > 0, j > 0, originalChars[i - 1] == revisedChars[j - 1] {
                flushAdded()
                flushRemoved()
                segments.append(.init(kind: .equal, text: String(originalChars[i - 1])))
                i -= 1
                j -= 1
            } else if j > 0, (i == 0 || lcsMatrix[i][j - 1] >= lcsMatrix[i - 1][j]) {
                addedBuffer.append(revisedChars[j - 1])
                j -= 1
            } else if i > 0 {
                removedBuffer.append(originalChars[i - 1])
                i -= 1
            }
        }

        flushAdded()
        flushRemoved()

        segments.reverse()

        var merged: [TextDiffSegment] = []
        for segment in segments {
            if let lastIndex = merged.indices.last, merged[lastIndex].kind == segment.kind {
                merged[lastIndex].text.append(contentsOf: segment.text)
            } else {
                merged.append(segment)
            }
        }

        var originalSegments: [TextDiffSegment] = []
        var revisedSegments: [TextDiffSegment] = []
        var hasRemovals = false
        var hasAdditions = false

        for segment in merged {
            switch segment.kind {
            case .equal:
                originalSegments.append(segment)
                revisedSegments.append(segment)
            case .added:
                revisedSegments.append(segment)
                hasAdditions = true
            case .removed:
                originalSegments.append(segment)
                hasRemovals = true
            }
        }

        return TextDiffPresentation(
            originalSegments: originalSegments,
            revisedSegments: revisedSegments,
            hasRemovals: hasRemovals,
            hasAdditions: hasAdditions
        )
    }

    static func attributedString(
        for segments: [TextDiffSegment],
        palette: AppColorPalette,
        colorScheme: ColorScheme
    ) -> AttributedString {
        let theme = TextDiffColorTheme.forScheme(colorScheme, palette: palette)
        var attributed = AttributedString()

        for segment in segments {
            var piece = AttributedString(segment.text)
            switch segment.kind {
            case .equal:
                piece.foregroundColor = theme.baseForeground
            case .added:
                piece.backgroundColor = theme.additionBackground
                piece.foregroundColor = theme.additionForeground
            case .removed:
                piece.backgroundColor = theme.removalBackground
                piece.foregroundColor = theme.removalForeground
                piece.strikethroughStyle = .single
            }
            attributed.append(piece)
        }

        return attributed
    }

    private static func buildLCSMatrix(original: [Character], revised: [Character]) -> [[Int]] {
        let rows = original.count + 1
        let columns = revised.count + 1
        var matrix = Array(repeating: Array(repeating: 0, count: columns), count: rows)

        for i in 1..<rows {
            for j in 1..<columns {
                if original[i - 1] == revised[j - 1] {
                    matrix[i][j] = matrix[i - 1][j - 1] + 1
                } else {
                    matrix[i][j] = max(matrix[i - 1][j], matrix[i][j - 1])
                }
            }
        }

        return matrix
    }
}

private struct TextDiffColorTheme {
    let additionBackground: Color
    let additionForeground: Color
    let removalBackground: Color
    let removalForeground: Color
    let baseForeground: Color

    static func forScheme(_ colorScheme: ColorScheme, palette: AppColorPalette) -> TextDiffColorTheme {
        let success = AppColors.success.resolve(colorScheme)
        let error = AppColors.error.resolve(colorScheme)
        switch colorScheme {
        case .dark:
            return TextDiffColorTheme(
                additionBackground: success.opacity(0.35),
                additionForeground: Color.white,
                removalBackground: error.opacity(0.35),
                removalForeground: Color.white,
                baseForeground: palette.textPrimary
            )
        default:
            return TextDiffColorTheme(
                additionBackground: success.opacity(0.18),
                additionForeground: success,
                removalBackground: error.opacity(0.18),
                removalForeground: error,
                baseForeground: palette.textPrimary
            )
        }
    }
}
