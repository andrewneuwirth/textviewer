# TextViewer

A small native macOS viewer and editor for text files. JSON gets a
syntax-highlighted source pane and a collapsible tree; other text is detected
and shown in the shape that suits it. ⌘E edits any of it.

| Detected kind | Shown as |
| --- | --- |
| JSON | Source + collapsible tree, filterable |
| Delimited (CSV/TSV/pipe) | Table: sticky header, row numbers, right-aligned numerics |
| Log | Line numbers, colored levels and timestamps |
| Config / INI / requirements | Line numbers, dim comments, colored keys and values |
| Plain prose | Reading view: 14.5pt, comfortable measure, generous leading |

Detection is a guess; the toolbar picker overrides it per window. Encoding is
sniffed too (BOM, then interleaved-zero heuristics) — UTF-8, UTF-16 LE/BE with
or without BOM, Windows-1252. Files are saved back in the encoding they arrived
in, byte-identical when unedited.

## Build

```sh
./build.sh            # builds build/TextViewer.app
./build.sh --install  # builds, then installs to /Applications and re-registers it
```

Requires the Swift toolchain that ships with Xcode. No dependencies.

## Layout

| File | What's in it |
| --- | --- |
| `Sources/TextViewer/JSONParser.swift` | Hand-written parser. Keeps member order (JSONSerialization doesn't), keeps numbers as written, records a token per literal for highlighting, and reports line/column on failure. |
| `Sources/TextViewer/Theme.swift` | Every color, as dynamic light/dark pairs. Change a hex here and both panes follow. |
| `Sources/TextViewer/Highlighter.swift` | Tokens → `NSAttributedString` for the source pane. |
| `Sources/TextViewer/EditorView.swift` | `NSTextView` + line-number ruler, wrapped for SwiftUI. |
| `Sources/TextViewer/TreeView.swift` | Flattens the value into visible rows, renders them, handles expansion and the copy menu. |
| `Sources/TextViewer/ContentView.swift` | Split view, toolbar, status bar. |
| `Sources/TextViewer/App.swift` | Read-only `DocumentGroup`. |
| `Sources/TextViewer/TextAnalysis.swift` | Encoding sniffing, kind detection, delimited-table parsing. |
| `Sources/TextViewer/LineTokenizer.swift` | Log and config tokenizers feeding the same highlighting pipeline as JSON. |
| `Sources/TextViewer/TextViews.swift` | Table and prose presentations. |
| `Sources/TextViewer/DocumentView.swift` | Picks the presentation, owns edit mode and the status bar. |
| `Sources/QuickLook/` | The Quick Look extension: same parser and rows, its own bundle and entry point. |

## Notes

- ⌘E switches between the formatted view and a plain editable text editor;
  ⌘S saves, undo works, and macOS autosaves as it does for any document app.
- Opens collapsed: the root's members are listed, everything below waits for a
  chevron or Expand All (⌘⌥E / ⌘⌥W).
- ⌘⇧F filters the tree by key or value; ancestors of a match open automatically
  and matches are highlighted. ⌘F is the source pane's own find bar.
- Right-click a tree row to copy its value, its path (`$.client[0].api_key`), or its key.
- The split position is remembered across launches (`splitFraction` in UserDefaults).
- Large files: a 4.3 MB / 192k-property file parses in ~0.14s and opens in under a
  second. Only the visible window is syntax-colored (temporary attributes, not a
  giant attributed string), which keeps that file at ~47 MB of document memory
  instead of ~123 MB.

## Quick Look

Spacebar in Finder renders the tree instead of raw text. macOS requires the
extension to be switched on by hand, once:

System Settings → General → Login Items & Extensions → Quick Look → tick **TextViewer**.

Check registration with `pluginkit -mAvvv -p com.apple.quicklook.preview | grep -A3 TextViewer`.

## Default handler

```sh
duti -s app.textviewer.TextViewer public.json all   # make it the .json app
duti -x json                                            # check what's bound now
```
