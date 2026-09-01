# Marka

A native macOS Markdown editor with Typora-style inline WYSIWYG rendering.
Swift, AppKit, TextKit 2. No Electron.

## Run

```sh
swift run Marka
```

## Test

With full Xcode installed, `swift test` is enough. With Command Line Tools only,
the Testing framework needs explicit search paths:

```sh
swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## Status

Rendered in place: headings, bold, italic, bold-italic, strikethrough, inline
code, links, list markers, task lists, blockquotes, fenced code blocks, and
horizontal rules. Syntax markers reveal when the caret enters a span and hide
when it leaves. Styling is incremental: only the edited paragraphs restyle on
a keystroke, with a full pass when fence boundaries change.

Editing: Enter continues a list (ordered numbers increment, task boxes reset
to unchecked), Enter on an empty item ends the list, Tab / Shift-Tab indents,
and brackets, quotes and markdown markers auto-pair or wrap the selection.

Menus and shortcuts: Cmd+O open, Cmd+S save, Shift+Cmd+S save as, Cmd+P print.
File > Export writes PDF, standalone HTML (MathJax and mermaid load from a CDN
only when the document uses them), or Word .docx (converted from the HTML, so
math stays as raw TeX there). Cmd+B/I/E/K formatting, Shift+Cmd+X strikethrough,
Cmd+1..6 headings, Cmd+0 paragraph. Cmd+/ source mode, Shift+Cmd+O outline
sidebar (click a heading to jump), Shift+Cmd+F focus mode, Shift+Cmd+T
typewriter mode. Word count sits in the status bar.

Fenced code blocks highlight via tree-sitter (CodeEditLanguages grammars,
language tag on the fence picks the grammar). Table rows style in place:
pipes dim, the header row above a separator goes bold. Pasting an image
saves a PNG (into assets/ next to the file, or the temp folder for unsaved
documents), inserts the markdown reference, and an image-only line renders
the picture inline; the raw markdown comes back when the caret enters it.

Set MARKA_SNAPSHOT=/path/out.png to launch, write a window snapshot, and
quit (used for automated visual checks).

LaTeX math renders through SwiftMath, natively, with no web view: `$E = mc^2$`
inline and `$$ ... $$` on its own line as a centered equation. A `$5` price or
a `` `$x$` `` code span stays literal text.

Mermaid diagrams render in a hidden WKWebView from a vendored copy of
mermaid 11.15.0, so no network access is needed. A ```` ```mermaid ```` fence
collapses to the rendered diagram; put the caret inside to edit the source.
Rendered diagrams are cached per source and per light/dark appearance.

The app bundle carries the icon and claims `.md` and `.txt` files:

```sh
scripts/make-app.sh          # build/Marka.app, release by default
open build/Marka.app
```

Documents use NSDocument, so multiple windows, tabs, Open Recent, and the
standard save and revert flows work.

The sidebar (Shift+Cmd+O) has two panes: Outline lists the headings, Files
browses the folder of the open document (markdown and text files plus
subfolders; click a file to open it).

View > Theme switches themes. Built in: Default (follows the system
appearance), GitHub, Night, and Newsprint (Georgia on sepia). A theme sets
fonts, editor colors, code token colors, and the window appearance, and the
choice persists across launches. Drop a JSON file into
`~/Library/Application Support/Marka/Themes/` (View > Theme > Open Themes
Folder) to add your own:

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

Not built yet: LaTeX/epub export (needs pandoc), multi-line `$$` blocks, and true
hidden-marker layout for text spans (markers currently
shrink to a 0.01pt clear font).
