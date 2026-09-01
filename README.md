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

Menus and shortcuts: Cmd+O open, Cmd+S save, Shift+Cmd+S save as, Cmd+P print,
File > Export as PDF. Cmd+B/I/E/K formatting, Shift+Cmd+X strikethrough,
Cmd+1..6 headings, Cmd+0 paragraph. Cmd+/ source mode, Shift+Cmd+O outline
sidebar (click a heading to jump), Shift+Cmd+F focus mode, Shift+Cmd+T
typewriter mode. Word count sits in the status bar.

Not built yet: tables, images, math, Mermaid, code syntax highlighting,
docx/LaTeX/epub export, themes, and true hidden-marker layout (markers
currently shrink to a 0.01pt clear font).
