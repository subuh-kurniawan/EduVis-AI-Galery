//
//  QuickAskModalView.swift
//  EduVis Native AI
//
//  Jendela Tanya Cepat (Quick Ask Spotlight Panel) khas macOS (⌘K).
//

import SwiftUI
import AppKit

struct QuickAskModalView: View {
    @ObservedObject var aiService: LocalAIService
    @Environment(\.dismiss) private var dismiss

    @State private var quickPrompt: String = ""
    @State private var quickReply: String = ""
    @State private var isAnswering: Bool = false
    @State private var clipboardSnippet: String = ""
    @State private var telemetryLabel: String = ""
    @State private var isCopied: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Bilah Input Spotlight & Command Palette
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.yellow)

                TextField("Tanya Gemma 4 atau ketik `> perintah` (⌘K)...", text: $quickPrompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .onSubmit { askQuickly() }

                if isAnswering {
                    ProgressView()
                        .controlSize(.small)
                } else if !quickPrompt.isEmpty {
                    Button(action: askQuickly) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(.ultraThinMaterial)

            // Chip Clipboard & Pintasan Perintah Cepat
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !clipboardSnippet.isEmpty {
                        Button {
                            quickPrompt = "Jelaskan atau ringkas isi clipboard berikut:\n\n\(clipboardSnippet)"
                        } label: {
                            Label("Tempel Clipboard", systemImage: "doc.on.clipboard")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.14))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach([
                        ("> Hermes", "> hermes"),
                        ("> Tema", "> tema"),
                        ("> Tangkap Layar", "> layar"),
                        ("> Pusat Model", "> model"),
                        ("> Pintasan ⌘/", "> pintasan")
                    ], id: \.0) { label, cmd in
                        Button {
                            quickPrompt = cmd
                            askQuickly()
                        } label: {
                            Text(label)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.07))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Divider()

            // Hasil Jawaban Spotlight
            ScrollView {
                if !quickReply.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(quickReply)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .onDrag {
                                NSItemProvider(object: quickReply as NSString)
                            }

                        HStack(spacing: 10) {
                            if !telemetryLabel.isEmpty {
                                Text(telemetryLabel)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareLink(item: quickReply) {
                                Label("Bagikan", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            Button(isCopied ? "Tersalin!" : "Salin Jawaban") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(quickReply, forType: .string)
                                isCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { isCopied = false }
                            }
                            .font(.system(size: 11))
                        }
                        .padding(.top, 8)
                    }
                    .padding(18)
                } else {
                    Text("Ketik pertanyaan Anda atau awali dengan `>` untuk Command Palette (contoh: `> tema`, `> layar`, `> model`, `> pintasan`).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(24)
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 600)
        .liquidGlass(cornerRadius: 16, strokeOpacity: 0.25, shadowRadius: 20)
        .onAppear {
            if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !clip.isEmpty {
                clipboardSnippet = String(clip.prefix(4000))
            }
        }
    }

    private func askQuickly() {
        let p = quickPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }

        if p.hasPrefix(">") {
            let cmd = p.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if cmd.contains("hermes") || cmd.contains("skill") || cmd.contains("memori") || cmd.contains("cron") {
                dismiss()
                NotificationCenter.default.post(name: .openHermesHubNotification, object: nil)
                return
            }
            if cmd.contains("tema") {
                NotificationCenter.default.post(name: .toggleThemeNotification, object: nil)
                dismiss()
                return
            }
            if cmd.contains("model") {
                dismiss()
                NotificationCenter.default.post(name: .openModelCenterNotification, object: nil)
                return
            }
            if cmd.contains("pintasan") || cmd.contains("shortcut") {
                dismiss()
                NotificationCenter.default.post(name: .toggleShortcutSheetNotification, object: nil)
                return
            }
            if cmd.contains("layar") || cmd.contains("screen") {
                dismiss()
                NotificationCenter.default.post(name: .captureScreenNotification, object: nil)
                return
            }
            if cmd.contains("baru") || cmd.contains("bersih") {
                NotificationCenter.default.post(name: .newChatNotification, object: nil)
                dismiss()
                return
            }
        }

        quickReply = ""
        telemetryLabel = ""
        isAnswering = true
        let startedAt = CFAbsoluteTimeGetCurrent()

        let msg = [ChatMessage(role: .user, content: p)]
        let cfg = GenerationConfig(temperature: 0.5)

        aiService.sendMessageStream(history: msg, model: "gemma-4-E2B-it", config: cfg) { token in
            quickReply += token
        } onCompletion: { _ in
            isAnswering = false
            let elapsed = max(0.05, CFAbsoluteTimeGetCurrent() - startedAt)
            let estTokens = max(1.0, Double(quickReply.count) / 4.0)
            telemetryLabel = String(format: "%.1f tok/s · %.1fd", estTokens / elapsed, elapsed)
        }
    }
}
