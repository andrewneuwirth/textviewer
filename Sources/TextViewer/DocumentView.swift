import SwiftUI

/// Routes a file to the right presentation, and switches to a real editor on
/// ⌘E. Reading and editing are separate modes: formatted by default, plain
/// editable text when you ask for it.
struct DocumentView: View {
    @Binding var text: String
    let encoding: String

    @State private var analysis = Analysis()
    @State private var override: TextKind?
    @State private var isEditing = false

    private static let proseLimit = 200_000

    /// `startEditing` exists so the offscreen renderer can screenshot edit
    /// mode; the app always uses the default.
    init(text: Binding<String>, encoding: String, startEditing: Bool = false) {
        _text = text
        self.encoding = encoding
        _isEditing = State(initialValue: startEditing)
    }

    private var kind: TextKind { override ?? analysis.detected }

    var body: some View {
        Group {
            if !isEditing, kind == .json {
                ContentView(text: text)
            } else {
                VStack(spacing: 0) {
                    content
                    Divider().overlay(Theme.divider.swiftUI)
                    statusBar
                }
            }
        }
        .background(Theme.background.swiftUI)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Toggle(isOn: $isEditing) {
                    Label("Edit", systemImage: isEditing ? "pencil.circle.fill" : "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)
                .help(isEditing ? "Back to formatted view (⌘E)" : "Edit this file (⌘E)")

                Picker("View as", selection: Binding(get: { kind }, set: { override = $0 })) {
                    ForEach(TextKind.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .help("How to display this file")
                .disabled(isEditing)
            }
        }
        .task(id: text) { await recompute() }
        .task(id: override) { await recompute(immediate: true) }
    }

    @ViewBuilder
    private var content: some View {
        if isEditing {
            EditorView(text: text, tokens: analysis.tokens, isEditable: true) { edited in
                text = edited
            }
        } else {
            switch kind {
            case .table:
                if let table = analysis.table {
                    TableTextView(table: table)
                } else {
                    loading
                }
            case .log, .config:
                EditorView(text: text, tokens: analysis.tokens)
            case .plain:
                if analysis.stats.characters <= Self.proseLimit {
                    ProseTextView(text: text)
                } else {
                    // Too long to typeset as one block; line numbers serve better.
                    EditorView(text: text, tokens: [])
                }
            case .json:
                EditorView(text: text, tokens: analysis.tokens)
            }
        }
    }

    private var loading: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.swiftUI)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if isEditing {
                Label("Editing", systemImage: "pencil")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Theme.key.swiftUI)
                dot
            }
            Text(kindLabel)
            dot
            Text(encoding)
            dot
            Text("\(analysis.stats.lines.formatted()) lines")
            dot
            Text("\(analysis.stats.words.formatted()) words")
            dot
            Text("\(analysis.stats.characters.formatted()) characters")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.secondaryText.swiftUI)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Theme.statusBar.swiftUI)
    }

    private var dot: some View {
        Text("·").foregroundStyle(Theme.punctuation.swiftUI)
    }

    private var kindLabel: String {
        guard kind == .table, let table = analysis.table else { return kind.rawValue }
        let columns = max(table.headers.count, table.rows.first?.count ?? 0)
        return "\(analysis.delimiter?.name ?? "Delimited") table · \(table.rows.count.formatted()) × \(columns)"
    }

    /// Analysis runs off the main thread, and typing debounces it, so a long
    /// file is re-detected and re-tokenized without stuttering the editor.
    private func recompute(immediate: Bool = false) async {
        if !immediate {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
        }
        let source = text
        let forced = override
        let computed = await Task.detached(priority: .userInitiated) {
            Analysis.make(text: source, forcedKind: forced)
        }.value
        guard !Task.isCancelled else { return }
        analysis = computed
    }
}

struct Analysis {
    var detected: TextKind = .plain
    var delimiter: Delimiter?
    var stats = TextStats(text: "")
    var table: TextTable?
    var tokens: [Token] = []

    private static let tokenizeLimit = 8_000_000

    static func make(text: String, forcedKind: TextKind?) -> Analysis {
        let detection = TextDetector.detect(text: text)
        let kind = forcedKind ?? detection.kind
        var analysis = Analysis(detected: kind,
                                delimiter: detection.delimiter,
                                stats: TextStats(text: text))
        guard text.count <= tokenizeLimit else { return analysis }

        switch kind {
        case .table:
            let separator = detection.delimiter ?? Delimiter(character: ",", name: "Comma")
            analysis.delimiter = separator
            analysis.table = TextTable.parse(text: text, delimiter: separator)
        case .log:
            analysis.tokens = LineTokenizer.log(text)
        case .config:
            analysis.tokens = LineTokenizer.config(text)
        case .json:
            analysis.tokens = JSONParser.parse(text).tokens
        case .plain:
            break
        }
        return analysis
    }
}

struct TextStats {
    let lines: Int
    let words: Int
    let characters: Int

    init(text: String) {
        characters = text.count
        var lineCount = 0
        text.enumerateLines { _, _ in lineCount += 1 }
        lines = lineCount
        words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }).count
    }
}
