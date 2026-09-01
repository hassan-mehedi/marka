import Foundation

enum PandocExporter {
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
        guard let pandoc = pandocURL else {
            throw NSError(
                domain: "Marka",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "pandoc is not installed. Install it with: brew install pandoc"]
            )
        }

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
