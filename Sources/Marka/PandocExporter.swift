import Foundation

enum PandocExporter {
    // Formats File > Import accepts, keyed by file extension.
    static let importFormats: [String: String] = [
        "docx": "docx", "odt": "odt", "html": "html", "htm": "html", "epub": "epub",
        "rst": "rst", "tex": "latex", "org": "org", "textile": "textile", "rtf": "rtf", "ipynb": "ipynb",
    ]

    static func importMarkdown(from url: URL) throws -> String {
        guard let pandoc = pandocURL else { throw missingPandoc }
        guard let format = importFormats[url.pathExtension.lowercased()] else {
            throw NSError(
                domain: "Marka",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Marka cannot import .\(url.pathExtension) files."]
            )
        }
        let process = Process()
        process.executableURL = pandoc
        process.arguments = ["--from", format, "--to", "gfm", "--wrap=none", url.path]
        process.currentDirectoryURL = url.deletingLastPathComponent()
        let result = try run(process, input: nil)
        guard result.status == 0 else { throw failure(result) }
        return String(decoding: result.output, as: UTF8.self)
    }

    private static let ignoresSIGPIPE: Void = { signal(SIGPIPE, SIG_IGN) }()

    // Drains stderr and feeds stdin on other threads while stdout is read
    // here, so a chatty or early-exiting pandoc cannot stall on a full pipe.
    private static func run(_ process: Process, input: Data?) throws -> (status: Int32, output: Data, errors: Data) {
        _ = ignoresSIGPIPE
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let stdin = input == nil ? nil : Pipe()
        if let stdin { process.standardInput = stdin }
        try process.run()

        let group = DispatchGroup()
        nonisolated(unsafe) var errorData = Data()
        group.enter()
        DispatchQueue.global().async {
            errorData = errors.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if let stdin, let input {
            group.enter()
            DispatchQueue.global().async {
                try? stdin.fileHandleForWriting.write(contentsOf: input)
                try? stdin.fileHandleForWriting.close()
                group.leave()
            }
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return (process.terminationStatus, outputData, errorData)
    }

    private static func failure(_ result: (status: Int32, output: Data, errors: Data)) -> NSError {
        let message = String(data: result.errors, encoding: .utf8) ?? ""
        return NSError(
            domain: "Marka",
            code: Int(result.status),
            userInfo: [NSLocalizedDescriptionKey: "pandoc failed: \(message)"]
        )
    }

    private static var missingPandoc: NSError {
        NSError(
            domain: "Marka",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "pandoc is not installed. Install it with: brew install pandoc"]
        )
    }

    static var pandocURL: URL? {
        let candidates = [
            "/opt/homebrew/bin/pandoc",
            "/usr/local/bin/pandoc",
            "/usr/bin/pandoc",
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func export(
        markdown: String,
        to url: URL,
        format: String,
        title: String,
        workingDirectory: URL?
    ) throws {
        guard let pandoc = pandocURL else { throw missingPandoc }

        let process = Process()
        process.executableURL = pandoc
        process.arguments = [
            "--from", "markdown",
            "--to", format,
            "--standalone",
            "--metadata", "title=\(title)",
            "--output", url.path,
            "-",
        ]
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        let result = try run(process, input: Data(markdown.utf8))
        guard result.status == 0 else { throw failure(result) }
    }
}
