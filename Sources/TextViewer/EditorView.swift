import AppKit
import SwiftUI

/// Read-only source pane: highlighted text with a line-number gutter.
struct EditorView: NSViewRepresentable {
    let text: String
    let tokens: [Token]
    var isEditable: Bool = false
    var onChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.background

        // TextKit 1 by construction: the ruler needs a layout manager, and a
        // plain NSTextView() would hand us a TextKit 2 view instead.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        // Multi-megabyte files stay responsive because layout happens lazily,
        // in the background, only for what is on screen.
        layoutManager.allowsNonContiguousLayout = true
        layoutManager.backgroundLayoutEnabled = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = Theme.background
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textStorage?.setAttributedString(Highlighter.baseStorage(for: text))
        textView.typingAttributes = [
            .font: Fonts.editor,
            .foregroundColor: Theme.primaryText
        ]

        scrollView.documentView = textView

        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.onChange = onChange
        context.coordinator.tokens = tokens
        context.coordinator.observe(scrollView: scrollView)
        DispatchQueue.main.async { context.coordinator.refreshHighlighting() }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.onChange = onChange
        textView.isEditable = isEditable
        // Never stamp the binding's value back over what is being typed; the
        // text view is the source of truth while it holds the edit.
        if textView.textStorage?.string != text, !context.coordinator.isApplyingEdit {
            textView.textStorage?.setAttributedString(Highlighter.baseStorage(for: text))
            context.coordinator.replaceTokens(tokens)
        } else if context.coordinator.tokenCount != tokens.count {
            // Log and config tokens are produced off the main thread and land
            // after the first layout; without this they would never be applied.
            context.coordinator.replaceTokens(tokens)
        }
        context.coordinator.ruler?.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var textView: NSTextView?
        var onChange: ((String) -> Void)?
        private(set) var isApplyingEdit = false
        var ruler: LineNumberRulerView?
        var tokens: [Token] = []
        var coloredRange: NSRange?
        var tokenCount: Int { tokens.count }
        private var observers: [NSObjectProtocol] = []

        func replaceTokens(_ newTokens: [Token]) {
            if let layoutManager = textView?.layoutManager, let previous = coloredRange {
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: previous)
            }
            tokens = newTokens
            coloredRange = nil
            refreshHighlighting()
        }

        /// Re-colors the visible window plus a margin, so ordinary scrolling
        /// never outruns the highlighting.
        func refreshHighlighting() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  let visibleRect = textView.enclosingScrollView?.contentView.bounds else { return }

            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let margin = 8_000
            let start = max(0, charRange.location - margin)
            let length = min((textView.textStorage?.length ?? 0) - start, charRange.length + margin * 2)
            guard length > 0 else { return }

            let target = NSRange(location: start, length: length)
            if let coloredRange, NSEqualRanges(coloredRange, target) { return }
            Highlighter.colorize(tokens: tokens, layoutManager: layoutManager,
                                 range: target, clearing: coloredRange)
            coloredRange = target
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isApplyingEdit = true
            onChange?(textView.string)
            isApplyingEdit = false
            ruler?.needsDisplay = true
            refreshHighlighting()
        }

        func observe(scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            let redraw: (Notification) -> Void = { [weak self] _ in
                self?.ruler?.needsDisplay = true
                self?.refreshHighlighting()
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView, queue: .main, using: redraw))
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.documentView, queue: .main, using: redraw))
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

final class LineNumberRulerView: NSRulerView {
    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 52
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              let contentView = scrollView?.contentView else { return }

        Theme.gutter.setFill()
        bounds.fill()
        Theme.divider.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        let text = textView.string as NSString
        let visibleRect = contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        var lineNumber = 1
        if charRange.location > 0 {
            text.enumerateSubstrings(in: NSRange(location: 0, length: charRange.location),
                                    options: [.byLines, .substringNotRequired]) { _, _, _, _ in
                lineNumber += 1
            }
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: Fonts.editorSize - 1.5, weight: .regular),
            .foregroundColor: Theme.lineNumber
        ]
        let inset = textView.textContainerInset.height

        var index = charRange.location
        let end = NSMaxRange(charRange)
        while index < end {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex,
                                                          effectiveRange: nil,
                                                          withoutAdditionalLayout: false)
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attributes)
            let y = lineRect.minY + inset - visibleRect.minY + 1
            label.draw(at: NSPoint(x: ruleThickness - size.width - 12, y: y), withAttributes: attributes)

            lineNumber += 1
            if lineRange.length == 0 { break }
            index = NSMaxRange(lineRange)
        }
    }
}
