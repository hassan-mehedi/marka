import CodeEditLanguages
import Foundation
import SwiftTreeSitter

@MainActor
final class CodeHighlighter {
    static let shared = CodeHighlighter()

    struct Token {
        let range: NSRange
        let name: String
    }

    private let parser = Parser()
    private var queries: [String: Query] = [:]

    // CodeEditLanguages resolves its query paths against a doubled
    // Resources/Resources directory under SwiftPM, so load the .scm
    // files from the resource bundle directly.
    private static let queryBase: URL? = {
        let host = Bundle(for: TreeSitterModel.self).bundleURL
        let candidates = [
            host,
            host.deletingLastPathComponent(),
            Bundle.main.resourceURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ]
        for base in candidates {
            guard let bundle = base?.appendingPathComponent("CodeEditLanguages_CodeEditLanguages.bundle") else { continue }
            for resources in [bundle.appendingPathComponent("Resources"), bundle.appendingPathComponent("Contents/Resources/Resources")]
            where FileManager.default.fileExists(atPath: resources.path) {
                return resources
            }
        }
        return nil
    }()

    func highlights(for code: String, language tag: String) -> [Token] {
        guard let codeLanguage = Self.codeLanguage(for: tag),
              let language = codeLanguage.language,
              let query = query(for: codeLanguage, language: language)
        else { return [] }

        do {
            try parser.setLanguage(language)
        } catch {
            return []
        }
        guard let tree = parser.parse(code) else { return [] }

        let cursor = query.execute(in: tree)
        return cursor
            .resolve(with: .init(string: code))
            .highlights()
            .map { Token(range: $0.range, name: $0.name) }
    }

    private func query(for codeLanguage: CodeLanguage, language: Language) -> Query? {
        if let cached = queries[codeLanguage.tsName] {
            return cached
        }
        guard let base = Self.queryBase else { return nil }

        var data = Data()
        if let parent = codeLanguage.parentQueryURL {
            let tail = parent.pathComponents.suffix(2).joined(separator: "/")
            if let parentData = try? Data(contentsOf: base.appendingPathComponent(tail)) {
                data.append(parentData)
            }
        }
        let own = base.appendingPathComponent("tree-sitter-\(codeLanguage.tsName)/highlights.scm")
        guard let ownData = try? Data(contentsOf: own) else { return nil }
        data.append(ownData)

        guard let query = try? Query(language: language, data: data) else { return nil }
        queries[codeLanguage.tsName] = query
        return query
    }

    private static func codeLanguage(for tag: String) -> CodeLanguage? {
        let key = tag.lowercased()
        return CodeLanguage.allLanguages.first { language in
            language.tsName.lowercased() == key
                || language.extensions.contains(key)
                || language.additionalIdentifiers.contains(key)
        }
    }
}
