import AppKit

enum Highlighter {
    /// Plain text with one uniform attribute run. Colors are layered on top as
    /// *temporary* attributes for the visible window only — an attributed
    /// string carrying a run per token costs hundreds of megabytes on a
    /// multi-megabyte file, and all of it would be off screen.
    static func baseStorage(for text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2.5
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: Fonts.editor,
            .foregroundColor: Theme.primaryText,
            .paragraphStyle: paragraph
        ])
    }

    /// Colors `range`, clearing whatever `previous` range was colored before.
    static func colorize(tokens: [Token], layoutManager: NSLayoutManager,
                         range: NSRange, clearing previous: NSRange?) {
        if let previous, previous.length > 0 {
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: previous)
        }
        guard range.length > 0, !tokens.isEmpty else { return }

        let end = NSMaxRange(range)
        var index = firstTokenIndex(in: tokens, endingAfter: range.location)
        while index < tokens.count, tokens[index].start < end {
            let token = tokens[index]
            let start = max(token.start, range.location)
            let stop = min(token.end, end)
            if stop > start {
                layoutManager.addTemporaryAttribute(
                    .foregroundColor,
                    value: Theme.color(for: token.kind),
                    forCharacterRange: NSRange(location: start, length: stop - start))
            }
            index += 1
        }
    }

    private static func firstTokenIndex(in tokens: [Token], endingAfter location: Int) -> Int {
        var low = 0
        var high = tokens.count
        while low < high {
            let mid = (low + high) / 2
            if tokens[mid].end <= location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
