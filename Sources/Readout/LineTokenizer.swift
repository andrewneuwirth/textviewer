import Foundation

/// Logs and config files get the same treatment JSON does: a flat token list
/// the editor colors lazily as you scroll.
enum LineTokenizer {
    private static let timestamp = try! NSRegularExpression(
        pattern: #"^\s*\[?(\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}(:\d{2}([.,]\d+)?)?)?|\d{2}:\d{2}:\d{2}([.,]\d+)?|\w{3}\s+\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2}\s+\d{4})\]?"#)
    private static let level = try! NSRegularExpression(
        pattern: #"\b(TRACE|DEBUG|INFO|NOTICE|WARN(?:ING)?|ERROR|FATAL|CRITICAL|Exception|Traceback)\b"#)
    private static let quoted = try! NSRegularExpression(pattern: #""[^"\n]*""#)
    private static let number = try! NSRegularExpression(pattern: #"(?<![\w.])-?\d+(\.\d+)?([eE][-+]?\d+)?(?![\w.])"#)
    private static let setting = try! NSRegularExpression(pattern: #"^\s*([\w.\-\[\]/]+)\s*([:=])"#)
    private static let section = try! NSRegularExpression(pattern: #"^\s*\[[^\]\n]+\]\s*$"#)

    static func log(_ text: String) -> [Token] {
        tokens(in: text) { line, lineRange, out in
            if let match = timestamp.firstMatch(in: line, range: lineRange) {
                out.append(Token(location: match.range.location, length: match.range.length, kind: .timestamp))
            }
            for match in level.matches(in: line, range: lineRange) {
                let word = (line as NSString).substring(with: match.range).uppercased()
                let kind: TokenKind
                switch word {
                case "ERROR", "FATAL", "CRITICAL", "EXCEPTION", "TRACEBACK": kind = .error
                case "WARN", "WARNING", "NOTICE": kind = .warning
                case "INFO": kind = .key
                default: kind = .comment
                }
                out.append(Token(location: match.range.location, length: match.range.length, kind: kind))
            }
            for match in quoted.matches(in: line, range: lineRange) {
                out.append(Token(location: match.range.location, length: match.range.length, kind: .string))
            }
        }
    }

    static func config(_ text: String) -> [Token] {
        tokens(in: text) { line, lineRange, out in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.hasPrefix(";") || trimmed.hasPrefix("//") {
                out.append(Token(location: lineRange.location, length: lineRange.length, kind: .comment))
                return
            }
            if section.firstMatch(in: line, range: lineRange) != nil {
                out.append(Token(location: lineRange.location, length: lineRange.length, kind: .keyword))
                return
            }
            var valueStart = lineRange.location
            if let match = setting.firstMatch(in: line, range: lineRange), match.numberOfRanges >= 3 {
                out.append(Token(location: match.range(at: 1).location,
                                 length: match.range(at: 1).length, kind: .key))
                out.append(Token(location: match.range(at: 2).location,
                                 length: match.range(at: 2).length, kind: .punctuation))
                valueStart = NSMaxRange(match.range(at: 2))
            }
            let valueRange = NSRange(location: valueStart,
                                     length: max(0, NSMaxRange(lineRange) - valueStart))
            guard valueRange.length > 0 else { return }
            for match in quoted.matches(in: line, range: valueRange) {
                out.append(Token(location: match.range.location, length: match.range.length, kind: .string))
            }
            for match in number.matches(in: line, range: valueRange) {
                out.append(Token(location: match.range.location, length: match.range.length, kind: .number))
            }
        }
    }

    /// Walks lines once, letting each styler append tokens in document order.
    private static func tokens(in text: String,
                              styler: @escaping (String, NSRange, inout [Token]) -> Void) -> [Token] {
        let full = text as NSString
        var out: [Token] = []
        out.reserveCapacity(min(full.length / 12, 400_000))
        full.enumerateSubstrings(in: NSRange(location: 0, length: full.length),
                                 options: [.byLines]) { _, lineRange, _, _ in
            guard lineRange.length > 0 else { return }
            let line = full.substring(with: lineRange)
            // Regexes run against the line but tokens carry document offsets,
            // so match ranges are shifted back by the line's own start.
            var lineTokens: [Token] = []
            styler(line, NSRange(location: 0, length: (line as NSString).length), &lineTokens)
            for token in lineTokens {
                out.append(Token(location: token.start + lineRange.location,
                                 length: Int(token.length),
                                 kind: token.kind))
            }
        }
        out.sort { $0.start < $1.start }
        return out
    }
}
