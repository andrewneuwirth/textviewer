import AppKit
import SwiftUI

struct TreeRow: Identifiable {
    let id: String
    let path: String
    let depth: Int
    let label: String?
    let isIndex: Bool
    let value: JSONValue

    var isContainer: Bool { value.isContainer }
}

/// Which rows survive the filter: `matched` nodes hit the query themselves,
/// `keep` adds their ancestors so the path stays visible, and `expand` opens
/// those ancestors automatically.
struct FilterResult {
    let matched: Set<String>
    let keep: Set<String>
    let expand: Set<String>
    let matchCount: Int
}

enum TreeBuilder {
    static let separator = "\u{1F}"

    static func rows(root: JSONValue, expanded: Set<String>, filter: FilterResult?) -> [TreeRow] {
        var rows: [TreeRow] = []
        let effective = filter.map { expanded.union($0.expand) } ?? expanded
        walk(root, id: "$", path: "$", label: nil, isIndex: false, depth: 0,
             expanded: effective, filter: filter, insideMatch: false, into: &rows)
        return rows
    }

    static func allContainerIDs(root: JSONValue, limit: Int = 200_000) -> Set<String> {
        var ids: Set<String> = []
        func visit(_ value: JSONValue, id: String) {
            guard value.isContainer, ids.count < limit else { return }
            ids.insert(id)
            for child in children(of: value, parentID: id) { visit(child.value, id: child.id) }
        }
        visit(root, id: "$")
        return ids
    }

    /// Collapsed on open: the root's own members are listed, everything below
    /// stays shut until you ask for it.
    static func defaultExpansion(root: JSONValue) -> Set<String> { ["$"] }

    static func filter(root: JSONValue, query: String) -> FilterResult? {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return nil }

        var matched: Set<String> = []
        var keep: Set<String> = ["$"]
        var expand: Set<String> = ["$"]
        var count = 0

        @discardableResult
        func visit(_ value: JSONValue, id: String, label: String?) -> Bool {
            var hit = label?.lowercased().contains(needle) ?? false
            if !hit {
                switch value {
                case .string(let text): hit = text.lowercased().contains(needle)
                case .number(let text): hit = text.contains(needle)
                case .bool(let flag): hit = (flag ? "true" : "false").contains(needle)
                case .null: hit = "null".contains(needle)
                case .object, .array: break
                }
            }
            if hit {
                matched.insert(id)
                keep.insert(id)
                count += 1
            }

            var childHit = false
            for child in children(of: value, parentID: id) {
                if visit(child.value, id: child.id, label: child.label) { childHit = true }
            }
            if childHit {
                keep.insert(id)
                expand.insert(id)
            }
            return hit || childHit
        }

        visit(root, id: "$", label: nil)
        return FilterResult(matched: matched, keep: keep, expand: expand, matchCount: count)
    }

    static func children(of value: JSONValue, parentID: String) -> [(value: JSONValue, id: String, label: String, isIndex: Bool)] {
        switch value {
        case .object(let members):
            return members.map { ($0.value, parentID + separator + $0.key, $0.key, false) }
        case .array(let items):
            return items.enumerated().map { ($0.element, parentID + separator + "\($0.offset)", "\($0.offset)", true) }
        default:
            return []
        }
    }

    private static func walk(_ value: JSONValue, id: String, path: String, label: String?,
                             isIndex: Bool, depth: Int, expanded: Set<String>,
                             filter: FilterResult?, insideMatch: Bool, into rows: inout [TreeRow]) {
        rows.append(TreeRow(id: id, path: path, depth: depth, label: label, isIndex: isIndex, value: value))
        guard expanded.contains(id) else { return }

        let matchedHere = insideMatch || (filter?.matched.contains(id) ?? false)
        for child in children(of: value, parentID: id) {
            if let filter, !matchedHere, !filter.keep.contains(child.id) { continue }
            let childPath = child.isIndex ? path + "[\(child.label)]" : path + "." + child.label
            walk(child.value, id: child.id, path: childPath, label: child.label,
                 isIndex: child.isIndex, depth: depth + 1, expanded: expanded,
                 filter: filter, insideMatch: matchedHere, into: &rows)
        }
    }
}

struct TreeView: View {
    let root: JSONValue
    @Binding var expanded: Set<String>
    @Binding var query: String
    var focus: FocusState<Bool>.Binding

    @State private var filter: FilterResult?

    var body: some View {
        VStack(spacing: 0) {
            filterField
            Divider().overlay(Theme.divider.swiftUI)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(TreeBuilder.rows(root: root, expanded: expanded, filter: filter)) { row in
                        TreeRowView(row: row,
                                    isExpanded: isExpanded(row),
                                    isMatch: filter?.matched.contains(row.id) ?? false) {
                            toggle(row)
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.background.swiftUI)
        .task(id: query) {
            filter = TreeBuilder.filter(root: root, query: query)
        }
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText.swiftUI)
            TextField("Filter keys and values", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused(focus)
            if !query.isEmpty {
                Text(filter.map { "\($0.matchCount)" } ?? "0")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText.swiftUI)
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText.swiftUI)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.statusBar.swiftUI)
    }

    private func isExpanded(_ row: TreeRow) -> Bool {
        expanded.contains(row.id) || (filter?.expand.contains(row.id) ?? false)
    }

    private func toggle(_ row: TreeRow) {
        guard row.isContainer else { return }
        if isExpanded(row) {
            expanded.remove(row.id)
            if let filter, filter.expand.contains(row.id) {
                // A filter-opened row still has to close when clicked.
                self.filter = FilterResult(matched: filter.matched,
                                           keep: filter.keep,
                                           expand: filter.expand.subtracting([row.id]),
                                           matchCount: filter.matchCount)
            }
        } else {
            expanded.insert(row.id)
        }
    }
}

struct TreeRowView: View {
    let row: TreeRow
    let isExpanded: Bool
    let isMatch: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Group {
                if row.isContainer {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.chevron.swiftUI)
                } else {
                    Color.clear
                }
            }
            .frame(width: 11, alignment: .leading)

            if let label = row.label {
                (Text(label)
                    .foregroundStyle((row.isIndex ? Theme.index : Theme.key).swiftUI)
                 + Text(":")
                    .foregroundStyle(Theme.punctuation.swiftUI))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(valueText)
                .foregroundStyle(Theme.color(for: row.value).swiftUI)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .font(Fonts.tree)
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(isMatch ? Theme.matchHighlight.swiftUI : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .padding(.leading, CGFloat(row.depth) * 17)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .contextMenu {
            Button("Copy Value") { copy(copyValueText) }
            Button("Copy Path") { copy(row.path) }
            if let label = row.label, !row.isIndex {
                Button("Copy Key") { copy(label) }
            }
        }
    }

    /// What the row shows: escapes stay visible on one line, and very long
    /// strings are clipped so a 900-character value can't stall layout.
    private var valueText: String {
        switch row.value {
        case .string(let value): return "\"\(escaped(value))\""
        default: return copyValueText
        }
    }

    /// What Copy Value puts on the pasteboard: the real string, unescaped.
    private var copyValueText: String {
        switch row.value {
        case .object, .array: return row.value.typeLabel
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        }
    }

    private func escaped(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(min(value.count, 400) + 8)
        for character in value {
            switch character {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if let scalar = character.unicodeScalars.first,
                   character.unicodeScalars.count == 1, scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.append(character)
                }
            }
            if out.count >= 400 { return out + "…" }
        }
        return out
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
