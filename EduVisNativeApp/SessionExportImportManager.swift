//
//  SessionExportImportManager.swift
//  EduVis Native AI
//
//  Pengelola ekspor dan impor sesi obrolan (JSON & Markdown) kompatibel dengan format browser.
//

import Foundation
import AppKit

enum SessionExportImportManager {
    @MainActor
    static func exportSessionAsJSON(_ session: ChatSession) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        let safeTitle = session.title.replacingOccurrences(of: "/", with: "-")
        savePanel.nameFieldStringValue = "\(safeTitle).json"

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(session) {
            try? data.write(to: url)
        }
    }

    @MainActor
    static func exportSessionAsMarkdown(_ session: ChatSession) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        let safeTitle = session.title.replacingOccurrences(of: "/", with: "-")
        savePanel.nameFieldStringValue = "\(safeTitle).md"

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        var md = "# \(session.title)\n\n"
        md += "- **Tanggal:** \(session.createdAt.formatted())\n"
        md += "- **Model:** \(session.modelName)\n"
        md += "- **Ruang Kerja:** \(session.workspace.displayName)\n\n---\n\n"

        for msg in session.messages {
            let roleHeader = msg.role == .user ? "### 👤 Pengguna" : "### 🤖 Gemma 4 AI"
            md += "\(roleHeader) (\(msg.timestamp.formatted(date: .omitted, time: .shortened)))\n\n"
            md += "\(msg.content)\n\n---\n\n"
        }

        try? md.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    static func importSessionFromJSON() -> ChatSession? {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false

        guard openPanel.runModal() == .OK, let url = openPanel.url else { return nil }

        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let decoded = try? decoder.decode(ChatSession.self, from: data) {
            return ChatSession(
                title: decoded.title + " (Impor)",
                workspace: decoded.workspace,
                messages: decoded.messages,
                modelName: decoded.modelName
            )
        }

        // Coba format browser generik jika ada
        struct BrowserSessionFormat: Decodable {
            let title: String?
            let messages: [BrowserMessageFormat]?
        }
        struct BrowserMessageFormat: Decodable {
            let role: String
            let content: String
        }

        if let browserFormat = try? decoder.decode(BrowserSessionFormat.self, from: data),
           let bMessages = browserFormat.messages {
            let chatMessages = bMessages.map { bm in
                ChatMessage(
                    role: bm.role == "user" ? .user : .assistant,
                    content: bm.content
                )
            }
            return ChatSession(
                title: (browserFormat.title ?? "Sesi Terimpor") + " (Browser)",
                messages: chatMessages
            )
        }

        return nil
    }
}
