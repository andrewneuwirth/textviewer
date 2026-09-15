import AppKit
import SwiftUI

/// One palette, defined once as dynamic NSColors so both panes agree and the
/// window follows the system appearance.
enum Theme {
    static let background = dynamic(dark: 0x1E1F22, light: 0xFFFFFF)
    static let gutter = dynamic(dark: 0x1E1F22, light: 0xFAFAFA)
    static let divider = dynamic(dark: 0x303236, light: 0xE3E3E6)
    static let statusBar = dynamic(dark: 0x25262A, light: 0xF6F6F7)
    static let lineNumber = dynamic(dark: 0x5B6069, light: 0xA9AFB8)
    static let chevron = dynamic(dark: 0x8A9199, light: 0x8A9199)
    static let primaryText = dynamic(dark: 0xD7DAE0, light: 0x1F2328)
    static let secondaryText = dynamic(dark: 0x8A9199, light: 0x6B7280)

    static let key = dynamic(dark: 0x79B8FF, light: 0x0550AE)
    static let index = dynamic(dark: 0xB9C0CB, light: 0x57606A)
    static let string = dynamic(dark: 0xE0836C, light: 0xB3461A)
    static let number = dynamic(dark: 0xB5CEA8, light: 0x2E7D32)
    static let boolean = dynamic(dark: 0xC792EA, light: 0x7A3DB8)
    static let nullValue = dynamic(dark: 0x7F8C98, light: 0x8A6D3B)
    static let typeLabel = dynamic(dark: 0xD7DAE0, light: 0x424A53)
    static let punctuation = dynamic(dark: 0x6B7280, light: 0x9AA0A6)
    static let errorText = dynamic(dark: 0xF07178, light: 0xC0392B)
    static let matchHighlight = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.47, green: 0.72, blue: 1.0, alpha: 0.18)
            : NSColor(srgbRed: 0.02, green: 0.31, blue: 0.68, alpha: 0.12)
    }

    static func color(for value: JSONValue) -> NSColor {
        switch value {
        case .object, .array: return typeLabel
        case .string: return string
        case .number: return number
        case .bool: return boolean
        case .null: return nullValue
        }
    }

    static let comment = dynamic(dark: 0x6A7A6A, light: 0x6A737D)
    static let warning = dynamic(dark: 0xE5B567, light: 0x9A6700)
    static let danger = dynamic(dark: 0xF07178, light: 0xC0392B)

    static func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .key: return key
        case .string: return string
        case .number: return number
        case .keyword: return boolean
        case .punctuation: return punctuation
        case .comment: return comment
        case .timestamp: return secondaryText
        case .warning: return warning
        case .error: return danger
        }
    }

    private static func dynamic(dark: Int, light: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        }
    }

    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
}

extension NSColor {
    var swiftUI: Color { Color(nsColor: self) }
}

enum Fonts {
    static let editorSize: CGFloat = 12.5
    static let treeSize: CGFloat = 12.5
    static let editor = NSFont.monospacedSystemFont(ofSize: editorSize, weight: .regular)
    static let tree = Font.system(size: treeSize, design: .monospaced)
}
