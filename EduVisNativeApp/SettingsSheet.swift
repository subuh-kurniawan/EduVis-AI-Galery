//
//  SettingsSheet.swift
//  EduVis Native AI
//
//  Lembar pengaturan model LLM, parameter inferensi, dan konfigurasi server lokal.
//

import SwiftUI
import AVFoundation

struct SettingsSheet: View {
    @Binding var config: GenerationConfig
    @AppStorage("gemma_chat_font_size") private var chatFontSize: Double = 15.0
    @AppStorage("eduvis_use_local_tts") private var useLocalTTS: Bool = true
    @AppStorage("eduvis_local_tts_speaker") private var selectedSpeaker: String = "gadis"
    @AppStorage("eduvis_local_tts_speed") private var speechSpeed: Double = 1.0

    @Environment(\.dismiss) private var dismiss
    @State private var syncStatusMessage: String = ""
    @State private var isSyncingModels: Bool = false
    @State private var isTestingTTS: Bool = false
    @State private var testTTSStatus: String = ""
    @State private var testAudioPlayer: AVAudioPlayer?
    @State private var testSynthesizer = AVSpeechSynthesizer()

    private let backendOptions: [(id: String, label: String)] = [
        ("gpu", "GPU (Metal / Akselerasi Apple Silicon)"),
        ("cpu", "CPU (XNNPACK)"),
        ("npu", "NPU (Neural Engine)")
    ]

    private let reasoningOptions: [(id: String, label: String)] = [
        ("none", "Mati (Cepat)"),
        ("minimal", "Minimal"),
        ("low", "Low"),
        ("medium", "Medium"),
        ("high", "High (Mendalam)")
    ]

    private let runtimeModeOptions: [(id: String, label: String)] = [
        ("auto", "Otomatis (Hybrid Server + Pure Swift)"),
        ("pure_swift", "Pure Swift LiteRTLM (In-Process · Tanpa Python)"),
        ("python_server", "Server Python (litert-lm serve · LAN & Web)")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Bahasa & Wilayah (Language & Region)") {
                    Picker("Bahasa Tampilan & Suara", selection: $config.appLanguage) {
                        Text("Otomatis (Mac)").tag("auto")
                        Text("English (US)").tag("en")
                        Text("Indonesia").tag("id")
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Pengaturan Aktif")
                        Spacer()
                        Text(config.effectiveLanguage == "en" ? "🇺🇸 English (US · en-US)" : "🇮🇩 Bahasa Indonesia (id-ID)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tint)
                    }
                }

                Section("Sintesis Suara & TTS Lokal (Voice & TTS)") {
                    Toggle("Gunakan TTS Lokal (Server Piper & RVC)", isOn: $useLocalTTS)
                        .help("Memakai server suara offline lokal (port 8765/1236) untuk menghasilkan audio vokal alami bahasa Indonesia")

                    if useLocalTTS {
                        Picker("Karakter Vokal Indonesia", selection: $selectedSpeaker) {
                            ForEach(NativeSpeechSynthesizerService.availableSpeakers) { spk in
                                Text(spk.displayName).tag(spk.id)
                            }
                        }

                        HStack {
                            Text("Kecepatan Artikulasi")
                            Spacer()
                            Text(String(format: "%.1fx", speechSpeed))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $speechSpeed, in: 0.7...1.5, step: 0.1)

                        HStack {
                            Button {
                                Task { await testVoiceSample() }
                            } label: {
                                HStack(spacing: 6) {
                                    if isTestingTTS {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "speaker.wave.2.fill")
                                    }
                                    Text("Uji Coba Karakter Suara Ini")
                                }
                            }
                            .disabled(isTestingTTS)

                            Spacer()

                            if !testTTSStatus.isEmpty {
                                Text(testTTSStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "apple.logo")
                            Text("Menggunakan AVSpeechSynthesizer macOS (Damayanti · Bahasa Indonesia)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Tampilan Percakapan (Chat UI)") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Ukuran Teks Chat")
                            Spacer()
                            Text("\(Int(chatFontSize)) px")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $chatFontSize, in: 11.0...24.0, step: 1.0)
                        HStack {
                            Text("Kecil (11px)").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("Standar (15px)").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("Besar (24px)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Koneksi Backend Lokal") {
                    TextField("Host Server", text: $config.serverHost)
                    Stepper("Port Backend: \(config.serverPort)", value: $config.serverPort, in: 1024...65535)

                    Toggle("Aktifkan Basis Pengetahuan (SQLite RAG)", isOn: $config.useKnowledgeBase)
                        .help("Menyematkan header X-EduVis-Use-KB: 1 pada setiap permintaan inferensi")
                }

                Section("Parameter Inferensi Gemma") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", config.temperature))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $config.temperature, in: 0.0...1.5, step: 0.05)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Top P")
                            Spacer()
                            Text(String(format: "%.2f", config.topP))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $config.topP, in: 0.1...1.0, step: 0.05)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max Tokens")
                            Spacer()
                            Text("\(config.maxTokens)")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(config.maxTokens) },
                            set: { config.maxTokens = Int($0) }
                        ), in: 256...4096, step: 128)
                    }
                }

                Section("Runtime & Akselerasi LiteRT-LM (v0.19)") {
                    Picker("Mode Mesin Inferensi", selection: $config.runtimeMode) {
                        ForEach(runtimeModeOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(NativeLiteRTEngine.shared.isAvailable ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(NativeLiteRTEngine.shared.statusSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Backend Eksekusi", selection: $config.backend) {
                        ForEach(backendOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }

                    Toggle("Speculative Decoding (MTP Drafter)", isOn: $config.speculativeDecoding)
                        .help("Memanfaatkan model drafter Multi-Token Prediction untuk mempercepat generasi token")

                    Picker("Mode Penalaran (Thinking Effort)", selection: $config.reasoningEffort) {
                        ForEach(reasoningOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Top-K")
                            Spacer()
                            Text("\(config.topK)")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(config.topK) },
                            set: { config.topK = Int($0) }
                        ), in: 1...100, step: 1)
                    }

                    HStack {
                        Button {
                            Task { await syncProjectModels() }
                        } label: {
                            HStack(spacing: 6) {
                                if isSyncingModels {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                Text("Sinkronkan Model Proyek (.litertlm)")
                            }
                        }
                        .disabled(isSyncingModels)

                        Spacer()
                    }

                    if !syncStatusMessage.isEmpty {
                        Text(syncStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Sistem Prompt") {
                    TextEditor(text: $config.systemPrompt)
                        .frame(minHeight: 80)
                        .font(.system(size: 13, design: .monospaced))
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Pengaturan Inferensi AI")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") {
                        Task { await pushRuntimeConfig() }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Atur Ulang") {
                        config = GenerationConfig()
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 560)
    }

    private func backendScheme() -> String {
        config.serverPort == 1234 ? "https" : "http"
    }

    @MainActor
    private func pushRuntimeConfig() async {
        let scheme = backendScheme()
        guard let url = URL(string: "\(scheme)://\(config.serverHost):\(config.serverPort)/api/litert-config") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 4.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "backend": config.backend,
            "speculative_decoding": config.speculativeDecoding,
            "top_k": config.topK,
            "thinking": config.reasoningEffort != "none"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
        _ = try? await session.data(for: request)
    }

    @MainActor
    private func syncProjectModels() async {
        isSyncingModels = true
        defer { isSyncingModels = false }
        await pushRuntimeConfig()

        let scheme = backendScheme()
        guard let url = URL(string: "\(scheme)://\(config.serverHost):\(config.serverPort)/api/models/sync-local") else {
            syncStatusMessage = "URL server lokal tidak valid."
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                syncStatusMessage = "Gagal menyinkronkan model dari server port \(config.serverPort)."
                return
            }
            let synced = json["synced_models"] as? [String] ?? []
            let registered = json["registered_models"] as? [String] ?? []
            let version = (json["litert_lm_version"] as? String) ?? "0.19"
            if !synced.isEmpty {
                syncStatusMessage = "LiteRT-LM v\(version): \(synced.count) model baru disinkronkan (\(synced.joined(separator: ", ")))."
            } else {
                syncStatusMessage = "LiteRT-LM v\(version): \(registered.count) model lokal sudah sinkron."
            }
            NotificationCenter.default.post(name: .eduVisModelsDidSync, object: nil)
        } catch {
            syncStatusMessage = "Sinkronisasi gagal: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func testVoiceSample() async {
        isTestingTTS = true
        testTTSStatus = "Menyiapkan audio..."
        defer { isTestingTTS = false }

        let sampleText = "Halo! Ini adalah contoh kualitas suara karakter vokal EduVis AI."

        if selectedSpeaker == "damayanti" || !useLocalTTS {
            let utterance = AVSpeechUtterance(string: sampleText)
            utterance.voice = AVSpeechSynthesisVoice(language: "id-ID")
            utterance.rate = Float(AVSpeechUtteranceDefaultSpeechRate) * Float(speechSpeed)
            testSynthesizer.speak(utterance)
            testTTSStatus = "Memutar Damayanti Native."
            return
        }

        let ports = [config.serverPort, 8765, 1236, 1234]
        var audioData: Data?

        for port in ports {
            guard let encodedText = sampleText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let encodedSpk = selectedSpeaker.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "http://127.0.0.1:\(port)/api/tts?text=\(encodedText)&speaker=\(encodedSpk)&speed=\(speechSpeed)") else {
                continue
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 6.0
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 44 {
                    audioData = data
                    break
                }
            } catch {
                continue
            }
        }

        if let data = audioData {
            do {
                let player = try AVAudioPlayer(data: data)
                player.prepareToPlay()
                player.play()
                self.testAudioPlayer = player
                let speakerName = NativeSpeechSynthesizerService.availableSpeakers.first { $0.id == selectedSpeaker }?.displayName ?? selectedSpeaker
                testTTSStatus = "Memutar: \(speakerName)"
            } catch {
                testTTSStatus = "Gagal memutar audio: \(error.localizedDescription)"
            }
        } else {
            testTTSStatus = "Server TTS offline. Memakai fallback macOS..."
            let utterance = AVSpeechUtterance(string: sampleText)
            utterance.voice = AVSpeechSynthesisVoice(language: "id-ID")
            testSynthesizer.speak(utterance)
        }
    }
}
