import SwiftUI

struct TextDiffPresentation {
    let original: AttributedString
    let revised: AttributedString
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

        enum SegmentType {
            case equal
            case added
            case removed
        }

        struct Segment {
            var type: SegmentType
            var text: String
        }

        var segments: [Segment] = []
        var i = originalChars.count
        var j = revisedChars.count
        var addedBuffer: [Character] = []
        var removedBuffer: [Character] = []

        func flushAdded() {
            guard !addedBuffer.isEmpty else { return }
            let text = String(addedBuffer.reversed())
            segments.append(.init(type: .added, text: text))
            addedBuffer.removeAll(keepingCapacity: true)
        }

        func flushRemoved() {
            guard !removedBuffer.isEmpty else { return }
            let text = String(removedBuffer.reversed())
            segments.append(.init(type: .removed, text: text))
            removedBuffer.removeAll(keepingCapacity: true)
        }

        while i > 0 || j > 0 {
            if i > 0, j > 0, originalChars[i - 1] == revisedChars[j - 1] {
                flushAdded()
                flushRemoved()
                segments.append(.init(type: .equal, text: String(originalChars[i - 1])))
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

        var merged: [Segment] = []
        for segment in segments {
            if let lastIndex = merged.indices.last, merged[lastIndex].type == segment.type {
                merged[lastIndex].text.append(contentsOf: segment.text)
            } else {
                merged.append(segment)
            }
        }

        var originalAttributed = AttributedString()
        var revisedAttributed = AttributedString()
        var hasRemovals = false
        var hasAdditions = false

        for segment in merged {
            switch segment.type {
            case .equal:
                var piece = AttributedString(segment.text)
                piece.foregroundColor = Color.primary
                originalAttributed.append(piece)
                revisedAttributed.append(piece)
            case .added:
                var piece = AttributedString(segment.text)
                piece.backgroundColor = Color.green.opacity(0.35)
                piece.foregroundColor = Color.white
                revisedAttributed.append(piece)
                hasAdditions = true
            case .removed:
                var piece = AttributedString(segment.text)
                piece.backgroundColor = Color.red.opacity(0.35)
                piece.foregroundColor = Color.white
                piece.strikethroughStyle = .single
                originalAttributed.append(piece)
                hasRemovals = true
            }
        }

        return TextDiffPresentation(
            original: originalAttributed,
            revised: revisedAttributed,
            hasRemovals: hasRemovals,
            hasAdditions: hasAdditions
        )
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
