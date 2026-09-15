import Foundation

// An order-preserving JSON value. Foundation's JSONSerialization hands back an
// unordered dictionary, which would scramble the tree, so we keep members in
// document order and hold numbers as their original text.
indirect enum JSONValue {
    struct Member {
        let key: String
        let value: JSONValue
    }

    case object([Member])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    var isContainer: Bool {
        switch self {
        case .object, .array: return true
        default: return false
        }
    }

    var typeLabel: String {
        switch self {
        case .object: return "Object"
        case .array(let items): return "Array[\(items.count)]"
        case .string: return "String"
        case .number: return "Number"
        case .bool: return "Bool"
        case .null: return "Null"
        }
    }

    /// Every addressable member in the document: object keys plus array
    /// elements, at any depth.
    var propertyCount: Int {
        switch self {
        case .object(let members):
            return members.count + members.reduce(0) { $0 + $1.value.propertyCount }
        case .array(let items):
            return items.count + items.reduce(0) { $0 + $1.propertyCount }
        default:
            return 0
        }
    }
}

enum TokenKind: UInt8 {
    case key, string, number, keyword, punctuation
    // Used by the log and config tokenizers, which share this pipeline.
    case comment, timestamp, warning, error
}

/// 12 bytes rather than 24: a multi-megabyte file produces hundreds of
/// thousands of these, and no JSON document addresses past Int32.
struct Token {
    let location: Int32
    let length: Int32
    let kind: TokenKind

    init(location: Int, length: Int, kind: TokenKind) {
        self.location = Int32(clamping: location)
        self.length = Int32(clamping: length)
        self.kind = kind
    }

    var start: Int { Int(location) }
    var end: Int { Int(location) + Int(length) }
}

struct JSONParseError: Error {
    let message: String
    let line: Int
    let column: Int
}

struct ParseResult {
    let root: JSONValue?
    let tokens: [Token]
    let error: JSONParseError?
}

private enum C {
    static let tab = UInt16(UInt8(ascii: "\t"))
    static let newline = UInt16(UInt8(ascii: "\n"))
    static let ret = UInt16(UInt8(ascii: "\r"))
    static let space = UInt16(UInt8(ascii: " "))
    static let quote = UInt16(UInt8(ascii: "\""))
    static let backslash = UInt16(UInt8(ascii: "\\"))
    static let slash = UInt16(UInt8(ascii: "/"))
    static let colon = UInt16(UInt8(ascii: ":"))
    static let comma = UInt16(UInt8(ascii: ","))
    static let lbrace = UInt16(UInt8(ascii: "{"))
    static let rbrace = UInt16(UInt8(ascii: "}"))
    static let lbracket = UInt16(UInt8(ascii: "["))
    static let rbracket = UInt16(UInt8(ascii: "]"))
    static let minus = UInt16(UInt8(ascii: "-"))
    static let plus = UInt16(UInt8(ascii: "+"))
    static let dot = UInt16(UInt8(ascii: "."))
    static let zero = UInt16(UInt8(ascii: "0"))
    static let nine = UInt16(UInt8(ascii: "9"))
    static let lowerT = UInt16(UInt8(ascii: "t"))
    static let lowerF = UInt16(UInt8(ascii: "f"))
    static let lowerN = UInt16(UInt8(ascii: "n"))
    static let lowerU = UInt16(UInt8(ascii: "u"))
    static let lowerE = UInt16(UInt8(ascii: "e"))
    static let upperE = UInt16(UInt8(ascii: "E"))
    static let lowerB = UInt16(UInt8(ascii: "b"))
    static let lowerR = UInt16(UInt8(ascii: "r"))
}

final class JSONParser {
    private let s: [UInt16]
    private var i = 0
    private var tokens: [Token] = []

    private init(text: String) {
        self.s = Array(text.utf16)
    }

    /// Parses `text`, returning the value when it is valid plus every token we
    /// scanned — the tokens drive the left pane's highlighting either way, so a
    /// broken file still renders everything up to the mistake.
    static func parse(_ text: String) -> ParseResult {
        let parser = JSONParser(text: text)
        do {
            let value = try parser.parseDocument()
            return ParseResult(root: value, tokens: parser.tokens, error: nil)
        } catch let error as JSONParseError {
            return ParseResult(root: nil, tokens: parser.tokens, error: error)
        } catch {
            return ParseResult(root: nil, tokens: parser.tokens,
                               error: JSONParseError(message: "could not be read", line: 1, column: 1))
        }
    }

    // MARK: - Scanning

    private var current: UInt16? { i < s.count ? s[i] : nil }

    private func addToken(_ location: Int, _ length: Int, _ kind: TokenKind) {
        tokens.append(Token(location: location, length: length, kind: kind))
    }

    private func skipWhitespace() {
        while i < s.count {
            let c = s[i]
            if c == C.space || c == C.tab || c == C.newline || c == C.ret { i += 1 } else { break }
        }
    }

    private func fail(_ message: String) -> JSONParseError {
        var line = 1
        var lineStart = 0
        var k = 0
        while k < min(i, s.count) {
            if s[k] == C.newline {
                line += 1
                lineStart = k + 1
            }
            k += 1
        }
        return JSONParseError(message: message, line: line, column: i - lineStart + 1)
    }

    // MARK: - Grammar

    private func parseDocument() throws -> JSONValue {
        skipWhitespace()
        guard i < s.count else { throw fail("the file is empty") }
        let value = try parseValue()
        skipWhitespace()
        if i < s.count { throw fail("unexpected characters after the end of the JSON value") }
        return value
    }

    private func parseValue() throws -> JSONValue {
        skipWhitespace()
        guard let c = current else { throw fail("unexpected end of input") }
        switch c {
        case C.lbrace: return try parseObject()
        case C.lbracket: return try parseArray()
        case C.quote: return .string(try parseString(kind: .string))
        case C.lowerT: try expect("true"); return .bool(true)
        case C.lowerF: try expect("false"); return .bool(false)
        case C.lowerN: try expect("null"); return .null
        default: return .number(try parseNumber())
        }
    }

    private func parseObject() throws -> JSONValue {
        addToken(i, 1, .punctuation)
        i += 1
        var members: [JSONValue.Member] = []
        skipWhitespace()
        if current == C.rbrace {
            addToken(i, 1, .punctuation)
            i += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard current == C.quote else { throw fail("expected a property name in double quotes") }
            let key = try parseString(kind: .key)
            skipWhitespace()
            guard current == C.colon else { throw fail("expected ':' after the property name") }
            addToken(i, 1, .punctuation)
            i += 1
            let value = try parseValue()
            members.append(JSONValue.Member(key: key, value: value))
            skipWhitespace()
            if current == C.comma {
                addToken(i, 1, .punctuation)
                i += 1
                continue
            }
            if current == C.rbrace {
                addToken(i, 1, .punctuation)
                i += 1
                break
            }
            throw fail("expected ',' or '}'")
        }
        return .object(members)
    }

    private func parseArray() throws -> JSONValue {
        addToken(i, 1, .punctuation)
        i += 1
        var items: [JSONValue] = []
        skipWhitespace()
        if current == C.rbracket {
            addToken(i, 1, .punctuation)
            i += 1
            return .array(items)
        }
        while true {
            items.append(try parseValue())
            skipWhitespace()
            if current == C.comma {
                addToken(i, 1, .punctuation)
                i += 1
                continue
            }
            if current == C.rbracket {
                addToken(i, 1, .punctuation)
                i += 1
                break
            }
            throw fail("expected ',' or ']'")
        }
        return .array(items)
    }

    private func parseString(kind: TokenKind) throws -> String {
        let start = i
        i += 1
        var out: [UInt16] = []
        while true {
            guard i < s.count else { throw fail("unterminated string") }
            let c = s[i]
            if c == C.quote {
                i += 1
                break
            }
            if c == C.backslash {
                i += 1
                guard i < s.count else { throw fail("unterminated escape sequence") }
                switch s[i] {
                case C.quote: out.append(C.quote)
                case C.backslash: out.append(C.backslash)
                case C.slash: out.append(C.slash)
                case C.lowerB: out.append(8)
                case C.lowerF: out.append(12)
                case C.lowerN: out.append(10)
                case C.lowerR: out.append(13)
                case C.lowerT: out.append(9)
                case C.lowerU:
                    guard i + 4 < s.count else { throw fail("truncated \\u escape") }
                    var v: UInt16 = 0
                    for k in 1...4 {
                        guard let digit = hexValue(s[i + k]) else { throw fail("invalid \\u escape") }
                        v = (v << 4) | UInt16(digit)
                    }
                    i += 4
                    out.append(v)
                default:
                    throw fail("invalid escape character")
                }
                i += 1
                continue
            }
            if c < 0x20 { throw fail("unescaped control character in string") }
            out.append(c)
            i += 1
        }
        addToken(start, i - start, kind)
        return String(decoding: out, as: UTF16.self)
    }

    private func parseNumber() throws -> String {
        let start = i
        if current == C.minus { i += 1 }
        guard let first = current, first >= C.zero, first <= C.nine else {
            throw fail("expected a value")
        }
        while let c = current, c >= C.zero, c <= C.nine { i += 1 }
        if current == C.dot {
            i += 1
            guard let c = current, c >= C.zero, c <= C.nine else { throw fail("expected digits after the decimal point") }
            while let c = current, c >= C.zero, c <= C.nine { i += 1 }
        }
        if current == C.lowerE || current == C.upperE {
            i += 1
            if current == C.plus || current == C.minus { i += 1 }
            guard let c = current, c >= C.zero, c <= C.nine else { throw fail("expected digits in the exponent") }
            while let c = current, c >= C.zero, c <= C.nine { i += 1 }
        }
        addToken(start, i - start, .number)
        return String(decoding: s[start..<i], as: UTF16.self)
    }

    private func expect(_ literal: String) throws {
        let units = Array(literal.utf16)
        guard i + units.count <= s.count, Array(s[i..<(i + units.count)]) == units else {
            throw fail("expected a value")
        }
        addToken(i, units.count, .keyword)
        i += units.count
    }

    private func hexValue(_ unit: UInt16) -> Int? {
        switch unit {
        case C.zero...C.nine: return Int(unit - C.zero)
        case UInt16(UInt8(ascii: "a"))...UInt16(UInt8(ascii: "f")): return Int(unit - UInt16(UInt8(ascii: "a"))) + 10
        case UInt16(UInt8(ascii: "A"))...UInt16(UInt8(ascii: "F")): return Int(unit - UInt16(UInt8(ascii: "A"))) + 10
        default: return nil
        }
    }
}
