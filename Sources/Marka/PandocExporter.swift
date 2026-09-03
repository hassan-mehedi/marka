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
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "Marka",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "pandoc failed: \(message)"]
            )
        }
        return String(decoding: data, as: UTF8.self)
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

        let input = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardError = errors
        try process.run()
        input.fileHandleForWriting.write(Data(markdown.utf8))
        input.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "Marka",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "pandoc failed: \(message)"]
            )
        }
    }
}
