import SwiftUI
import UniformTypeIdentifiers

struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json, .plainText, .text, .log, .commaSeparatedText, .tabSeparatedText, .delimitedText, .data]
    }

    static var writableContentTypes: [UTType] {
        [.plainText, .json, .log, .commaSeparatedText, .tabSeparatedText, .delimitedText]
    }

    var text: String
    var encoding: String

    init(text: String = "", encoding: String = "UTF-8") {
        self.text = text
        self.encoding = encoding
    }

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mdtext", "mdwn", "rmd", "qmd"]

    init(configuration: ReadConfiguration) throws {
        if let name = configuration.file.filename,
           Self.markdownExtensions.contains((name as NSString).pathExtension.lowercased()) {
            throw TextFileDocument.unsupportedMarkdown
        }
        if let markdown = UTType("net.daringfireball.markdown"),
           configuration.contentType.conforms(to: markdown) {
            throw TextFileDocument.unsupportedMarkdown
        }
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoded = TextLoader.decode(data)
        text = decoded.text
        encoding = decoded.encoding
    }

    static let unsupportedMarkdown = NSError(
        domain: "app.textviewer.TextViewer",
        code: 1,
        userInfo: [
            NSLocalizedDescriptionKey: "TextViewer doesn’t open Markdown files.",
            NSLocalizedRecoverySuggestionErrorKey: "Open it with MDHero instead."
        ])

    /// Saves in the encoding the file arrived in — rewriting an LTspice
    /// UTF-16 log as UTF-8 would break the tool that produced it.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: TextLoader.encode(text, as: encoding))
    }
}

@main
struct TextViewerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: TextFileDocument()) { file in
            DocumentView(text: file.$document.text, encoding: file.document.encoding)
        }
        .defaultSize(width: 1120, height: 740)

    }
}
