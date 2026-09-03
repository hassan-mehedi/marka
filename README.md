# Marka

A native macOS Markdown editor with Typora-style inline WYSIWYG rendering.
Swift, AppKit, TextKit 2. No Electron, no web view for the editor itself.

## Features

- Live inline rendering: headings, bold, italic, strikethrough, inline code,
  links, lists, task lists, blockquotes, tables, horizontal rules, and YAML
  front matter style themselves as you type. Syntax markers take zero width
  on lines the caret is not in and reveal when the caret enters a span.
- Fenced code blocks render as padded boxes with a language label and
  highlight through tree-sitter grammars, picked by the language tag on the
  fence. Tables render as bordered grids with wrapping cells and column
  alignment; put the caret inside either to edit the source.
- LaTeX math renders natively through SwiftMath: `$E = mc^2$` inline,
  `$$ ... $$` as a centered block equation. A `$5` price stays literal.
- Mermaid diagrams render offline from a vendored mermaid 11.15.0 in a
  hidden WKWebView. Put the caret inside a diagram to edit its source.
- Images paste or drag in as a saved PNG plus a markdown reference, and an
  image-only line shows the picture inline. Remote `https://` images load in
  the background.
- `[TOC]` renders a clickable table of contents. Footnotes render as raised
  superscripts with dimmed definition lines.
- Export to PDF, standalone HTML, Word .docx, epub, and LaTeX. Epub and
  LaTeX go through pandoc (`brew install pandoc`); the rest is native.
  File > Import converts docx, odt, html, epub, rst, LaTeX, and more to
  Markdown through pandoc.
- Themes: Default, GitHub, GitHub Dark, Dracula, One Dark Pro, Night, and
  Newsprint built in, plus JSON user themes in `~/Library/Application Support/Marka/Themes/`.
- Format menu covers lists, task lists, blockquotes, code fences, tables,
  images, math blocks, footnotes, and rules. Inside a table, Tab moves
  between cells, Return adds a row, and Format > Table adds, moves, aligns,
  and deletes rows and columns.
- Type `:smi` for an emoji picker or three backticks plus a few letters for
  a language picker; Return accepts, Esc dismisses.
- Pasting HTML from a browser or word processor converts it to Markdown;
  Paste as Plain Text and Copy as HTML sit in the Edit menu.
- Settings (Cmd+,) for editor and code fonts, maximum line width, the image
  folder, spell check, autocorrect, and autosave. Zoom with Cmd+Shift+= and
  Cmd+Shift+-.
- Sidebar with outline, file tree, and folder search panes (Cmd+Shift+F),
  Quick Open fuzzy file switcher (Cmd+Shift+O), source mode, focus mode,
  typewriter mode, smart punctuation, native find and replace, word count
  with a stats popover.
- NSDocument under the hood, so tabs, Open Recent, autosave-style revert,
  and multiple windows work the way macOS users expect. Tabs draw as rounded,
  bordered pills in the theme colors; the strip appears once a window holds
  two or more tabs, and middle-click closes a tab.

## Install

Download the dmg for your Mac from the
[releases page](https://github.com/hassan-mehedi/marka/releases):
`arm64` for Apple Silicon, `x86_64` for Intel. Drag Marka.app into
Applications.

Releases built without a Developer ID are ad-hoc signed, not notarized,
so the first launch is blocked with "Marka is damaged" or "unidentified
developer". Clear the quarantine flag once and it opens normally:

```sh
xattr -d com.apple.quarantine /Applications/Marka.app
```

Notarized releases open without that step. See Releasing below.

## Requirements

- macOS 14 or later
- Swift 6.1+ toolchain (full Xcode or Command Line Tools)
- pandoc, only for the epub and LaTeX exports

## Build and run

```sh
swift run Marka          # run straight from SwiftPM
scripts/make-app.sh      # build/Marka.app with icon and file associations
open build/Marka.app
```

`make-app.sh` builds release by default; pass `debug` for a debug bundle.
It ad-hoc signs the bundle so Gatekeeper lets it launch locally.

## Test

With full Xcode installed, `swift test` is enough. With Command Line Tools
only, the Testing framework needs explicit search paths:

```sh
swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

For visual checks without a human, launch with `MARKA_SNAPSHOT=/path/out.png`
and the app writes a window snapshot and quits. `MARKA_SAMPLE=1` loads a
sample document first, `MARKA_SIDEBAR=files` opens the file tree pane,
`MARKA_SNAPSHOT_CARET=<offset>` places the caret before capturing,
`MARKA_SNAPSHOT_TABS=1` opens a second tab, `MARKA_SNAPSHOT_FRAME=1`
captures the window frame including the title bar, `MARKA_SNAPSHOT_SETTINGS=1`
and `MARKA_SNAPSHOT_QUICKOPEN=1` open those panels, and
`MARKA_SNAPSHOT_SEARCH=<query>` runs a folder search in the sidebar.

## Releasing

Pushing a `v*` tag runs `.github/workflows/release.yml`, which tests,
builds both dmgs, and publishes a GitHub release. With these repository
secrets set, the build is Developer ID signed with the hardened runtime,
notarized, and stapled:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | base64 of a "Developer ID Application" .p12 export |
| `MACOS_CERTIFICATE_PASSWORD` | password chosen when exporting the .p12 |
| `APPLE_ID` | Apple ID email of the developer account |
| `APPLE_TEAM_ID` | 10-character team id |
| `APPLE_APP_PASSWORD` | app-specific password from appleid.apple.com |

Export the certificate from Keychain Access and encode it with
`base64 -i cert.p12 | pbcopy`. Locally, `MARKA_SIGN_IDENTITY="Developer ID
Application: Name (TEAMID)" scripts/make-dmg.sh v1.2.3 arm64` does the same
signing; add `MARKA_APPLE_ID`, `MARKA_TEAM_ID`, and `MARKA_APP_PASSWORD` to
notarize.

## How it works

The app is a SwiftPM executable target, no xcodeproj. `scripts/make-app.sh`
wraps the binary into an app bundle, copies resource bundles, generates the
icon with `scripts/make-icon.swift`, and ad-hoc signs it.

The editor is one NSTextView on TextKit 2. Three layers cooperate:

- `MarkdownParser` is pure functions from a line (or the whole text) to
  structure: block kind, inline spans, fences, math blocks, front matter,
  footnotes, outline. It holds no state, which is what makes it testable.
- `MarkdownHighlighter` styles text storage attributes incrementally from
  `NSTextStorageDelegate`. A keystroke restyles only the edited paragraphs;
  a full pass runs only when fence, math block, or front matter boundaries
  change. Colors and fonts come from the active `Theme`.
- `EditorViewController` implements `NSTextContentStorageDelegate` and
  substitutes display paragraphs: marker characters drop out entirely on
  paragraphs the caret is not in, inline math becomes an image attachment,
  image-only lines become the picture, mermaid fences collapse to the
  rendered diagram. When a click lands in a substituted paragraph, the
  display column maps back to the source offset so the caret is placed
  correctly (`displayReplacements` / `sourceOffset`).

The document text is always the plain markdown source. Rendering never
mutates it; only the display layer differs. That single invariant is why
source mode, export, and save need no conversion step.

Supporting pieces: `MathRenderer` (SwiftMath, cached per color and size),
`MermaidRenderer` (offscreen WKWebView, cached per source and appearance),
`CodeHighlighter` (tree-sitter via CodeEditLanguages), `HTMLExporter`
(hand-rolled markdown to HTML for the HTML, PDF, and docx exports),
`PandocExporter` (Process wrapper), `Theme`/`ThemeManager`, and the
NSDocument plumbing in `MarkaDocument`.

## Contributing

Bug reports with a minimal markdown snippet that misrenders are the most
useful thing you can send.

For code changes:

1. Keep `MarkdownParser` pure. New syntax support starts there, with tests,
   before any UI wiring.
2. Match the existing style: no comments where the code already says it,
   `nonisolated static` for logic tests need to call, theme colors through
   `Theme` accessors, never hard-coded NSColors in the highlighter.
3. Run the test suite (see above) and add tests beside the feature:
   parser logic in `MarkdownParserTests`, display substitution in
   `HiddenMarkerTests`, export in `HTMLExporterTests`.
4. For anything visual, attach a `MARKA_SNAPSHOT` capture to the PR.
5. One feature per commit, imperative subject line, no attribution lines.

The codebase is small on purpose (about 3,000 lines of app code). Prefer
extending an existing type over adding a new abstraction.

## Releases

Pushing a tag like `v0.2.0` runs `.github/workflows/release.yml`: it tests,
builds an arm64 and an x86_64 dmg with `scripts/make-dmg.sh`, and publishes
both on a GitHub release. The tag becomes the bundle version. Build a dmg
locally with `scripts/make-dmg.sh 0.2.0 arm64`.

## Themes

Drop a JSON file into `~/Library/Application Support/Marka/Themes/`
(View > Theme > Open Themes Folder):

```json
{
  "name": "My Theme",
  "appearance": "dark",
  "font": "Avenir Next",
  "fontSize": 17,
  "background": "#1e2030",
  "text": "#c8d3f5",
  "accent": "#82aaff",
  "tokens": { "keyword": "#c099ff", "string": "#c3e88d" }
}
```

Every key except `name` is optional; missing values fall back to the
system appearance.
