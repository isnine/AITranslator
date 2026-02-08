import SwiftUI

public enum TextDiffBuilder {
    public struct Segment {
        public enum Kind {
            case equal
            case added
            case removed
        }

        public var kind: Kind
        public var text: String
    }

    public struct Presentation {
        public let originalSegments: [Segment]
        public let revisedSegments: [Segment]
        public let hasRemovals: Bool
        public let hasAdditions: Bool
    }

    public static func build(original: String, revised: String) -> Presentation? {
        guard original != revised else {
            return nil
        }

        let originalTokens = tokenize(original)
        let revisedTokens = tokenize(revised)
        guard !originalTokens.isEmpty || !revisedTokens.isEmpty else {
            return nil
        }

        let lcsMatrix = buildLCSMatrix(original: originalTokens, revised: revisedTokens)

        // Backtrack to collect diff tokens, then merge adjacent same-kind tokens
        var tokenKinds: [(token: Substring, kind: Segment.Kind)] = []
        var i = originalTokens.count
        var j = revisedTokens.count

        while i > 0 || j > 0 {
            if i > 0, j > 0, originalTokens[i - 1] == revisedTokens[j - 1] {
                tokenKinds.append((originalTokens[i - 1], .equal))
                i -= 1
                j -= 1
            } else if j > 0, i == 0 || lcsMatrix[i][j - 1] >= lcsMatrix[i - 1][j] {
                tokenKinds.append((revisedTokens[j - 1], .added))
                j -= 1
            } else if i > 0 {
                tokenKinds.append((originalTokens[i - 1], .removed))
                i -= 1
            }
        }

        // Build merged segments in forward order
        var segments: [Segment] = []
        for idx in tokenKinds.indices.reversed() {
            let (token, kind) = tokenKinds[idx]
            if let lastIdx = segments.indices.last, segments[lastIdx].kind == kind {
                segments[lastIdx].text.append(contentsOf: token)
            } else {
                segments.append(.init(kind: kind, text: String(token)))
            }
        }

        var originalSegments: [Segment] = []
        var revisedSegments: [Segment] = []
        var hasRemovals = false
        var hasAdditions = false

        for segment in segments {
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

        return Presentation(
            originalSegments: originalSegments,
            revisedSegments: revisedSegments,
            hasRemovals: hasRemovals,
            hasAdditions: hasAdditions
        )
    }

    public static func attributedString(
        for segments: [Segment],
        palette: AppColorPalette,
        colorScheme: ColorScheme
    ) -> AttributedString {
        let theme = ColorTheme.forScheme(colorScheme, palette: palette)
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

    /// Tokenize a string into words and whitespace/punctuation tokens.
    /// Preserves all characters so `tokens.joined() == input`.
    private static func tokenize(_ string: String) -> [Substring] {
        var tokens: [Substring] = []
        let s = string[...]
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c.isWhitespace {
                // Collect contiguous whitespace
                let start = i
                while i < s.endIndex, s[i].isWhitespace {
                    i = s.index(after: i)
                }
                tokens.append(s[start ..< i])
            } else if c.isPunctuation || c.isSymbol {
                // Each punctuation/symbol character is its own token
                let next = s.index(after: i)
                tokens.append(s[i ..< next])
                i = next
            } else {
                // Collect contiguous word characters
                let start = i
                while i < s.endIndex, !s[i].isWhitespace, !s[i].isPunctuation, !s[i].isSymbol {
                    i = s.index(after: i)
                }
                tokens.append(s[start ..< i])
            }
        }
        return tokens
    }

    private static func buildLCSMatrix(original: [Substring], revised: [Substring]) -> [[Int]] {
        let rows = original.count + 1
        let columns = revised.count + 1
        var matrix = Array(repeating: Array(repeating: 0, count: columns), count: rows)

        for i in 1 ..< rows {
            for j in 1 ..< columns {
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

private extension TextDiffBuilder {
    struct ColorTheme {
        let additionBackground: Color
        let additionForeground: Color
        let removalBackground: Color
        let removalForeground: Color
        let baseForeground: Color

        static func forScheme(_ colorScheme: ColorScheme, palette: AppColorPalette) -> ColorTheme {
            let success = palette.success
            let error = palette.error
            switch colorScheme {
            case .dark:
                return ColorTheme(
                    additionBackground: success.opacity(0.35),
                    additionForeground: Color.white,
                    removalBackground: error.opacity(0.35),
                    removalForeground: Color.white,
                    baseForeground: palette.textPrimary
                )
            default:
                return ColorTheme(
                    additionBackground: success.opacity(0.18),
                    additionForeground: success,
                    removalBackground: error.opacity(0.18),
                    removalForeground: error,
                    baseForeground: palette.textPrimary
                )
            }
        }
    }
}
