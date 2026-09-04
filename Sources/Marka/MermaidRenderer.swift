import AppKit
import WebKit

@MainActor
final class MermaidRenderer: NSObject {
    static let shared = MermaidRenderer()

    private enum State {
        case rendering([() -> Void])
        case done(NSImage)
        case failed(retryAfter: Date?)
    }

    private static let retryInterval: TimeInterval = 10

    private var states: [String: State] = [:]
    private var webView: WKWebView?
    private var script: String?
    private var pendingSource: String?

    /// Returns the rendered diagram, or nil while it is still rendering or if it failed.
    /// `onReady` fires once when the render finishes, for every caller that
    /// asked while it was in flight. A failure is retried after a pause.
    func image(for source: String, dark: Bool, onReady: @escaping () -> Void) -> NSImage? {
        let key = "\(dark ? "dark" : "light")\n\(source)"
        switch states[key] {
        case let .done(image):
            return image
        case let .rendering(waiters):
            states[key] = .rendering(waiters + [onReady])
            return nil
        case let .failed(retryAfter):
            guard let retryAfter, Date() >= retryAfter else { return nil }
            states[key] = .rendering([onReady])
            render(source: source, dark: dark, key: key)
            return nil
        case nil:
            states[key] = .rendering([onReady])
            render(source: source, dark: dark, key: key)
            return nil
        }
    }

    func clearCache() {
        states.removeAll()
    }

    // A diagram mermaid rejected stays failed; a timeout retries after a pause.
    private func finish(_ key: String, with result: Result<NSImage, RenderError>) {
        let waiters: [() -> Void]
        if case let .rendering(pending) = states[key] { waiters = pending } else { waiters = [] }
        switch result {
        case let .success(image): states[key] = .done(image)
        case .failure(.rejected): states[key] = .failed(retryAfter: nil)
        case .failure(.timedOut): states[key] = .failed(retryAfter: Date().addingTimeInterval(Self.retryInterval))
        }
        waiters.forEach { $0() }
    }

    private enum RenderError: Error {
        case rejected
        case timedOut
    }

    private func render(source: String, dark: Bool, key: String) {
        guard let script = loadScript() else {
            finish(key, with: .failure(.rejected))
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
            let result = await Self.snapshot(from: webView)
            self.webView = nil
            self.finish(key, with: result)
        }
    }

    private static func snapshot(from webView: WKWebView) async -> Result<NSImage, RenderError> {
        // Poll until mermaid reports the SVG size, then match the view to it.
        for _ in 0..<80 {
            try? await Task.sleep(for: .milliseconds(50))
            let result = try? await webView.evaluateJavaScript("window.markaSize")
            guard let size = result as? [String: Any] else { continue }
            if size["error"] != nil { return .failure(.rejected) }
            guard let width = size["width"] as? Double,
                  let height = size["height"] as? Double,
                  width > 1, height > 1
            else { continue }

            webView.frame = NSRect(x: 0, y: 0, width: ceil(width), height: ceil(height))
            try? await Task.sleep(for: .milliseconds(80))

            let configuration = WKSnapshotConfiguration()
            configuration.rect = webView.bounds
            guard let image = try? await webView.takeSnapshot(configuration: configuration) else { return .failure(.timedOut) }
            return .success(image)
        }
        return .failure(.timedOut)
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
