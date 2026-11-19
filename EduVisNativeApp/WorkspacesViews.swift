//
//  WorkspacesViews.swift
//  EduVis Native AI
//
//  Implementasi Native untuk seluruh Ruang Kerja (Workspaces):
//  1. VS (Komparasi Model)
//  2. Claude & Artifacts (Split Screen)
//  3. EduVis Live (Voice & Audio Waveform)
//  4. Vision & Dokumen (PDF/Code/CSV Extraction)
//  5. Analisis Kode (Code Review & Refactor)
//  6. Agen AI Otonom (Multi-step Planner)
//  7. PGlite Vector SQL (Database & RAG Inspector)
//

import SwiftUI
import AppKit
import AVFoundation

// MARK: - 1. VS (Komparasi Model Side-by-Side)
struct VSComparisonWorkspaceView: View {
    @ObservedObject var aiService: LocalAIService
    @State private var modelA: String = "gemma-4-E2B-it"
    @State private var modelB: String = "gemma-4-E4B-it"
    @State private var promptText: String = ""
    @State private var responseA: String = ""
    @State private var responseB: String = ""
    @State private var isRunningA: Bool = false
    @State private var isRunningB: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header pemilihan model
            HStack(spacing: 16) {
                HStack {
                    Text("Model A:")
                        .font(.system(size: 12, weight: .bold))
                    Picker("", selection: $modelA) {
                        ForEach(aiService.availableModels) { Text($0.displayName).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                }
                .padding(8)
                .liquidGlass(cornerRadius: 10, strokeOpacity: 0.15)

                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Model B:")
                        .font(.system(size: 12, weight: .bold))
                    Picker("", selection: $modelB) {
                        ForEach(aiService.availableModels) { Text($0.displayName).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                }
                .padding(8)
                .liquidGlass(cornerRadius: 10, strokeOpacity: 0.15)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider().opacity(0.2)

            // Panel Komparasi Side-by-Side
            GeometryReader { geo in
                HStack(spacing: 1) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(modelA)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.blue)
                            Spacer()
                            if isRunningA {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)

                        ScrollView {
                            Text(responseA.isEmpty ? "Menunggu inferensi..." : responseA)
                                .font(.system(size: 13))
                                .foregroundStyle(responseA.isEmpty ? .secondary : .primary)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(width: geo.size.width / 2)
                    .background(Color.black.opacity(0.1))

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(modelB)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.purple)
                            Spacer()
                            if isRunningB {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)

                        ScrollView {
                            Text(responseB.isEmpty ? "Menunggu inferensi..." : responseB)
                                .font(.system(size: 13))
                                .foregroundStyle(responseB.isEmpty ? .secondary : .primary)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(width: geo.size.width / 2)
                    .background(Color.black.opacity(0.1))
                }
            }

            Divider().opacity(0.2)

            // Input prompt komparasi
            HStack(spacing: 12) {
                TextField("Masukkan instruksi prompt untuk dikomparasi secara bersamaan...", text: $promptText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { runComparison() }

                Button(action: runComparison) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Bandingkan")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(promptText.trimmingCharacters(in: .whitespaces).isEmpty || isRunningA || isRunningB)
            }
            .padding(14)
            .liquidGlass(cornerRadius: 16, strokeOpacity: 0.15)
            .padding(16)
        }
    }

    private func runComparison() {
        let p = promptText.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }

        responseA = ""
        responseB = ""
        isRunningA = true
        isRunningB = true

        let msg = [ChatMessage(role: .user, content: p)]
        let cfg = GenerationConfig()

        aiService.sendMessageStream(history: msg, model: modelA, config: cfg) { token in
            responseA += token
        } onCompletion: { _ in
            isRunningA = false
        }

        aiService.sendMessageStream(history: msg, model: modelB, config: cfg) { token in
            responseB += token
        } onCompletion: { _ in
            isRunningB = false
        }
    }
}

// MARK: - 2. Claude & Artifacts (Split Screen)
struct ClaudeArtifactsWorkspaceView: View {
    @ObservedObject var aiService: LocalAIService
    @Binding var currentSession: ChatSession?
    @Binding var inputText: String
    var onSend: () -> Void

    @State private var activeArtifactCode: String = ""
    @State private var activeArtifactTitle: String = "Artifact Preview"

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Kolom Chat Kiri
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            if let session = currentSession, !session.messages.isEmpty {
                                LazyVStack(spacing: 12) {
                                    ForEach(session.messages) { msg in
                                        ChatBubbleView(
                                            message: msg,
                                            activePort: aiService.activePort
                                        )
                                        .id(msg.id)
                                    }

                                    Color.clear
                                        .frame(height: 1)
                                        .id("claudeBottomAnchor")
                                }
                                .padding(.vertical, 14)
                            } else {
                                Text("Mode Claude & Artifacts: Kode dan dokumen visual akan otomatis terbuka di panel sebelah kanan.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .padding(30)
                            }
                        }
                        .onChange(of: currentSession?.messages.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.22)) {
                                proxy.scrollTo("claudeBottomAnchor", anchor: .bottom)
                            }
                        }
                        .onChange(of: currentSession?.messages.last?.content) { _, _ in
                            withAnimation(.easeOut(duration: 0.22)) {
                                proxy.scrollTo("claudeBottomAnchor", anchor: .bottom)
                            }
                        }
                    }

                    ComposerBarView(
                        text: $inputText,
                        isStreaming: aiService.isStreaming,
                        useKnowledgeBase: .constant(true),
                        onSend: onSend,
                        onStop: { aiService.stopStreaming() }
                    )
                }
                .frame(width: geo.size.width * 0.52)

                Divider()

                // Kolom Artifact Kanan (Live Inspector)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: "sidebar.right")
                            .foregroundStyle(.blue)
                        Text(activeArtifactTitle)
                            .font(.system(size: 13, weight: .bold))

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(activeArtifactCode, forType: .string)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Salin Artifact")
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)

                    Divider()

                    ScrollView {
                        Text(activeArtifactCode.isEmpty ? "// Belum ada artifact yang dihasilkan.\n// Mintalah Gemma 4 untuk menulis kode, HTML, diagram, atau komponen aplikasi!" : activeArtifactCode)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .background(Color.black.opacity(0.35))
                }
                .frame(width: geo.size.width * 0.48)
            }
        }
        .onChange(of: currentSession?.messages.last?.content) { _, newContent in
            if let content = newContent {
                detectAndExtractArtifact(from: content)
            }
        }
    }

    private func detectAndExtractArtifact(from text: String) {
        if let start = text.range(of: "```"),
           let end = text.range(of: "```", options: .backwards),
           start.upperBound < end.lowerBound {
            let codeWithLang = String(text[start.upperBound..<end.lowerBound])
            let lines = codeWithLang.components(separatedBy: "\n")
            if lines.count > 1 {
                activeArtifactTitle = "Artifact: " + (lines.first?.trimmingCharacters(in: .whitespaces) ?? "Code")
                activeArtifactCode = lines.dropFirst().joined(separator: "\n")
            } else {
                activeArtifactCode = codeWithLang
            }
        }
    }
}

// MARK: - 3. EduVis Live (Voice & Waveform Workspace)
struct GeminiLiveVoiceWorkspaceView: View {
    @ObservedObject var aiService: LocalAIService
    @StateObject private var speechRecognizer = SpeechRecognizerService()
    @StateObject private var speechSynthesizer = NativeSpeechSynthesizerService()
    @State private var lastUserPrompt: String = ""
    @State private var assistantSpokenReply: String = ""
    @State private var isProcessing: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            // Bilah Bar Opsi Pengaturan TTS Cepat (Liquid Glass)
            HStack(spacing: 12) {
                // Selector Mesin TTS: Lokal (Server) vs Native macOS
                Menu {
                    Button {
                        speechSynthesizer.setUseLocalTTS(true)
                    } label: {
                        HStack {
                            Text("🔊 Model TTS Lokal (Server Piper/RVC)")
                            if speechSynthesizer.useLocalTTS { Image(systemName: "checkmark") }
                        }
                    }

                    Button {
                        speechSynthesizer.setUseLocalTTS(false)
                    } label: {
                        HStack {
                            Text("🍏 TTS Native macOS (Damayanti)")
                            if !speechSynthesizer.useLocalTTS { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: speechSynthesizer.useLocalTTS ? "waveform.badge.magnifyingglass" : "apple.logo")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(speechSynthesizer.useLocalTTS ? Color.purple : Color.blue)
                        Text(speechSynthesizer.useLocalTTS ? "TTS Lokal (Server)" : "TTS Native Mac")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)

                // Selector Karakter Suara Lokal
                if speechSynthesizer.useLocalTTS {
                    Menu {
                        ForEach(NativeSpeechSynthesizerService.availableSpeakers) { spk in
                            Button {
                                speechSynthesizer.setSpeaker(spk.id)
                            } label: {
                                HStack {
                                    Text(spk.displayName)
                                    if speechSynthesizer.selectedSpeaker == spk.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "person.wave.2.fill")
                                .font(.system(size: 11))
                            Text(currentSpeakerDisplayName)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.2))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                    }
                    .menuStyle(.borderlessButton)
                }

                Spacer()

                // Pengatur Kecepatan Bicara
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fx", speechSynthesizer.speechSpeed))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button("−") {
                        speechSynthesizer.setSpeed(max(0.7, speechSynthesizer.speechSpeed - 0.1))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 4)

                    Button("+") {
                        speechSynthesizer.setSpeed(min(1.5, speechSynthesizer.speechSpeed + 0.1))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)

            Spacer(minLength: 16)

            // Visualizer Orb Interaktif (Dapat diklik langsung)
            Button(action: toggleVoiceInteraction) {
                ZStack {
                    // Glow gelombang luar responsif
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: orbGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(
                            width: 140 + CGFloat(orbDynamicScale * 80),
                            height: 140 + CGFloat(orbDynamicScale * 80)
                        )
                        .blur(radius: 24)
                        .animation(.easeOut(duration: 0.15), value: speechRecognizer.audioLevel)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: speechSynthesizer.isSpeaking)

                    // Lingkaran Inti Orb
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: orbCoreColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 110, height: 110)
                        .shadow(color: orbShadowColor.opacity(0.6), radius: 18)

                    // Ikon Status
                    Image(systemName: orbIconName)
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating, value: speechRecognizer.isRecording || speechSynthesizer.isSpeaking)
                }
            }
            .buttonStyle(.plain)
            .help("Klik untuk mulai / selesai berbicara")

            // Status Teks Utama
            VStack(spacing: 6) {
                Text(statusTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)

                if let err = speechRecognizer.errorMessage {
                    Text(err)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    Text(statusSubtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 540)
                        .padding(.horizontal, 24)
                }

                // Indikator Mesin TTS yang Sedang Digunakan
                Text(speechSynthesizer.lastUsedEngineLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.purple.opacity(0.85))
                    .padding(.top, 2)
            }

            // Balasan Asisten Terakhir & Teks Pengguna
            if !lastUserPrompt.isEmpty || !assistantSpokenReply.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !lastUserPrompt.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.blue)
                                    .padding(6)
                                    .background(Color.blue.opacity(0.15))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Anda:")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.secondary)
                                    Text(lastUserPrompt)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.primary)
                                }
                            }
                        }

                        if !assistantSpokenReply.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.purple)
                                    .padding(6)
                                    .background(Color.purple.opacity(0.15))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Gemma 4:")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.purple)

                                        Spacer()

                                        if speechSynthesizer.isSpeaking {
                                            Button("Hentikan Suara") {
                                                speechSynthesizer.stop()
                                            }
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.red)
                                        } else {
                                            Button("Dengarkan Ulang") {
                                                speechSynthesizer.speak(text: assistantSpokenReply, port: aiService.activePort)
                                            }
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.blue)
                                        }
                                    }

                                    Text(assistantSpokenReply)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 580, alignment: .leading)
                    .liquidGlass(cornerRadius: 16, strokeOpacity: 0.18, tint: .purple)
                    .padding(.horizontal, 20)
                }
                .frame(maxHeight: 220)
            }

            Spacer(minLength: 20)

            // Kontrol Suara Bawah
            HStack(spacing: 16) {
                Button(action: toggleVoiceInteraction) {
                    HStack(spacing: 8) {
                        Image(systemName: controlButtonIcon)
                            .font(.system(size: 15, weight: .bold))
                        Text(controlButtonTitle)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
                    .background(controlButtonColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: controlButtonColor.opacity(0.4), radius: 10)
                }
                .buttonStyle(.plain)

                if speechSynthesizer.isSpeaking {
                    Button {
                        speechSynthesizer.stop()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.slash.fill")
                            Text("Mute")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 28)
        }
        .onDisappear {
            speechRecognizer.stopRecording(triggerFinal: false)
            speechSynthesizer.stop()
        }
    }

    // MARK: - Computed State Visuals
    private var currentSpeakerDisplayName: String {
        NativeSpeechSynthesizerService.availableSpeakers.first { $0.id == speechSynthesizer.selectedSpeaker }?.displayName ?? speechSynthesizer.selectedSpeaker
    }

    private var isBusy: Bool {
        speechRecognizer.isRecording || isProcessing || speechSynthesizer.isSpeaking
    }

    private var statusTitle: String {
        if speechSynthesizer.isSpeaking {
            return "Gemma 4 Sedang Berbicara..."
        } else if isProcessing {
            return "Memproses & Menganalisis..."
        } else if speechRecognizer.isRecording {
            return "Mendengarkan Suara Anda..."
        } else {
            return "EduVis Live Voice"
        }
    }

    private var statusSubtitle: String {
        if speechSynthesizer.isSpeaking {
            return speechSynthesizer.useLocalTTS
                ? "Membacakan respon dengan model vokal lokal: \(currentSpeakerDisplayName)"
                : "Membacakan jawaban dengan Text-to-Speech native macOS (Damayanti)."
        } else if isProcessing {
            return "LiteRT-LM GPU sedang menghasilkan balasan suara alami..."
        } else if speechRecognizer.isRecording {
            return speechRecognizer.recognizedText.isEmpty
                ? "Silakan bicara sekarang, AI menyimak..."
                : speechRecognizer.recognizedText
        } else {
            return "Tekan tombol mikrofon untuk berbicara langsung dengan Gemma 4 secara offline."
        }
    }

    private var orbDynamicScale: CGFloat {
        if speechRecognizer.isRecording {
            return CGFloat(speechRecognizer.audioLevel)
        } else if speechSynthesizer.isSpeaking {
            return 0.45
        } else {
            return 0.0
        }
    }

    private var orbIconName: String {
        if speechSynthesizer.isSpeaking {
            return "speaker.wave.3.fill"
        } else if isProcessing {
            return "sparkles"
        } else if speechRecognizer.isRecording {
            return "waveform"
        } else {
            return "mic.fill"
        }
    }

    private var orbGradientColors: [Color] {
        if speechRecognizer.isRecording {
            return [.red.opacity(0.4), .purple.opacity(0.4), .pink.opacity(0.3)]
        } else if speechSynthesizer.isSpeaking {
            return [.cyan.opacity(0.4), .blue.opacity(0.4), .purple.opacity(0.3)]
        } else {
            return [.blue.opacity(0.4), .purple.opacity(0.4), .pink.opacity(0.3)]
        }
    }

    private var orbCoreColors: [Color] {
        if speechRecognizer.isRecording {
            return [.orange, .red]
        } else if speechSynthesizer.isSpeaking {
            return [.cyan, .purple]
        } else if isProcessing {
            return [.purple, .indigo]
        } else {
            return [.blue, .purple]
        }
    }

    private var orbShadowColor: Color {
        if speechRecognizer.isRecording {
            return .red
        } else if speechSynthesizer.isSpeaking {
            return .cyan
        } else {
            return .purple
        }
    }

    private var controlButtonIcon: String {
        if speechRecognizer.isRecording {
            return "stop.fill"
        } else if speechSynthesizer.isSpeaking {
            return "stop.circle.fill"
        } else if isProcessing {
            return "xmark.circle.fill"
        } else {
            return "mic.fill"
        }
    }

    private var controlButtonTitle: String {
        if speechRecognizer.isRecording {
            return "Selesai Berbicara (Kirim)"
        } else if speechSynthesizer.isSpeaking {
            return "Hentikan Suara"
        } else if isProcessing {
            return "Batalkan"
        } else {
            return "Mulai Percakapan Suara"
        }
    }

    private var controlButtonColor: Color {
        if speechRecognizer.isRecording {
            return .red
        } else if speechSynthesizer.isSpeaking || isProcessing {
            return .orange
        } else {
            return .blue
        }
    }

    // MARK: - Actions
    private func toggleVoiceInteraction() {
        if speechRecognizer.isRecording {
            // Selesaikan rekaman dan kirim
            speechRecognizer.stopRecording(triggerFinal: true)
        } else if speechSynthesizer.isSpeaking {
            speechSynthesizer.stop()
        } else if isProcessing {
            aiService.stopStreaming()
            isProcessing = false
        } else {
            startListening()
        }
    }

    private func startListening() {
        speechSynthesizer.stop()
        speechRecognizer.startRecording(
            onUpdate: { _ in },
            onFinal: { transcribedText in
                let prompt = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !prompt.isEmpty {
                    sendSpokenPrompt(prompt)
                }
            }
        )
    }

    private func sendSpokenPrompt(_ prompt: String) {
        lastUserPrompt = prompt
        assistantSpokenReply = ""
        isProcessing = true

        let activeModel = aiService.availableModels.first?.id ?? "gemma-4-E2B-it"
        let msg = [ChatMessage(role: .user, content: prompt)]
        let cfg = GenerationConfig(
            systemPrompt: "Anda adalah asisten suara ramah EduVis AI. Jawablah langsung ke intinya dalam bahasa Indonesia yang luwes, ringkas, dan alami untuk percakapan lisan."
        )

        aiService.sendMessageStream(history: msg, model: activeModel, config: cfg) { token in
            assistantSpokenReply += token
        } onCompletion: { result in
            isProcessing = false
            switch result {
            case .success:
                if !assistantSpokenReply.isEmpty {
                    speechSynthesizer.speak(text: assistantSpokenReply, port: aiService.activePort)
                }
            case .failure(let error):
                assistantSpokenReply = "Maaf, terjadi kendala saat memproses jawaban: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 4. Vision & Dokumen (PDF, Code, CSV Extraction)
struct VisionDocWorkspaceView: View {
    @ObservedObject var aiService: LocalAIService
    @State private var attachedDocument: AttachedFile?
    @State private var promptText: String = "Analisis dokumen ini dan berikan ringkasan poin-poin utama serta temuan penting."
    @State private var analysisResult: String = ""
    @State private var isAnalyzing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Area upload dokumen
            HStack(spacing: 16) {
                if let doc = attachedDocument {
                    HStack(spacing: 10) {
                        Image(systemName: doc.fileExtension == "pdf" ? "doc.fill" : "doc.text.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.red)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.name)
                                .font(.system(size: 13, weight: .bold))
                            Text("Ukuran: \(doc.fileSize / 1024) KB • Ekstrak \(doc.contentSnippet.count) karakter")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Ganti Dokumen") {
                            pickDocument()
                        }
                        .font(.system(size: 11))
                    }
                    .padding(12)
                    .liquidGlass(cornerRadius: 12, strokeOpacity: 0.15)
                } else {
                    Button(action: pickDocument) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.rectangle.on.folder.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pilih Dokumen PDF, TXT, CSV, DOCX, atau Kode")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("Ekstraksi teks dilakukan secara offline dan aman di perangkat Mac Anda.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .liquidGlass(cornerRadius: 12, strokeOpacity: 0.15)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            Divider().opacity(0.2)

            // Hasil Analisis
            ScrollView {
                if !analysisResult.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.blue)
                            Text("Hasil Analisis Gemma 4")
                                .font(.system(size: 14, weight: .bold))
                            Spacer()
                            Button("Salin Hasil") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(analysisResult, forType: .string)
                            }
                            .font(.system(size: 11))
                        }
                        .padding(.bottom, 6)

                        Text(analysisResult)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                    .padding(18)
                    .liquidGlass(cornerRadius: 14, strokeOpacity: 0.15)
                    .padding(16)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Pilih dokumen dan jalankan instruksi analisis.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
                }
            }

            Divider().opacity(0.2)

            // Bilah Instruksi
            HStack(spacing: 12) {
                TextField("Instruksi analisis dokumen...", text: $promptText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { runAnalysis() }

                Button(action: runAnalysis) {
                    HStack(spacing: 6) {
                        if isAnalyzing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text("Analisis")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(attachedDocument == nil || isAnalyzing)
            }
            .padding(14)
            .liquidGlass(cornerRadius: 16, strokeOpacity: 0.15)
            .padding(16)
        }
    }

    private func pickDocument() {
        if let file = DocumentAnalyzerService.promptForFile() {
            attachedDocument = file
        }
    }

    private func runAnalysis() {
        guard let doc = attachedDocument else { return }
        analysisResult = ""
        isAnalyzing = true

        let combined = """
        Berikut adalah isi dokumen: '\(doc.name)'
        ========================================
        \(doc.contentSnippet)
        ========================================

        Tugas Anda:
        \(promptText)
        """

        let msg = [ChatMessage(role: .user, content: combined)]
        let cfg = GenerationConfig(temperature: 0.3)
        aiService.sendMessageStream(history: msg, model: "gemma-4-E2B-it", config: cfg) { token in
            analysisResult += token
        } onCompletion: { _ in
            isAnalyzing = false
        }
    }
}

// MARK: - 5. Analisis Kode (Code Review Workspace)
struct CodeAnalysisWorkspaceView: View {
    @ObservedObject var aiService: LocalAIService
    @State private var sourceCode: String = "// Masukkan kode Swift, Python, JS, atau C++ Anda di sini untuk dianalisis..."
    @State private var reviewResult: String = ""
    @State private var isReviewing: Bool = false

    private let presets = [
        ("Cari Bug & Keamanan", "Temukan potensi bug, celah keamanan, dan error runtime pada kode berikut:"),
        ("Refactor & Optimasi", "Lakukan refactor agar kode lebih bersih, modular, dan berperforma tinggi:"),
        ("Buat Unit Test", "Buatkan unit test komprehensif untuk kode berikut:"),
        ("Dokumentasikan", "Tambahkan dokumentasi docstring dan penjelasan detail pada setiap fungsi:")
    ]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Editor Input Kode
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(.blue)
                        Text("Kode Sumber")
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                        Button("Bersihkan") {
                            sourceCode = ""
                        }
                        .font(.system(size: 11))
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    TextEditor(text: $sourceCode)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 12)

                    // Tombol Preset
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.0) { title, prompt in
                                Button {
                                    runReview(prompt: prompt)
                                } label: {
                                    Text(title)
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.2))
                                        .foregroundStyle(Color.blue)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(isReviewing)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                }
                .frame(width: geo.size.width * 0.48)

                Divider()

                // Hasil Review
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        Text("Hasil Audit & Refactor")
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                        if isReviewing {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    ScrollView {
                        Text(reviewResult.isEmpty ? "Pilih salah satu tombol preset audit kode di sebelah kiri untuk memulai analisis otomatis." : reviewResult)
                            .font(.system(size: 13))
                            .foregroundStyle(reviewResult.isEmpty ? .secondary : .primary)
                            .lineSpacing(4)
                            .padding(14)
                            .textSelection(.enabled)
                    }
                }
                .frame(width: geo.size.width * 0.52)
                .background(Color.black.opacity(0.08))
            }
        }
    }

    private func runReview(prompt: String) {
        guard !sourceCode.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        reviewResult = ""
        isReviewing = true

        let combined = """
        \(prompt)

        ```
        \(sourceCode)
        ```
        """

        let msg = [ChatMessage(role: .user, content: combined)]
        let cfg = GenerationConfig(temperature: 0.2)
        aiService.sendMessageStream(history: msg, model: "gemma-4-E2B-it", config: cfg) { token in
            reviewResult += token
        } onCompletion: { _ in
            isReviewing = false
        }
    }
}

// MARK: - 6. Agen AI Otonom (Autonomous Agent Workspace)
struct AutonomousAgentWorkspaceView: View {
    @ObservedObject var aiService: LocalAIService
    @State private var goalText: String = "Rencanakan strategi migrasi arsitektur dari WebView ke Pure Native SwiftUI macOS."
    @State private var steps: [AgentStep] = []
    @State private var finalOutput: String = ""
    @State private var isExecuting: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header Goal / Sasaran
            VStack(alignment: .leading, spacing: 8) {
                Text("Sasaran Tugas Agen Otonom (Autonomous Goal)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    TextField("Sasaran tugas agen...", text: $goalText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))

                    Button(action: executeAgentLoop) {
                        HStack(spacing: 6) {
                            if isExecuting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text("Jalankan Agen")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.purple)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(goalText.trimmingCharacters(in: .whitespaces).isEmpty || isExecuting)
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 12, strokeOpacity: 0.15)
            .padding(16)

            Divider().opacity(0.2)

            // Timeline Langkah Berpikir Agen
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if steps.isEmpty && finalOutput.isEmpty {
                        Text("Agen akan memecah tujuan menjadi tahapan pemikiran logis (Thought -> Action -> Execution Plan).")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(30)
                    }

                    ForEach(steps) { step in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Langkah \(step.stepNumber): \(step.action)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.purple)
                                Spacer()
                            }
                            Text("💭 Pemikiran: \(step.thought)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            Text(step.observation)
                                .font(.system(size: 13))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(14)
                        .liquidGlass(cornerRadius: 12, strokeOpacity: 0.12)
                    }

                    if !finalOutput.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("🎯 Kesimpulan Akhir Agen")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.green)
                            Text(finalOutput)
                                .font(.system(size: 14))
                                .lineSpacing(4)
                        }
                        .padding(16)
                        .liquidGlass(cornerRadius: 12, strokeOpacity: 0.18, tint: .green)
                    }
                }
                .padding(16)
            }
        }
    }

    private func executeAgentLoop() {
        let goal = goalText.trimmingCharacters(in: .whitespaces)
        guard !goal.isEmpty else { return }

        steps.removeAll()
        finalOutput = ""
        isExecuting = true

        let prompt = """
        Anda adalah Agen AI Otonom berbasis Gemma 4.
        Sasaran Tugas: "\(goal)"

        Berikan rencana eksekusi terstruktur:
        1. Identifikasi kebutuhan inti
        2. Rencana aksi per langkah teknis
        3. Validasi & solusi akhir
        """

        let msg = [ChatMessage(role: .user, content: prompt)]
        let cfg = GenerationConfig(temperature: 0.4)
        aiService.sendMessageStream(history: msg, model: "gemma-4-E2B-it", config: cfg) { token in
            finalOutput += token
        } onCompletion: { _ in
            isExecuting = false
        }
    }
}

// MARK: - 7. PGlite Vector SQL (Database & RAG Inspector)
struct VectorSQLWorkspaceView: View {
    @ObservedObject var aiService: LocalAIService
    @State private var queryText: String = "SELECT * FROM knowledge_documents LIMIT 5;"
    @State private var queryResult: String = ""
    @State private var isExecuting: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Editor Query SQL
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "cylinder.split.1x2.fill")
                        .foregroundStyle(.blue)
                    Text("Pemeriksa Basis Data & Vektor RAG Lokal (SQLite/PGlite)")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                }

                TextEditor(text: $queryText)
                    .frame(height: 70)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(6)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button("Cari Dokumen RAG Terindeks") {
                        queryText = "Tampilkan ringkasan seluruh topik yang ada di basis pengetahuan lokal."
                        runSQLOrRAG()
                    }
                    .font(.system(size: 11))

                    Spacer()

                    Button(action: runSQLOrRAG) {
                        HStack(spacing: 4) {
                            if isExecuting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text("Jalankan Query")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isExecuting)
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 12, strokeOpacity: 0.15)
            .padding(16)

            Divider().opacity(0.2)

            // Hasil Output Query
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Hasil Query / Vektor Search")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    Text(queryResult.isEmpty ? "Tekan 'Jalankan Query' untuk melihat data dari basis pengetahuan lokal." : queryResult)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(queryResult.isEmpty ? .secondary : .primary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(16)
            }
        }
    }

    private func runSQLOrRAG() {
        queryResult = ""
        isExecuting = true

        var cfg = GenerationConfig()
        cfg.useKnowledgeBase = true

        let msg = [ChatMessage(role: .user, content: "Kueri Basis Pengetahuan Lokal:\n\(queryText)")]
        aiService.sendMessageStream(history: msg, model: "gemma-4-E2B-it", config: cfg) { token in
            queryResult += token
        } onCompletion: { _ in
            isExecuting = false
        }
    }
}
