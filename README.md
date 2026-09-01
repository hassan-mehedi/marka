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

Early. Rendered in place: headings, bold, italic, bold-italic, strikethrough,
inline code, links, list markers, blockquotes, fenced code blocks, and
horizontal rules. Syntax markers reveal when the caret enters a span and hide
when it leaves. Styling is incremental: only the edited paragraphs restyle on
a keystroke, with a full pass when fence boundaries change. Cmd+O opens a
file, Cmd+S / Shift+Cmd+S saves.

Not built yet: tables, images, math, Mermaid, export, themes, true
hidden-marker layout (markers currently shrink to a 0.01pt clear font).
