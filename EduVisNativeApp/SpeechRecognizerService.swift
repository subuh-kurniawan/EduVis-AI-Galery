//
//  SpeechRecognizerService.swift
//  EduVis Native AI
//
//  Layanan pengenalan suara (STT) & sintesis teks (TTS Hybrid Native + Server) macOS.
//

import Foundation
import Speech
import AVFoundation
import AppKit

// MARK: - Local TTS Speaker Option
struct LocalTTSSpeakerOption: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let isNeural: Bool
}

// MARK: - 1. Native Speech Synthesizer & Local TTS Player (Hybrid Engine)
@MainActor
final class NativeSpeechSynthesizerService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var isSpeaking: Bool = false
    @Published var currentSpokenText: String = ""
    @Published var useLocalTTS: Bool = true
    @Published var selectedSpeaker: String = "gadis"
    @Published var speechSpeed: Double = 1.0
    @Published var isFetchingLocalAudio: Bool = false
    @Published var lastUsedEngineLabel: String = "TTS Native macOS (Damayanti)"

    static let availableSpeakers: [LocalTTSSpeakerOption] = [
        LocalTTSSpeakerOption(id: "gadis", displayName: "Gadis — Perempuan Merdu & Elegan (ID)", isNeural: false),
        LocalTTSSpeakerOption(id: "ardi", displayName: "Ardi — Pria Lembut & Bersahabat (ID)", isNeural: false),
        LocalTTSSpeakerOption(id: "wibowo", displayName: "Wibowo — Pria Dewasa & Berwibawa (ID)", isNeural: false),
        LocalTTSSpeakerOption(id: "citra", displayName: "Citra — Perempuan Ceria & Ekspresif (ID)", isNeural: false),
        LocalTTSSpeakerOption(id: "bimo", displayName: "Bimo — Narator Dokumenter & Tegas (ID)", isNeural: false),
        LocalTTSSpeakerOption(id: "sari", displayName: "Sari — Pengajar Lembut & Artikulatif (ID)", isNeural: false),
        LocalTTSSpeakerOption(id: "dimas", displayName: "Dimas — Pemuda Santai & Kasual (ID)", isNeural: false),
        LocalTTSSpeakerOption(id: "bayu", displayName: "Bayu — Pemuda Cerdas & Enerjik (ID)", isNeural: false),
        LocalTTSSpeakerOption(id: "tari", displayName: "Tari — Gadis Remaja & Ramah (ID)", isNeural: false),
        LocalTTSSpeakerOption(id: "orator", displayName: "Orator — Karismatik, Tegas & Menggelegar (ID)", isNeural: true),
        LocalTTSSpeakerOption(id: "jokowi", displayName: "Jokowi — RVC Neural 40kHz Asli (ID)", isNeural: true),
        LocalTTSSpeakerOption(id: "dewi", displayName: "Dewi — Narator Audiobook & Puitis (ID)", isNeural: false),
        LocalTTSSpeakerOption(id: "damayanti", displayName: "Damayanti — macOS Native Realtime (0ms)", isNeural: false)
    ]

    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var fetchTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
        if let savedUseLocal = UserDefaults.standard.object(forKey: "eduvis_use_local_tts") as? Bool {
            self.useLocalTTS = savedUseLocal
        }
        if let savedSpeaker = UserDefaults.standard.string(forKey: "eduvis_local_tts_speaker"), !savedSpeaker.isEmpty {
            self.selectedSpeaker = savedSpeaker
        }
        if let savedSpeed = UserDefaults.standard.object(forKey: "eduvis_local_tts_speed") as? Double, savedSpeed > 0 {
            self.speechSpeed = savedSpeed
        }
    }

    func setSpeaker(_ speaker: String) {
        selectedSpeaker = speaker
        UserDefaults.standard.set(speaker, forKey: "eduvis_local_tts_speaker")
    }

    func setUseLocalTTS(_ useLocal: Bool) {
        useLocalTTS = useLocal
        UserDefaults.standard.set(useLocal, forKey: "eduvis_use_local_tts")
    }

    func setSpeed(_ speed: Double) {
        speechSpeed = speed
        UserDefaults.standard.set(speed, forKey: "eduvis_local_tts_speed")
    }

    func speak(text: String, port: Int = 8765) {
        stop()
        let cleanText = cleanMarkdownForSpeech(text)
        guard !cleanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        currentSpokenText = cleanText

        // Jika mode TTS Lokal aktif dan speaker bukan damayanti, fetch audio dari server lokal
        if useLocalTTS && selectedSpeaker != "damayanti" {
            fetchAndPlayLocalTTS(text: cleanText, speaker: selectedSpeaker, speed: speechSpeed, primaryPort: port)
        } else {
            speakNativeMac(text: cleanText)
        }
    }

    func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        isFetchingLocalAudio = false

        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        audioPlayer = nil

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    private func fetchAndPlayLocalTTS(text: String, speaker: String, speed: Double, primaryPort: Int) {
        isFetchingLocalAudio = true
        isSpeaking = true
        lastUsedEngineLabel = "Menghubungkan model vokal TTS lokal (\(speaker))..."

        fetchTask = Task { [weak self] in
            guard let self else { return }
            let portsToTry = [primaryPort, 8765, 1236, 1234]
            var fetchedData: Data?

            for port in portsToTry {
                if Task.isCancelled { break }
                guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let encodedSpeaker = speaker.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: "http://127.0.0.1:\(port)/api/tts?text=\(encodedText)&speaker=\(encodedSpeaker)&speed=\(speed)") else { continue }

                var request = URLRequest(url: url)
                request.timeoutInterval = 8.0
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 44 {
                        fetchedData = data
                        break
                    }
                } catch {
                    continue
                }
            }

            guard !Task.isCancelled else {
                await MainActor.run { self.isSpeaking = false; self.isFetchingLocalAudio = false }
                return
            }

            await MainActor.run {
                self.isFetchingLocalAudio = false
                if let data = fetchedData {
                    do {
                        let player = try AVAudioPlayer(data: data)
                        player.delegate = self
                        player.prepareToPlay()
                        player.play()
                        self.audioPlayer = player
                        self.isSpeaking = true
                        let speakerName = Self.availableSpeakers.first { $0.id == speaker }?.displayName ?? speaker
                        self.lastUsedEngineLabel = "TTS Lokal: \(speakerName)"
                    } catch {
                        self.lastUsedEngineLabel = "TTS lokal gagal; beralih ke Native Damayanti"
                        self.speakNativeMac(text: text)
                    }
                } else {
                    self.lastUsedEngineLabel = "Server TTS offline; beralih ke Native Damayanti"
                    self.speakNativeMac(text: text)
                }
            }
        }
    }

    private func speakNativeMac(text: String) {
        lastUsedEngineLabel = "TTS Native macOS (Damayanti)"
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = resolveVoice(for: "id-ID")
        utterance.rate = Float(AVSpeechUtteranceDefaultSpeechRate) * Float(speechSpeed)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    private func resolveVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        // 1. Cari suara bahasa Indonesia: Damayanti atau id-ID
        if let indonesian = allVoices.first(where: { $0.language.hasPrefix("id") && $0.name.contains("Damayanti") }) ??
                             allVoices.first(where: { $0.language.hasPrefix("id") && $0.quality == .premium }) ??
                             allVoices.first(where: { $0.language.hasPrefix("id") && $0.quality == .enhanced }) ??
                             allVoices.first(where: { $0.language.hasPrefix("id") }) {
            return indonesian
        }

        // 2. Coba AVSpeechSynthesisVoice langsung dengan identifier bahasa
        if let direct = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "id-ID") {
            return direct
        }

        // 3. Fallback ke suara sistem macOS default
        return AVSpeechSynthesisVoice(language: Locale.current.identifier) ?? allVoices.first
    }

    private func cleanMarkdownForSpeech(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "```[\\s\\S]*?```", with: " potongan kode disembunyikan. ", options: .regularExpression)
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "[#*~_>|]", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AVSpeechSynthesizerDelegate
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    // MARK: - AVAudioPlayerDelegate
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

// MARK: - 2. Native Speech Recognizer (STT)
@MainActor
final class SpeechRecognizerService: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var recognizedText: String = ""
    @Published var audioLevel: Float = 0.0
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var microphoneAuthorized: Bool = false
    @Published var selectedLocaleIdentifier: String = "id-ID"
    @Published var errorMessage: String? = nil

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastSpokenText: String = ""
    private var onFinalTranscriptionCallback: ((String) -> Void)?

    init() {
        requestAuthorization()
    }

    func requestAuthorization() {
        // 1. Izin Pengenalan Suara
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
            }
        }

        // 2. Izin Mikrofon macOS
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    self?.microphoneAuthorized = granted
                }
            }
        default:
            microphoneAuthorized = false
        }
    }

    func toggleRecording(onUpdate: @escaping (String) -> Void) {
        toggleRecording(onUpdate: onUpdate, onFinal: nil)
    }

    func toggleRecording(
        onUpdate: @escaping (String) -> Void,
        onFinal: ((String) -> Void)?
    ) {
        if isRecording {
            stopRecording(triggerFinal: true)
        } else {
            startRecording(onUpdate: onUpdate, onFinal: onFinal)
        }
    }

    func startRecording(
        onUpdate: @escaping (String) -> Void = { _ in },
        onFinal: ((String) -> Void)? = nil
    ) {
        stopRecording(triggerFinal: false)
        errorMessage = nil
        onFinalTranscriptionCallback = onFinal

        // Mainkan nada mulai (Tink)
        playFeedbackTone(isStart: true)

        let localeIdentifier = selectedLocaleIdentifier == "auto" ? "id-ID" : selectedLocaleIdentifier
        let requestedLocale = Locale(identifier: localeIdentifier)

        // Cari recognizer yang tersedia dengan fallback cerdas
        let resolvedRecognizer = (SFSpeechRecognizer(locale: requestedLocale)?.isAvailable == true
            ? SFSpeechRecognizer(locale: requestedLocale)
            : nil)
            ?? (SFSpeechRecognizer()?.isAvailable == true ? SFSpeechRecognizer() : nil)
            ?? SFSpeechRecognizer.supportedLocales().compactMap { SFSpeechRecognizer(locale: $0) }.first { $0.isAvailable }

        guard let recognizer = resolvedRecognizer else {
            errorMessage = "Pengenalan suara tidak aktif di macOS. Pastikan fitur Dikte diaktifkan di Pengaturan Sistem > Papan Ketik."
            recognizedText = errorMessage ?? ""
            return
        }

        // Cek izin mikrofon
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    self?.microphoneAuthorized = granted
                    if granted {
                        self?.startRecording(onUpdate: onUpdate, onFinal: onFinal)
                    } else {
                        self?.errorMessage = "Izin mikrofon diperlukan. Berikan izin di Pengaturan Sistem > Privasi & Keamanan > Mikrofon."
                    }
                }
            }
            return
        } else if micStatus == .denied || micStatus == .restricted {
            errorMessage = "Izin mikrofon ditolak. Berikan izin EduVis di Pengaturan Sistem > Privasi & Keamanan > Mikrofon."
            return
        }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = [
            "EduVis", "Gemma", "AI", "Halo", "Tolong", "Jelaskan",
            "Bagaimana", "Apa", "Terima kasih", "Indonesia"
        ]

        // Hanya gunakan on-device jika Mac telah mengunduh model offline-nya
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.channelCount > 0, recordingFormat.sampleRate > 0 else {
            errorMessage = "Input mikrofon tidak aktif atau tidak ditemukan."
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)

            // Hitung level audio untuk animasi visualizer gelombang suara
            let channelData = buffer.floatChannelData?[0]
            let frames = buffer.frameLength
            if let channelData, frames > 0 {
                var sum: Float = 0
                for i in 0..<Int(frames) {
                    sum += abs(channelData[i])
                }
                let avg = sum / Float(frames)
                Task { @MainActor in
                    self?.audioLevel = min(1.0, avg * 6.0)
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
            isRecording = true
        } catch {
            isRecording = false
            errorMessage = "Gagal memulai mikrofon: \(error.localizedDescription)"
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.recognizedText = text
                    self.lastSpokenText = text
                    onUpdate(text)

                    self.silenceTimer?.invalidate()
                    // Adaptive VAD: beri jeda ekstra 2.6 detik jika kalimat menggantung / pengguna sedang berpikir, atau 1.8 detik normal
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedText.isEmpty && !result.isFinal {
                        let lowerWords = trimmedText.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
                        let thinkingWords: Set<String> = [
                            "dan", "atau", "yang", "karena", "kalau", "jika", "terus", "lalu", "jadi",
                            "untuk", "dengan", "tentang", "seperti", "eee", "ee", "eh", "emm", "em",
                            "hmm", "hm", "anu", "maksudnya", "yaitu", "adalah", "nah", "tapi", "tetapi",
                            "namun", "soalnya", "supaya", "agar", "dari", "di", "ke", "pada", "bahwa",
                            "sehingga", "misalnya", "contohnya", "kemudian", "terkait"
                        ]
                        let isThinkingPause = lowerWords.count <= 2 || (lowerWords.last.map { thinkingWords.contains($0) } ?? false)
                        let pauseDuration: TimeInterval = isThinkingPause ? 2.6 : 1.8
                        self.silenceTimer = Timer.scheduledTimer(withTimeInterval: pauseDuration, repeats: false) { [weak self] _ in
                            Task { @MainActor in
                                guard let self, self.isRecording else { return }
                                self.stopRecording(triggerFinal: true)
                            }
                        }
                    }
                }
                if error != nil {
                    // Fallback otomatis dari on-device ke server jika paket on-device belum terpasang
                    if request.requiresOnDeviceRecognition {
                        request.requiresOnDeviceRecognition = false
                        return
                    }
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = nil
                    self.stopRecording(triggerFinal: !self.lastSpokenText.isEmpty)
                } else if result?.isFinal ?? false {
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = nil
                    self.stopRecording(triggerFinal: true)
                }
            }
        }
    }

    func stopRecording(triggerFinal: Bool = true) {
        silenceTimer?.invalidate()
        silenceTimer = nil

        let finalText = lastSpokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        lastSpokenText = ""

        if isRecording {
            playFeedbackTone(isStart: false)
        }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isRecording = false
        audioLevel = 0.0

        if triggerFinal && !finalText.isEmpty {
            onFinalTranscriptionCallback?(finalText)
        }
        onFinalTranscriptionCallback = nil
    }

    private func playFeedbackTone(isStart: Bool) {
        // Nada sistem macOS "Tink" (mulai mendengarkan) & "Pop" (mulai memproses)
        NSSound(named: isStart ? "Tink" : "Pop")?.play()
    }
}
