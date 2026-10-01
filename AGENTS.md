# AGENTS.md: TextViewer

A native macOS viewer/editor for text files. JSON gets a syntax-highlighted source pane plus a collapsible, filterable tree; CSV/TSV, logs, config files and prose are detected and shown in a fitting layout. ⌘E edits any of it. Ships a Quick Look extension.

## Stack

- Swift 5.9 tools, SwiftPM, macOS 14+, SwiftUI + AppKit. No dependencies. Bundle id `app.textviewer.TextViewer`.
- App target `TextViewer` (`Sources/TextViewer/`) built by SwiftPM. The Quick Look extension `TextViewerQuickLook` (`Sources/QuickLook/`) is **not** a SwiftPM target: `build.sh` compiles it with `swiftc` from `JSONParser.swift`, `Theme.swift`, `TreeView.swift` plus `Sources/QuickLook/*.swift`. If those shared files gain a dependency on another app file, add it to the `swiftc` line too.
- Resources: `Resources/Info.plist`, `Resources/TextViewer.icns`, `Resources/QuickLook/{Info.plist,QuickLook.entitlements}` (the sandbox entitlement PlugInKit requires).

## Commands

```sh
swift build                 # quick compile check of the app
./build.sh                  # build/TextViewer.app with the .appex, ad-hoc signed (nested first)
./build.sh --install        # replace /Applications/TextViewer.app, lsregister, pluginkit -a
```

Only install when Andrew asks. No tests.

## Where data lives

- No app data. `splitFraction` (split position) is in UserDefaults. Files are saved back in the encoding they arrived in, byte-identical when unedited; keep that.

## Code map

- `JSONParser.swift`: hand-written parser that keeps member order and numbers as written, with tokens for highlighting and line/column errors.
- `TextAnalysis.swift`: encoding sniffing (BOM, interleaved zeros; UTF-8, UTF-16 LE/BE, Windows-1252), kind detection, delimited parsing.
- `Highlighter.swift`, `LineTokenizer.swift`, `Theme.swift` (all colours, light/dark pairs), `EditorView.swift`, `TreeView.swift`, `TextViews.swift`, `DocumentView.swift`, `ContentView.swift`, `App.swift`, `DefaultHandler.swift`.

## Rules

- Large files: only the visible range is syntax-coloured (temporary attributes). Don't switch to one giant attributed string.
- Detection is a guess; the toolbar picker overrides it per window.
