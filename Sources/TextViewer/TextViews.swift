import AppKit
import SwiftUI

// MARK: - Table

struct TableTextView: View {
    let table: TextTable

    private static let cellFont = Font.system(size: 12, design: .monospaced)
    private let characterWidth: CGFloat = {
        let advance = ("0" as NSString).size(withAttributes: [.font: Fonts.editor]).width
        return max(advance, 6.5)
    }()

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                        rowView(row, index: index)
                    }
                } header: {
                    headerView
                }
            }
        }
        .background(Theme.background.swiftUI)
    }

    private var headerView: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: 56, alignment: .trailing)
            ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                Text(header)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.key.swiftUI)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(width: width(of: index), alignment: .leading)
            }
        }
        .padding(.vertical, 7)
        .background(Theme.statusBar.swiftUI)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.divider.swiftUI).frame(height: 1)
        }
    }

    private func rowView(_ row: [String], index: Int) -> some View {
        HStack(spacing: 0) {
            Text("\(index + 1)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.lineNumber.swiftUI)
                .frame(width: 56, alignment: .trailing)
                .padding(.trailing, 10)

            ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                let numeric = Double(cell.trimmingCharacters(in: .whitespaces)) != nil
                Text(cell)
                    .font(Self.cellFont)
                    .foregroundStyle((numeric ? Theme.number : Theme.primaryText).swiftUI)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .frame(width: width(of: column), alignment: numeric ? .trailing : .leading)
            }
        }
        .padding(.vertical, 3)
        .background(index.isMultiple(of: 2) ? Color.clear : Theme.statusBar.swiftUI.opacity(0.45))
    }

    private func width(of column: Int) -> CGFloat {
        let characters = column < table.columnWidths.count ? table.columnWidths[column] : 12
        return min(max(CGFloat(characters) * characterWidth + 16, 56), 420)
    }
}

// MARK: - Prose

/// Plain text that is meant to be *read*: a comfortable measure, generous
/// leading, and a real reading size instead of TextEdit's 12pt Helvetica.
struct ProseTextView: View {
    let text: String

    var body: some View {
        ScrollView(.vertical) {
            Text(text)
                .font(.system(size: 14.5))
                .lineSpacing(6)
                .textSelection(.enabled)
                .foregroundStyle(Theme.primaryText.swiftUI)
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.background.swiftUI)
    }
}
