//
//  DocumentAnalyzerService.swift
//  EduVis Native AI
//
//  Ekstraksi dan analisis dokumen native (PDF, Teks, Markdown, CSV, Kode Sumber).
//

import Foundation
import AppKit
import PDFKit

enum DocumentAnalyzerService {
    @MainActor
    static func promptForFile() -> AttachedFile? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .pdf,
            .plainText,
            .sourceCode,
            .json,
            .commaSeparatedText,
            .xml,
            .html
        ]

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return extractFile(at: url)
    }

    static func extractFile(at url: URL) -> AttachedFile? {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? Int64) ?? 0

        var extractedText = ""

        if ext == "pdf" {
            if let pdf = PDFDocument(url: url) {
                var pagesText: [String] = []
                for i in 0..<min(25, pdf.pageCount) {
                    if let page = pdf.page(at: i), let pageString = page.string {
                        pagesText.append("--- Halaman \(i + 1) ---\n\(pageString)")
                    }
                }
                extractedText = pagesText.joined(separator: "\n\n")
            }
        } else {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                extractedText = text
            } else if let text = try? String(contentsOf: url, encoding: .isoLatin1) {
                extractedText = text
            }
        }

        if extractedText.isEmpty {
            return nil
        }

        // Batasi snippet jika file terlalu besar
        let maxChars = 20_000
        let truncated = extractedText.count > maxChars
            ? String(extractedText.prefix(maxChars)) + "\n\n[... Isi dokumen dipotong untuk menghemat konteks ...]"
            : extractedText

        return AttachedFile(
            name: name,
            fileExtension: ext,
            fileSize: size,
            contentSnippet: truncated
        )
    }
}
