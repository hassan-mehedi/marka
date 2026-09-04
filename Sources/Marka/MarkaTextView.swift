import AppKit
import UniformTypeIdentifiers

@MainActor
final class MarkaTextView: NSTextView {
    var onPasteImage: ((Data) -> Bool)?
    // The delegate supplies completions; the completed range grows to include
    // the ":" that opened an emoji shortcode or the fence backticks.
    var completionRange: ((NSRange) -> NSRange)?

    override var rangeForUserCompletion: NSRange {
        let base = super.rangeForUserCompletion
        return completionRange?(base) ?? base
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        let text = flag ? Completions.insertion(for: word) : word
        super.insertCompletion(text, forPartialWordRange: charRange, movement: movement, isFinal: flag)
    }
    // Returns false when the caret sits somewhere HTML must stay literal.
    var acceptsMarkdownPaste: (() -> Bool)?

    override func paste(_ sender: Any?) {
        if let data = Self.imageData(from: .general), onPasteImage?(data) == true {
            return
        }
        if let markdown = Self.markdown(from: .general), acceptsMarkdownPaste?() ?? true {
            insertText(markdown, replacementRange: selectedRange())
            return
        }
        if let plain = NSPasteboard.general.string(forType: .string), plain.contains("\r") {
            insertText(plain.replacingOccurrences(of: "\r\n", with: "\n"), replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }

    // Rich clipboard content converted to Markdown. Text copied from a plain
    // editor carries no HTML and passes through untouched.
    static func markdown(from pasteboard: NSPasteboard) -> String? {
        guard pasteboard.availableType(from: [.html]) != nil,
              let html = pasteboard.string(forType: .html) else { return nil }
        let markdown = HTMLToMarkdown.markdown(from: html)
        guard !markdown.isEmpty else { return nil }
        if let plain = pasteboard.string(forType: .string),
           plain.trimmingCharacters(in: .whitespacesAndNewlines) == markdown {
            return nil
        }
        return markdown
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.hasImage(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.hasImage(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if Self.hasImage(sender.draggingPasteboard),
           let data = Self.imageData(from: sender.draggingPasteboard) {
            let point = convert(sender.draggingLocation, from: nil)
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
            if onPasteImage?(data) == true {
                return true
            }
        }
        return super.performDragOperation(sender)
    }

    static func hasImage(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.availableType(from: [.png, .tiff]) != nil {
            return true
        }
        return imageFileURL(on: pasteboard) != nil
    }

    private static func imageFileURL(on pasteboard: NSPasteboard) -> URL? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let url = urls.first,
              let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image) else { return nil }
        return url
    }

    static func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) {
            return png
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        if let url = imageFileURL(on: pasteboard) {
            return try? Data(contentsOf: url)
        }
        return nil
    }
}
