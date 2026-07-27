import Foundation

public enum ChatContentBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case quote(String)
    case code(language: String?, content: String)
    case divider
}

public enum ChatPresentation {
    public static func isVisible(_ role: MessageRole) -> Bool {
        role == .user || role == .assistant
    }

    public static func sanitizeUserContent(_ content: String) -> String {
        var value = content
        value = replacing(
            #"^\[[A-Za-z]{3} \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [A-Za-z]{2,6}\]\s*"#,
            in: value,
            with: { _ in "" }
        )
        value = replacing(#"\[User sent an image:\s*([^\]]+)\]"#, in: value) { match in
            "📎 \(displayName(match[1]))\n"
        }
        value = replacing(#"\[Image attached at:\s*([^\]]+)\]"#, in: value) { match in
            "\n\n📎 \(displayName(match[1]))"
        }
        value = replacing(
            #"\[The user sent a document: '(.*?)'\. It is saved at: .*?instead of asking the user to paste the contents\.\]"#,
            in: value,
            options: [.dotMatchesLineSeparators]
        ) { match in
            "📎 \(match[1])\n"
        }
        value = replacing(#"\s*\[screenshot\]\s*"#, in: value) { _ in "" }
        value = replacing(#"[ \t]+\n"#, in: value) { _ in "\n" }
        value = replacing(#"\n{3,}"#, in: value) { _ in "\n\n" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func blocks(_ markdown: String) -> [ChatContentBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        var result: [ChatContentBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var body: [String] = []
                while index < lines.count, !lines[index].hasPrefix("```") {
                    body.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                result.append(.code(language: language.isEmpty ? nil : language, content: body.joined(separator: "\n")))
                continue
            }
            if let heading = heading(line) {
                result.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }
            if isDivider(line) {
                result.append(.divider)
                index += 1
                continue
            }
            if let item = unorderedItem(line) {
                var items = [item]
                index += 1
                while index < lines.count, let next = unorderedItem(lines[index]) {
                    items.append(next)
                    index += 1
                }
                result.append(.unorderedList(items))
                continue
            }
            if let item = orderedItem(line) {
                var items = [item]
                index += 1
                while index < lines.count, let next = orderedItem(lines[index]) {
                    items.append(next)
                    index += 1
                }
                result.append(.orderedList(items))
                continue
            }
            if let quoted = quoteLine(line) {
                var quote = [quoted]
                index += 1
                while index < lines.count, let next = quoteLine(lines[index]) {
                    quote.append(next)
                    index += 1
                }
                result.append(.quote(quote.joined(separator: "\n")))
                continue
            }

            var paragraph = [line]
            index += 1
            while index < lines.count {
                let next = lines[index]
                if next.trimmingCharacters(in: .whitespaces).isEmpty || isBlockStart(next) { break }
                paragraph.append(next)
                index += 1
            }
            result.append(.paragraph(paragraph.joined(separator: "\n")))
        }
        return result
    }

    private static func isBlockStart(_ line: String) -> Bool {
        line.hasPrefix("```") || heading(line) != nil || isDivider(line)
            || unorderedItem(line) != nil || orderedItem(line) != nil || quoteLine(line) != nil
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, line.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces))
    }

    private static func unorderedItem(_ line: String) -> String? {
        guard line.count >= 2 else { return nil }
        let prefix = line.prefix(2)
        guard prefix == "- " || prefix == "* " || prefix == "+ " else { return nil }
        return String(line.dropFirst(2))
    }

    private static func orderedItem(_ line: String) -> String? {
        guard let match = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) else { return nil }
        return String(line[match.upperBound...])
    }

    private static func quoteLine(_ line: String) -> String? {
        guard line.hasPrefix(">") else { return nil }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        return compact.count >= 3 && (Set(compact) == ["-"] || Set(compact) == ["*"] || Set(compact) == ["_"])
    }

    private static func displayName(_ rawPath: String) -> String {
        rawPath.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? "Attachment"
    }

    private static func replacing(
        _ pattern: String,
        in source: String,
        options: NSRegularExpression.Options = [],
        with replacement: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return source }
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        var result = source
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result) else { continue }
            var groups = [String(result[fullRange])]
            if match.numberOfRanges > 1 {
                for index in 1..<match.numberOfRanges {
                    if let range = Range(match.range(at: index), in: result) { groups.append(String(result[range])) }
                    else { groups.append("") }
                }
            }
            result.replaceSubrange(fullRange, with: replacement(groups))
        }
        return result
    }
}
