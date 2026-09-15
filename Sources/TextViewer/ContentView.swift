import SwiftUI

struct ContentView: View {
    private let text: String
    private let result: ParseResult

    @State private var expanded: Set<String>
    @State private var query: String
    @FocusState private var filterFocused: Bool
    @AppStorage("splitFraction") private var splitFraction: Double = 0.5

    private static let minimumPaneWidth: CGFloat = 280

    /// `initialQuery` exists so the offscreen renderer can screenshot a
    /// filtered tree; the app always passes the default.
    init(text: String, initialQuery: String = "") {
        let parsed = JSONParser.parse(text)
        self.text = text
        self.result = parsed
        _query = State(initialValue: initialQuery)
        _expanded = State(initialValue: parsed.root.map { TreeBuilder.defaultExpansion(root: $0) } ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let leftWidth = clampedLeftWidth(in: geometry.size.width)
                HStack(spacing: 0) {
                    EditorView(text: text, tokens: result.tokens)
                        .frame(width: leftWidth)
                    splitHandle(totalWidth: geometry.size.width, leftWidth: leftWidth)
                    detailPane
                        .frame(maxWidth: .infinity)
                }
            }
            Divider().overlay(Theme.divider.swiftUI)
            statusBar
        }
        .background(Theme.background.swiftUI)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    filterFocused = true
                } label: {
                    Label("Filter", systemImage: "magnifyingglass")
                }
                .help("Filter the tree (⌘⇧F)")
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(result.root == nil)

                Button {
                    if let root = result.root { expanded = TreeBuilder.allContainerIDs(root: root) }
                } label: {
                    Label("Expand All", systemImage: "chevron.down")
                }
                .help("Expand all (⌘⌥E)")
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(result.root == nil)

                Button {
                    expanded = ["$"]
                } label: {
                    Label("Collapse All", systemImage: "chevron.right")
                }
                .help("Collapse all (⌘⌥W)")
                .keyboardShortcut("w", modifiers: [.command, .option])
                .disabled(result.root == nil)
            }
        }
    }

    // MARK: - Panes

    @ViewBuilder
    private var detailPane: some View {
        if let root = result.root {
            TreeView(root: root, expanded: $expanded, query: $query, focus: $filterFocused)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.errorText.swiftUI)
                Text(errorHeadline)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primaryText.swiftUI)
                if let error = result.error {
                    Text("Line \(error.line), column \(error.column)")
                        .font(Fonts.tree)
                        .foregroundStyle(Theme.secondaryText.swiftUI)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .background(Theme.background.swiftUI)
        }
    }

    /// The divider doubles as the drag target; its position is remembered as a
    /// fraction so it survives both quitting and resizing the window.
    private func splitHandle(totalWidth: CGFloat, leftWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Theme.divider.swiftUI)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 10)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                guard totalWidth > 0 else { return }
                                let proposed = leftWidth + value.translation.width
                                splitFraction = Double(clamp(proposed, in: totalWidth) / totalWidth)
                            }
                    )
            )
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(result.root == nil ? "Invalid JSON" : "Valid JSON")
                .foregroundStyle((result.root == nil ? Theme.errorText : Theme.secondaryText).swiftUI)
            separatorDot
            Text("\(text.count.formatted()) characters")
            if let root = result.root {
                separatorDot
                Text("\(root.propertyCount.formatted()) properties")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.secondaryText.swiftUI)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Theme.statusBar.swiftUI)
    }

    private var separatorDot: some View {
        Text("·").foregroundStyle(Theme.punctuation.swiftUI)
    }

    private var errorHeadline: String {
        guard let error = result.error else { return "This file isn’t valid JSON" }
        return error.message.prefix(1).uppercased() + error.message.dropFirst()
    }

    // MARK: - Geometry

    private func clampedLeftWidth(in totalWidth: CGFloat) -> CGFloat {
        clamp(totalWidth * CGFloat(splitFraction), in: totalWidth)
    }

    private func clamp(_ width: CGFloat, in totalWidth: CGFloat) -> CGFloat {
        let upper = max(Self.minimumPaneWidth, totalWidth - Self.minimumPaneWidth)
        return min(max(width, Self.minimumPaneWidth), upper)
    }
}
