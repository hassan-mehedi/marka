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

    // A highlighted block plus the syntax tree behind it, so the next edit to
    // the same block reparses only what changed.
    struct Parse {
        let code: String
        let tokens: [Token]
        fileprivate let tree: MutableTree
    }

    private let parser = Parser()
    private var queries: [String: Query] = [:]
    private var currentLanguage: String?
    private static var languageLookup: [String: CodeLanguage?] = [:]

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
        parse(code, language: tag, previous: nil)?.tokens ?? []
    }

    func parse(_ code: String, language tag: String, previous: Parse?) -> Parse? {
        guard let codeLanguage = Self.codeLanguage(for: tag),
              let language = codeLanguage.language,
              let query = query(for: codeLanguage, language: language)
        else { return nil }

        if currentLanguage != codeLanguage.tsName {
            do {
                try parser.setLanguage(language)
            } catch {
                return nil
            }
            currentLanguage = codeLanguage.tsName
        }

        let tree: MutableTree?
        if let previous {
            previous.tree.edit(Self.edit(from: previous.code, to: code))
            tree = parser.parse(tree: previous.tree, string: code)
        } else {
            tree = parser.parse(code)
        }
        guard let tree else { return nil }

        let cursor = query.execute(in: tree)
        let tokens = cursor
            .resolve(with: .init(string: code))
            .highlights()
            .map { Token(range: $0.range, name: $0.name) }
        return Parse(code: code, tokens: tokens, tree: tree)
    }

    // The single replaced span between two versions of a block: the text
    // after the common prefix and before the common suffix.
    nonisolated static func edit(from old: String, to new: String) -> InputEdit {
        let oldUnits = Array(old.utf16)
        let newUnits = Array(new.utf16)
        var prefix = 0
        while prefix < oldUnits.count, prefix < newUnits.count, oldUnits[prefix] == newUnits[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldUnits.count - prefix, suffix < newUnits.count - prefix,
              oldUnits[oldUnits.count - 1 - suffix] == newUnits[newUnits.count - 1 - suffix] {
            suffix += 1
        }
        let oldEnd = oldUnits.count - suffix
        let newEnd = newUnits.count - suffix
        return InputEdit(
            startByte: prefix * 2,
            oldEndByte: oldEnd * 2,
            newEndByte: newEnd * 2,
            startPoint: point(at: prefix, in: oldUnits),
            oldEndPoint: point(at: oldEnd, in: oldUnits),
            newEndPoint: point(at: newEnd, in: newUnits)
        )
    }

    private nonisolated static func point(at index: Int, in units: [UInt16]) -> Point {
        var row = 0
        var lineStart = 0
        for offset in 0..<index where units[offset] == 0x0A {
            row += 1
            lineStart = offset + 1
        }
        return Point(row: row, column: (index - lineStart) * 2)
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
        if let cached = languageLookup[key] { return cached }
        let found = CodeLanguage.allLanguages.first { language in
            language.tsName.lowercased() == key
                || language.extensions.contains(key)
                || language.additionalIdentifiers.contains(key)
        }
        languageLookup[key] = .some(found)
        return found
    }
}
