import AppKit
import WebKit

@MainActor
final class MermaidRenderer: NSObject {
    static let shared = MermaidRenderer()

    private enum State {
        case rendering
        case done(NSImage)
        case failed
    }

    private var states: [String: State] = [:]
    private var webView: WKWebView?
    private var script: String?
    private var pendingSource: String?

    /// Returns the rendered diagram, or nil while it is still rendering or if it failed.
    /// `onReady` fires once when a render this call started finishes.
    func image(for source: String, dark: Bool, onReady: @escaping () -> Void) -> NSImage? {
        let key = "\(dark ? "dark" : "light")\n\(source)"
        switch states[key] {
        case let .done(image):
            return image
        case .rendering, .failed:
            return nil
        case nil:
            states[key] = .rendering
            render(source: source, dark: dark, key: key, onReady: onReady)
            return nil
        }
    }

    func clearCache() {
        states.removeAll()
    }

    private func render(source: String, dark: Bool, key: String, onReady: @escaping () -> Void) {
        guard let script = loadScript() else {
            states[key] = .failed
            return
        }

        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView

        let html = Self.page(script: script, source: source, dark: dark)
        webView.loadHTMLString(html, baseURL: nil)

        Task { [weak self] in
            guard let self else { return }
            let image = await Self.snapshot(from: webView)
            if let image {
                self.states[key] = .done(image)
            } else {
                self.states[key] = .failed
            }
            self.webView = nil
            onReady()
        }
    }

    private static func snapshot(from webView: WKWebView) async -> NSImage? {
        // Poll until mermaid reports the SVG size, then match the view to it.
        for _ in 0..<80 {
            try? await Task.sleep(for: .milliseconds(50))
            let result = try? await webView.evaluateJavaScript("window.markaSize")
            guard let size = result as? [String: Any],
                  let width = size["width"] as? Double,
                  let height = size["height"] as? Double,
                  width > 1, height > 1
            else { continue }

            webView.frame = NSRect(x: 0, y: 0, width: ceil(width), height: ceil(height))
            try? await Task.sleep(for: .milliseconds(80))

            let configuration = WKSnapshotConfiguration()
            configuration.rect = webView.bounds
            return try? await webView.takeSnapshot(configuration: configuration)
        }
        return nil
    }

    private func loadScript() -> String? {
        if let script { return script }
        guard let url = Bundle.module.url(forResource: "mermaid.min", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        script = text
        return text
    }

    private static func page(script: String, source: String, dark: Bool) -> String {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
          html, body { margin: 0; padding: 0; background: transparent; }
          #out { display: inline-block; width: max-content; padding: 8px; }
        </style>
        </head>
        <body><div id="out"></div>
        <script>\(script)</script>
        <script>
        (async () => {
          try {
            const ns = __esbuild_esm_mermaid_nm.mermaid;
            const mermaid = ns.default ?? ns;
            mermaid.initialize({
              startOnLoad: false,
              theme: \(dark ? "'dark'" : "'default'"),
              flowchart: { useMaxWidth: false },
              sequence: { useMaxWidth: false },
              gantt: { useMaxWidth: false },
              class: { useMaxWidth: false },
              state: { useMaxWidth: false },
              pie: { useMaxWidth: false },
            });
            const { svg } = await mermaid.render('marka-diagram', `\(escaped)`);
            const out = document.getElementById('out');
            out.innerHTML = svg;
            const rect = out.getBoundingClientRect();
            window.markaSize = { width: rect.width, height: rect.height };
          } catch (error) {
            window.markaSize = { width: 0, height: 0, error: String(error) };
          }
        })();
        </script>
        </body></html>
        """
    }
}
