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
    private static let renderTimeout: Duration = .seconds(8)

    private var states: [String: State] = [:]
    // One page with mermaid loaded once; diagrams render through it in turn.
    private var webView: WKWebView?
    private var pageReady: Task<Bool, Never>?
    private var queue: Task<Void, Never>?

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
            enqueue(source: source, dark: dark, key: key)
            return nil
        case nil:
            states[key] = .rendering([onReady])
            enqueue(source: source, dark: dark, key: key)
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

    private func enqueue(source: String, dark: Bool, key: String) {
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let result = await render(source: source, dark: dark)
            finish(key, with: result)
        }
    }

    private func render(source: String, dark: Bool) async -> Result<NSImage, RenderError> {
        guard let webView = await readyWebView() else { return .failure(.rejected) }
        webView.frame = NSRect(x: 0, y: 0, width: 1200, height: 900)

        let size: (width: Double, height: Double)?
        do {
            size = try await withTimeout(Self.renderTimeout) {
                let value = try await webView.callAsyncJavaScript(
                    Self.renderScript,
                    arguments: ["source": source, "dark": dark],
                    contentWorld: .page
                )
                guard let dictionary = value as? [String: Any],
                      let width = dictionary["width"] as? Double,
                      let height = dictionary["height"] as? Double
                else { return nil }
                return (width, height)
            }
        } catch is TimeoutError {
            return .failure(.timedOut)
        } catch {
            return .failure(.rejected)
        }

        guard let size, size.width > 1, size.height > 1 else { return .failure(.rejected) }
        let (width, height) = size
        webView.frame = NSRect(x: 0, y: 0, width: ceil(width), height: ceil(height))
        try? await Task.sleep(for: .milliseconds(80))

        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        guard let image = try? await webView.takeSnapshot(configuration: configuration) else { return .failure(.timedOut) }
        _ = try? await webView.evaluateJavaScript("document.getElementById('out').innerHTML = ''; 0")
        return .success(image)
    }

    private func readyWebView() async -> WKWebView? {
        if let webView, await pageReady?.value == true { return webView }
        guard let script = loadScript() else { return nil }

        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.page(script: script), baseURL: nil)
        self.webView = webView
        let ready = Task { () -> Bool in
            for _ in 0..<200 {
                try? await Task.sleep(for: .milliseconds(50))
                let loaded = try? await webView.evaluateJavaScript("typeof __esbuild_esm_mermaid_nm !== 'undefined'")
                if loaded as? Bool == true { return true }
            }
            return false
        }
        pageReady = ready
        guard await ready.value else {
            self.webView = nil
            pageReady = nil
            return nil
        }
        return webView
    }

    private struct TimeoutError: Error {}

    private func withTimeout<T: Sendable>(_ duration: Duration, _ work: @escaping @MainActor () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw TimeoutError()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private func loadScript() -> String? {
        guard let url = Bundle.module.url(forResource: "mermaid.min", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return text
    }

    private static let renderScript = """
    const ns = __esbuild_esm_mermaid_nm.mermaid;
    const mermaid = ns.default ?? ns;
    mermaid.initialize({
      startOnLoad: false,
      theme: dark ? 'dark' : 'default',
      flowchart: { useMaxWidth: false },
      sequence: { useMaxWidth: false },
      gantt: { useMaxWidth: false },
      class: { useMaxWidth: false },
      state: { useMaxWidth: false },
      pie: { useMaxWidth: false },
    });
    window.markaCounter = (window.markaCounter ?? 0) + 1;
    const { svg } = await mermaid.render('marka-diagram-' + window.markaCounter, source);
    const out = document.getElementById('out');
    out.innerHTML = svg;
    const rect = out.getBoundingClientRect();
    return { width: rect.width, height: rect.height };
    """

    private static func page(script: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
          html, body { margin: 0; padding: 0; background: transparent; }
          #out { display: inline-block; width: max-content; padding: 8px; }
        </style>
        </head>
        <body><div id="out"></div>
        <script>\(script)</script>
        </body></html>
        """
    }
}
