import AppKit
import QuickLookUI
import SwiftUI

/// Spacebar in Finder renders the same tree the app shows, read-only.
@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        await MainActor.run {
            let hosting = NSHostingView(rootView: QuickLookPreview(text: text))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: view.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }
}

struct QuickLookPreview: View {
    let text: String
    private let result: ParseResult

    init(text: String) {
        self.text = text
        self.result = JSONParser.parse(text)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let root = result.root {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(TreeBuilder.rows(root: root, expanded: expansion(for: root), filter: nil)) { row in
                            TreeRowView(row: row,
                                        isExpanded: expansion(for: root).contains(row.id),
                                        isMatch: false) {}
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.errorText.swiftUI)
                    Text("Not valid JSON")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.primaryText.swiftUI)
                    if let error = result.error {
                        Text("Line \(error.line), column \(error.column)")
                            .font(Fonts.tree)
                            .foregroundStyle(Theme.secondaryText.swiftUI)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            statusBar
        }
        .background(Theme.background.swiftUI)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(result.root == nil ? "Invalid JSON" : "Valid JSON")
            Text("·").foregroundStyle(Theme.punctuation.swiftUI)
            Text("\(text.count.formatted()) characters")
            if let root = result.root {
                Text("·").foregroundStyle(Theme.punctuation.swiftUI)
                Text("\(root.propertyCount.formatted()) properties")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.secondaryText.swiftUI)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Theme.statusBar.swiftUI)
    }

    /// A preview is a glance, not a session: open what fits, no more.
    private func expansion(for root: JSONValue) -> Set<String> {
        var ids: Set<String> = ["$"]
        var rows = 1
        var queue: [(JSONValue, String)] = [(root, "$")]
        while !queue.isEmpty {
            let (value, id) = queue.removeFirst()
            let children = TreeBuilder.children(of: value, parentID: id)
            guard !children.isEmpty, rows + children.count <= 200 else { continue }
            ids.insert(id)
            rows += children.count
            for child in children where child.value.isContainer {
                queue.append((child.value, child.id))
            }
        }
        return ids
    }
}
