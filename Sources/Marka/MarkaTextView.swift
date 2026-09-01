import AppKit
import UniformTypeIdentifiers

@MainActor
final class MarkaTextView: NSTextView {
    var onPasteImage: ((Data) -> Bool)?

    override func paste(_ sender: Any?) {
        if let data = Self.imageData(from: .general), onPasteImage?(data) == true {
            return
        }
        super.paste(sender)
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
