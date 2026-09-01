import AppKit
import Testing
@testable import Marka

@Test @MainActor func pasteboardImageDetectionAndExtraction() throws {
    let pasteboard = NSPasteboard(name: .init("marka-test-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }

    pasteboard.clearContents()
    #expect(!MarkaTextView.hasImage(pasteboard))
    #expect(MarkaTextView.imageData(from: pasteboard) == nil)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )
    let png = try #require(rep?.representation(using: .png, properties: [:]))
    pasteboard.setData(png, forType: .png)
    #expect(MarkaTextView.hasImage(pasteboard))
    #expect(MarkaTextView.imageData(from: pasteboard) == png)

    pasteboard.clearContents()
    pasteboard.setString("plain text", forType: .string)
    #expect(!MarkaTextView.hasImage(pasteboard))
}
