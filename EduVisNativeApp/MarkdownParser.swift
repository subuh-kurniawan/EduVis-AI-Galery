//
//  MarkdownParser.swift
//  EduVis Native AI
//
//  Parser blok markdown ringan untuk teks dan syntax code block native.
//

import Foundation

enum ContentBlock: Identifiable, Sendable {
    case text(String)
    case code(language: String, code: String)

    var id: String {
        switch self {
        case .text(let t):
            return "text_\(t.hashValue)"
        case .code(let lang, let code):
            return "code_\(lang)_\(code.hashValue)"
        }
    }
}

enum MarkdownParser {
    static func parseBlocks(_ content: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        let lines = content.components(separatedBy: "\n")
        var currentTextLines: [String] = []
        var isInCodeBlock = false
        var currentCodeLanguage = ""
        var currentCodeLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    // Selesai code block
                    let codeText = currentCodeLines.joined(separator: "\n")
                    blocks.append(.code(language: currentCodeLanguage, code: codeText))
                    currentCodeLines.removeAll()
                    currentCodeLanguage = ""
                    isInCodeBlock = false
                } else {
                    // Simpan teks sebelumnya
                    if !currentTextLines.isEmpty {
                        let text = currentTextLines.joined(separator: "\n")
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            blocks.append(.text(text))
                        }
                        currentTextLines.removeAll()
                    }
                    // Mulai code block
                    isInCodeBlock = true
                    currentCodeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    if currentCodeLanguage.isEmpty {
                        currentCodeLanguage = "code"
                    }
                }
            } else if isInCodeBlock {
                currentCodeLines.append(line)
            } else {
                currentTextLines.append(line)
            }
        }

        // Tangani sisa blok jika streaming belum selesai menutup ```
        if isInCodeBlock {
            let codeText = currentCodeLines.joined(separator: "\n")
            blocks.append(.code(language: currentCodeLanguage, code: codeText))
        } else if !currentTextLines.isEmpty {
            let text = currentTextLines.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(text))
            }
        }

        if blocks.isEmpty && !content.isEmpty {
            blocks.append(.text(content))
        }

        return blocks
    }
}
