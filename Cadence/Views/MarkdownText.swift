import SwiftUI

/// A small, dependency-free markdown renderer. Handles the block structure Cadence produces —
/// headings, bullet/numbered lists, fenced code, blockquotes, rules, paragraphs — and defers
/// inline styling (**bold**, *italic*, `code`, [links](url)) to `AttributedString`. Not full
/// CommonMark, but it renders the descriptions, solutions, digests, and docs the app generates.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.parse(markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(.system(size: headingSize(level), weight: .bold))
                .padding(.top, level <= 2 ? 4 : 2)
        case .paragraph(let text):
            inline(text).font(DS.Font.body)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(DS.Font.body).foregroundStyle(DS.textSecondary)
                        inline(item).font(DS.Font.body)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(idx + 1).").font(DS.Font.body).foregroundStyle(DS.textSecondary).monospacedDigit()
                        inline(item).font(DS.Font.body)
                    }
                }
            }
        case .code(let text):
            Text(text)
                .font(DS.Font.mono)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
        case .quote(let text):
            HStack(spacing: 8) {
                Rectangle().fill(DS.border).frame(width: 3)
                inline(text).font(DS.Font.body).foregroundStyle(DS.textSecondary)
            }
        case .rule:
            Divider().overlay(DS.borderSoft)
        }
    }

    /// Inline markers (bold/italic/code/links) via AttributedString; block syntax handled above.
    private func inline(_ text: String) -> Text {
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr)
        }
        return Text(text)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 19
        case 3: return 17
        default: return 15
        }
    }

    // MARK: parsing

    enum Block {
        case heading(Int, String)
        case paragraph(String)
        case bullet([String])
        case numbered([String])
        case code(String)
        case quote(String)
        case rule
    }

    /// The item text if `line` is a numbered-list item ("3. foo"), else nil.
    private static func numberedItem(_ line: String) -> String? {
        var idx = line.startIndex
        var digits = 0
        while idx < line.endIndex, line[idx].isNumber { idx = line.index(after: idx); digits += 1 }
        guard digits > 0, idx < line.endIndex, line[idx] == "." else { return nil }
        let afterDot = line.index(after: idx)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.index(after: afterDot)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func bulletItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(2))
        }
        return nil
    }

    static func parse(_ md: String) -> [Block] {
        var blocks: [Block] = []
        let lines = md.components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []
        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph.removeAll()
            }
        }

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {                        // fenced code
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1                                         // skip closing fence
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }
            if line.isEmpty { flushParagraph(); i += 1; continue }
            if line == "---" || line == "***" || line == "___" {
                flushParagraph(); blocks.append(.rule); i += 1; continue
            }
            if line.hasPrefix("#") {                           // heading
                let hashes = line.prefix(while: { $0 == "#" }).count
                if hashes <= 6, line.dropFirst(hashes).first == " " {
                    flushParagraph()
                    blocks.append(.heading(hashes, String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)))
                    i += 1; continue
                }
            }
            if bulletItem(line) != nil {                       // bullet list
                flushParagraph()
                var items: [String] = []
                while i < lines.count, let item = bulletItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(item); i += 1
                }
                blocks.append(.bullet(items))
                continue
            }
            if numberedItem(line) != nil {                     // numbered list
                flushParagraph()
                var items: [String] = []
                while i < lines.count, let item = numberedItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(item); i += 1
                }
                blocks.append(.numbered(items))
                continue
            }
            if line.hasPrefix("> ") {                          // blockquote
                flushParagraph()
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("> ") {
                    quote.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2))); i += 1
                }
                blocks.append(.quote(quote.joined(separator: " ")))
                continue
            }
            paragraph.append(line)                             // paragraph
            i += 1
        }
        flushParagraph()
        return blocks
    }
}
