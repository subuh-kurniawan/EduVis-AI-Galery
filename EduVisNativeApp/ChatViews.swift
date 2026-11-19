//
//  ChatViews.swift
//  EduVis Native AI
//
//  Komponen tampilan obrolan: Bubble percakapan Liquid Glass, blok kode interaktif,
//  bilah masukan mengambang (composer) dengan Lampiran Dokumen & Dikte Suara.
//

import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

struct AILoadingIndicatorView: View {
    @State private var phase: CGFloat = 0
    @State private var pulseGlow: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .scaleEffect(pulseGlow ? 1.15 : 0.95)

                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(phase * 360))
            }

            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(
                            i == 0 ? Color.blue : (i == 1 ? Color.purple : Color.pink)
                        )
                        .frame(width: 7, height: 7)
                        .scaleEffect(dotScale(for: i))
                        .opacity(dotOpacity(for: i))
                }
            }

            Text("Gemma sedang menyiapkan jawaban…")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .liquidGlass(cornerRadius: 14, strokeOpacity: 0.16)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseGlow = true
            }
        }
    }

    private func dotScale(for index: Int) -> CGFloat {
        let offset = Double(index) * 0.35
        let wave = sin((Double(phase) * 2 * .pi) - offset)
        return 0.75 + CGFloat((wave + 1) * 0.25)
    }

    private func dotOpacity(for index: Int) -> Double {
        let offset = Double(index) * 0.35
        let wave = sin((Double(phase) * 2 * .pi) - offset)
        return 0.35 + ((wave + 1) * 0.32)
    }
}

struct StreamingTypingIndicatorView: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(
                            i == 0 ? Color.blue : (i == 1 ? Color.purple : Color.pink)
                        )
                        .frame(width: 5, height: 5)
                        .scaleEffect(dotScale(for: i))
                        .opacity(dotOpacity(for: i))
                }
            }

            Text("Menulis respon…")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }

    private func dotScale(for index: Int) -> CGFloat {
        let offset = Double(index) * 0.4
        let wave = sin((phase * 2 * .pi) - offset)
        return 0.8 + CGFloat((wave + 1) * 0.2)
    }

    private func dotOpacity(for index: Int) -> Double {
        let offset = Double(index) * 0.4
        let wave = sin((phase * 2 * .pi) - offset)
        return 0.4 + ((wave + 1) * 0.3)
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(isCopied ? "Tersalin!" : "Salin Kode")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.25))

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.45))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage
    var activePort: Int = 1236
    var isLatestAssistant: Bool = false
    var onSelectFollowUp: ((String) -> Void)? = nil
    @State private var webHeight: CGFloat = 60
    @State private var isCopied = false
    @State private var isSkillSaved = false
    @AppStorage("gemma_chat_font_size") private var chatFontSize: Double = 15.0

    private var followUpPrompts: [String] {
        [
            "Ringkas menjadi poin utama",
            "Berikan contoh praktis",
            "Jelaskan lebih mendalam"
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                    .shadow(
                        color: .purple.opacity(message.isStreaming ? 0.75 : 0.3),
                        radius: message.isStreaming ? 7 : 4,
                        x: 0,
                        y: 2
                    )
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Lampiran dokumen jika ada
                if let attachments = message.attachments, !attachments.isEmpty {
                    ForEach(attachments) { doc in
                        HStack(spacing: 6) {
                            Image(systemName: doc.fileExtension == "pdf" ? "doc.fill" : "doc.text.fill")
                                .font(.system(size: 11))
                            Text(doc.name)
                                .font(.system(size: 11, weight: .medium))
                            Text("(\(doc.fileSize / 1024) KB)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }

                if message.role == .user {
                    Text(message.content)
                        .font(.system(size: CGFloat(chatFontSize)))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.85), Color.indigo.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .blue.opacity(0.2), radius: 6, x: 0, y: 2)
                        .frame(maxWidth: 680, alignment: .trailing)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if message.isStreaming && message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            AILoadingIndicatorView()
                        } else {
                            AIResponseRendererView(
                                content: message.content,
                                isStreaming: message.isStreaming,
                                activePort: activePort,
                                dynamicHeight: $webHeight,
                                fontSize: chatFontSize
                            )
                            .frame(height: max(35, webHeight))
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if message.isStreaming {
                                StreamingTypingIndicatorView()
                            }
                        }
                    }
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.92))
                            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                }

                if message.role == .assistant && !message.isStreaming {
                    HStack(spacing: 12) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                            isCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { isCopied = false }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                Text(isCopied ? "Tersalin!" : "Salin")
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(isCopied ? .green : .secondary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            let synth = AVSpeechSynthesizer()
                            let utterance = AVSpeechUtterance(string: message.content)
                            utterance.voice = AVSpeechSynthesisVoice(language: "id-ID")
                            synth.speak(utterance)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "speaker.wave.2")
                                Text("Suara")
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        ShareLink(item: message.content) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Bagikan")
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Bagikan lewat macOS Share Sheet atau seret gelembung keluar")

                        Button {
                            saveAsHermesSkill()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isSkillSaved ? "checkmark.circle.fill" : "wand.and.stars")
                                Text(isSkillSaved ? "Skill Tersimpan" : "Jadikan Skill")
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(isSkillSaved ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Simpan jawaban ini ke Hermes Skills (.md)")

                        Spacer()

                        Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                    .onDrag {
                        NSItemProvider(object: message.content as NSString)
                    }

                    if isLatestAssistant, let onSelectFollowUp, !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(followUpPrompts, id: \.self) { chip in
                                    Button {
                                        onSelectFollowUp(chip)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.turn.down.right")
                                                .font(.system(size: 9))
                                            Text(chip)
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .liquidGlass(cornerRadius: 12, strokeOpacity: 0.16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                } else if message.role == .user {
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }

            if message.role == .user {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func saveAsHermesSkill() {
        let scheme = activePort == 1234 ? "https" : "http"
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(activePort)/api/hermes/skills") else { return }
        let titleLine = message.content
            .split(separator: "\n")
            .first
            .map { String($0).replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) } ?? "Skill EduVis"
        let cleanTitle = String(titleLine.prefix(48)).isEmpty ? "Skill EduVis" : String(titleLine.prefix(48))
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "action": "save",
            "name": cleanTitle,
            "description": "Disimpan dari percakapan Native AI",
            "content": message.content,
            "tags": "native-chat,eduvis"
        ])
        let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
        session.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                isSkillSaved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { isSkillSaved = false }
            }
        }.resume()
    }
}

struct EmptyStateGreetingView: View {
    let onSelectPrompt: (String) -> Void

    private let suggestions = [
        ("cpu", "Analisis Kode", "Bantu saya mereview dan menganalisis kode arsitektur ini."),
        ("cylinder.split.1x2", "Basis Pengetahuan (RAG)", "Apa saja dokumen yang tersimpan di basis data lokal?"),
        ("wand.and.stars", "Ide & Konseptual", "Jelaskan konsep Local-First AI dan inferensi Gemma 4."),
        ("square.split.2x1", "Komparasi Model", "Bandingkan performa Gemma 4 E2B vs E4B.")
    ]

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.35), .purple.opacity(0.35)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)
                        .blur(radius: 12)

                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text("EduVis Native AI Studio")
                    .font(.system(size: 24, weight: .bold))

                Text("Aplikasi native macOS murni dengan 13 Ruang Kerja lengkap, analisis dokumen, komparasi model, dan inferensi Gemma 4 lokal.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 380), spacing: 12)], spacing: 12) {
                ForEach(suggestions, id: \.1) { icon, title, prompt in
                    Button {
                        onSelectPrompt(prompt)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon)
                                .font(.system(size: 18))
                                .foregroundStyle(.blue)
                                .frame(width: 32, height: 32)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(prompt)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .liquidGlass(cornerRadius: 12, strokeOpacity: 0.12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 640)
        }
        .padding(32)
    }
}

struct ComposerBarView: View {
    @Binding var text: String
    var isStreaming: Bool
    @Binding var useKnowledgeBase: Bool
    var onSend: () -> Void
    var onStop: () -> Void

    @State private var attachedFile: AttachedFile?
    @State private var isDropTargeted = false
    @StateObject private var speechRecognizer = SpeechRecognizerService()
    @AppStorage("gemma_chat_font_size") private var chatFontSize: Double = 15.0

    var body: some View {
        VStack(spacing: 6) {
            // Pill lampiran berkas jika ada
            if let file = attachedFile {
                HStack(spacing: 8) {
                    Image(systemName: file.fileExtension == "pdf" ? "doc.fill" : "doc.text.fill")
                        .foregroundStyle(.red)
                    Text(file.name)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Button {
                        attachedFile = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.07))
                .clipShape(Capsule())
                .padding(.horizontal, 22)
            }

            HStack(spacing: 10) {
                // Tombol Lampirkan Dokumen
                Button {
                    if let picked = DocumentAnalyzerService.promptForFile() {
                        attachedFile = picked
                    }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14))
                        .foregroundStyle(attachedFile != nil ? Color.blue : Color.secondary)
                        .padding(8)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Lampirkan atau seret dokumen PDF, CSV, TXT, atau Kode")

                // Tombol Dikte Suara (Native Speech-to-Text)
                Button {
                    speechRecognizer.toggleRecording { transcribed in
                        text = transcribed
                    }
                } label: {
                    Image(systemName: speechRecognizer.isRecording ? "waveform" : "mic")
                        .font(.system(size: 14))
                        .foregroundStyle(speechRecognizer.isRecording ? Color.red : Color.secondary)
                        .padding(8)
                        .background(speechRecognizer.isRecording ? Color.red.opacity(0.2) : Color.primary.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Dikte suara native")

                // Tombol Sakelar RAG KB
                Button {
                    useKnowledgeBase.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: useKnowledgeBase ? "cylinder.split.1x2.fill" : "cylinder.split.1x2")
                            .font(.system(size: 11))
                        Text("RAG")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(useKnowledgeBase ? Color.blue.opacity(0.25) : Color.primary.opacity(0.07))
                    .foregroundStyle(useKnowledgeBase ? Color.blue : Color.secondary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Gunakan Basis Pengetahuan Dokumen Lokal (SQLite RAG)")

                TextField("Ketik pesan untuk Gemma 4...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...5)
                    .onSubmit {
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming {
                            sendWithAttachment()
                        }
                    }

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Hentikan generasi token")
                } else {
                    Button(action: sendWithAttachment) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(
                                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.secondary.opacity(0.4)
                                    : Color.blue
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Kirim pesan")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .liquidGlass(cornerRadius: 22, strokeOpacity: 0.22, shadowRadius: 10)
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.accentColor.opacity(0.08))
                        )
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleComposerDrop(providers: providers)
            }
            .padding(.horizontal, 20)

            // Bilah Pengatur Cepat Bawah Composer (Ukuran Font Aa − 15px + ↺ & Info Singkat)
            HStack(spacing: 10) {
                ChatFontSizePillView(compact: true)

                Spacer()

                Text("Enter untuk kirim · ⇧⌘L Galeri · ⌘⌥I Inspector")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
        }
    }

    private func handleComposerDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  let extracted = DocumentAnalyzerService.extractFile(at: url) else { return }
            DispatchQueue.main.async {
                attachedFile = extracted
            }
        }
        return true
    }

    private func sendWithAttachment() {
        if let doc = attachedFile {
            text = """
            [Lampiran Dokumen: \(doc.name)]
            \(doc.contentSnippet)

            Pertanyaan:
            \(text)
            """
            attachedFile = nil
        }
        onSend()
    }
}
