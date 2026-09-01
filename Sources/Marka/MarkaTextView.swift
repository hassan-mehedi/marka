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

    private static func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) {
            return png
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first,
           let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .image) {
            return try? Data(contentsOf: url)
        }
        return nil
    }
}
