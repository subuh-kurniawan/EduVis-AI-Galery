//
//  WorkspaceWebView.swift
//  EduVis Native AI
//
//  Komponen NSViewRepresentable pembungkus WKWebView berkinerja tinggi dengan jembatan native penuh:
//  - Cache instan per Ruang Kerja (OPFS, PGlite WASM, Mermaid, Chart.js, KaTeX tetap terjaga)
//  - WKScriptMessageHandler: savePng, saveSvg, saveDocument (PDF/DOCX), nativeSpeech, aiStatus (Dock Badge), appTheme
//  - WKUIDelegate: NSOpenPanel (<input type="file">), JS Alert / Confirm / Prompt
//  - Injeksi otomatis native-mac.css?v=8, eduvis-liquid-engine.js, chat-font-size.js & sinkronisasi ukuran font real-time
//

import SwiftUI
import WebKit
import AppKit
import Speech
import AVFoundation
import UniformTypeIdentifiers
import Network

final class NativeLocalWebServer: @unchecked Sendable {
    static let shared = NativeLocalWebServer()

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.eduvis.native-web-server", qos: .userInitiated)
    private var listener: NWListener?
    private var activePortValue: Int = 0
    private lazy var rootDirectoryURL: URL? = Self.resolveRootDirectoryURL()

    private init() {}

    var currentPort: Int {
        lock.lock()
        defer { lock.unlock() }
        return activePortValue
    }

    func ensureStarted() -> Int {
        lock.lock()
        if activePortValue > 0, listener != nil {
            let port = activePortValue
            lock.unlock()
            return port
        }
        lock.unlock()

        let semaphore = DispatchSemaphore(value: 0)
        var startedPort = 0

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)

            let newListener = try NWListener(using: params)
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let rawPort = newListener.port?.rawValue {
                        self.lock.lock()
                        self.activePortValue = Int(rawPort)
                        self.lock.unlock()
                        startedPort = Int(rawPort)
                    }
                    semaphore.signal()
                case .failed, .cancelled:
                    self.lock.lock()
                    if self.listener === newListener {
                        self.listener = nil
                        self.activePortValue = 0
                    }
                    self.lock.unlock()
                    semaphore.signal()
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            lock.lock()
            self.listener?.cancel()
            self.listener = newListener
            lock.unlock()

            newListener.start(queue: queue)
            _ = semaphore.wait(timeout: .now() + 2.0)

            lock.lock()
            let port = activePortValue > 0 ? activePortValue : startedPort
            lock.unlock()
            return port
        } catch {
            return 0
        }
    }

    private static func resolveRootDirectoryURL() -> URL? {
        let fm = FileManager.default
        let bundleURL = Bundle.main.bundleURL
        var candidates: [URL] = [
            bundleURL.deletingLastPathComponent().deletingLastPathComponent(),
            bundleURL.deletingLastPathComponent(),
            URL(fileURLWithPath: "/Users/subuhkurniawan/Gemma4", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Gemma4", isDirectory: true)
        ]
        if let bundledApp = Bundle.main.resourceURL?.appendingPathComponent("app", isDirectory: true) {
            candidates.append(bundledApp)
        }
        for url in candidates {
            if fm.fileExists(atPath: url.appendingPathComponent("utama.html").path) {
                return url.standardizedFileURL
            }
        }
        return nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }

            let headerDelimiter = Data("\r\n\r\n".utf8)
            let altDelimiter = Data("\n\n".utf8)
            if accumulated.range(of: headerDelimiter) != nil || accumulated.range(of: altDelimiter) != nil {
                self.processHTTPRequest(accumulated, on: connection)
                return
            }

            if isComplete || error != nil || accumulated.count > 131072 {
                if !accumulated.isEmpty {
                    self.processHTTPRequest(accumulated, on: connection)
                } else {
                    connection.cancel()
                }
                return
            }

            self.receiveRequest(on: connection, buffer: accumulated)
        }
    }

    private func processHTTPRequest(_ data: Data, on connection: NWConnection) {
        guard let rawRequest = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let firstLine = rawRequest.components(separatedBy: .newlines).first else {
            sendResponse(status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: Data("Bad Request".utf8), headOnly: false, on: connection)
            return
        }

        let parts = firstLine.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: Data("Bad Request".utf8), headOnly: false, on: connection)
            return
        }

        let method = String(parts[0]).uppercased()
        let rawTarget = String(parts[1])
        let headOnly = (method == "HEAD")

        if method == "OPTIONS" {
            sendResponse(status: "204 No Content", contentType: "text/plain; charset=utf-8", body: Data(), headOnly: true, on: connection)
            return
        }

        let pathWithoutQuery = rawTarget.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "/"
        let decodedPath = pathWithoutQuery.removingPercentEncoding ?? pathWithoutQuery

        if decodedPath == "/" {
            sendRedirect(to: "/utama.html", on: connection)
            return
        }

        switch decodedPath {
        case "/api/network-info":
            let port = currentPort
            let payload: [String: Any] = [
                "addresses": ["127.0.0.1"],
                "ui_urls": ["http://127.0.0.1:\(port)/utama.html"],
                "api_urls": ["http://127.0.0.1:\(port)/v1"],
                "ca_urls": []
            ]
            sendJSON(payload, headOnly: headOnly, on: connection)
            return

        case "/api/models":
            let models = discoverFallbackModelIDs()
            sendJSON(["models": models], headOnly: headOnly, on: connection)
            return

        case "/api/local-models":
            let files = discoverLocalLitertFiles()
            sendJSON(["files": files], headOnly: headOnly, on: connection)
            return

        case "/api/kb/snapshot":
            sendJSON(["files": [], "chunks": []], headOnly: headOnly, on: connection)
            return

        case "/api/kb/files":
            sendJSON(["files": []], headOnly: headOnly, on: connection)
            return

        case "/v1/models":
            let items = discoverFallbackModelIDs().map { id in
                ["id": id, "object": "model", "owned_by": "litert-lm"]
            }
            sendJSON(["object": "list", "data": items], headOnly: headOnly, on: connection)
            return

        default:
            break
        }

        guard let rootURL = rootDirectoryURL else {
            sendResponse(status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("Asset directory not found".utf8), headOnly: headOnly, on: connection)
            return
        }

        let relativePath = decodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fileURL = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard fileURL.path.hasPrefix(rootPrefix) else {
            sendResponse(status: "403 Forbidden", contentType: "text/plain; charset=utf-8", body: Data("Forbidden".utf8), headOnly: headOnly, on: connection)
            return
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue,
              let fileData = try? Data(contentsOf: fileURL) else {
            sendResponse(status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("Not Found".utf8), headOnly: headOnly, on: connection)
            return
        }

        let contentType = mimeType(for: fileURL.pathExtension.lowercased())
        sendResponse(status: "200 OK", contentType: contentType, body: fileData, headOnly: headOnly, on: connection)
    }

    private func discoverFallbackModelIDs() -> [String] {
        let models = NativeLiteRTEngine.shared.discoverLocalModels().map(\.id)
        if !models.isEmpty {
            return models
        }
        return ["gemma-4-E2B-it"]
    }

    private func discoverLocalLitertFiles() -> [String] {
        let fm = FileManager.default
        var dirs: [URL] = []
        if let rootDirectoryURL {
            dirs.append(rootDirectoryURL)
        }
        dirs.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true))
        var results: [String] = []
        for dir in dirs {
            if let entries = try? fm.contentsOfDirectory(atPath: dir.path) {
                for entry in entries where entry.lowercased().hasSuffix(".litertlm") {
                    if !results.contains(entry) {
                        results.append(entry)
                    }
                }
            }
        }
        return results
    }

    private func sendJSON(_ object: Any, headOnly: Bool, on connection: NWConnection) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
        sendResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: data, headOnly: headOnly, on: connection)
    }

    private func sendRedirect(to location: String, on connection: NWConnection) {
        let header = "HTTP/1.1 302 Found\r\nLocation: \(location)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendResponse(status: String, contentType: String, body: Data, headOnly: Bool, on connection: NWConnection) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cross-Origin-Opener-Policy: same-origin\r\n"
        header += "Cross-Origin-Embedder-Policy: credentialless\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Cache-Control: no-cache, no-store, must-revalidate\r\n"
        header += "Connection: close\r\n\r\n"

        var responseData = Data(header.utf8)
        if !headOnly && !body.isEmpty {
            responseData.append(body)
        }
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js", "mjs": return "application/javascript; charset=utf-8"
        case "json", "webmanifest": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "wasm": return "application/wasm"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "txt", "md": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}

private final class WorkspaceWeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
final class WorkspaceWebBridge: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var webView: WKWebView?
    var fileName: String
    var lastFontSize: Double = 15.0
    @Published var isLoadingPage: Bool = true
    var hasLoadedSuccessfully: Bool = false
    var isUsingFallbackServer: Bool = false
    var targetPort: Int = 1236
    private var retryCount: Int = 0
    private var retryWorkItem: DispatchWorkItem?
    private var attemptedFallbackLoad: Bool = false

    // Speech Recognition (macOS Native)
    private var speechRecognizer: SFSpeechRecognizer?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var speechSilenceTimer: Timer?
    private var lastSpeechTranscription: String = ""
    private var speechGeneration: Int = 0
    private lazy var speechSynthesizer = AVSpeechSynthesizer()

    init(fileName: String) {
        self.fileName = fileName
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch message.name {
            case "nativeSpeech":
                guard message.frameInfo.isMainFrame,
                      let payload = message.body as? [String: Any],
                      let action = payload["action"] as? String else { return }
                if action == "start" {
                    let defaultLanguage = Locale.preferredLanguages.first ?? Locale.current.identifier
                    let fallbackLang = defaultLanguage.lowercased().starts(with: "id") ? "id-ID" : "en-US"
                    let language = payload["language"] as? String ?? fallbackLang
                    self.startNativeSpeech(language: (language == "auto" ? fallbackLang : language))
                } else if action == "stop" {
                    self.stopNativeSpeech()
                    if self.speechSynthesizer.isSpeaking {
                        self.speechSynthesizer.stopSpeaking(at: .immediate)
                    }
                } else if action == "speak", let text = payload["text"] as? String {
                    let language = payload["language"] as? String ?? "id-ID"
                    self.speakTextNative(text, language: language)
                }

            case "savePng":
                guard message.frameInfo.isMainFrame else { return }
                self.handlePngSaveRequest(message.body)

            case "saveSvg":
                guard message.frameInfo.isMainFrame else { return }
                self.handleSvgSaveRequest(message.body)

            case "saveDocument":
                guard message.frameInfo.isMainFrame else { return }
                self.handleDocumentSaveRequest(message.body)

            case "aiStatus":
                guard message.frameInfo.isMainFrame,
                      let payload = message.body as? [String: Any] else { return }
                let isGenerating = payload["isGenerating"] as? Bool ?? false
                let badge = payload["badge"] as? String
                self.updateDockTileStatus(isGenerating: isGenerating, text: badge)

            case "openExternal":
                if let urlString = message.body as? String, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }

            case "appTheme":
                guard let theme = message.body as? String, theme == "light" || theme == "dark" else { return }
                UserDefaults.standard.set(theme, forKey: "eduvis_theme_mode")
                let appearance = NSAppearance(named: theme == "light" ? .aqua : .darkAqua)
                message.webView?.appearance = appearance

            default:
                break
            }
        }
    }

    private func activeHostWindow() -> NSWindow? {
        webView?.window ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
    }

    private func updateDockTileStatus(isGenerating: Bool, text: String? = nil) {
        if let text, !text.isEmpty {
            NSApp.dockTile.badgeLabel = text
        } else {
            NSApp.dockTile.badgeLabel = isGenerating ? "⚡ AI" : nil
        }
    }

    private func speakTextNative(_ text: String, language: String) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "id-ID")
        speechSynthesizer.speak(utterance)
    }

    // MARK: - Native Speech-to-Text Bridge

    private func startNativeSpeech(language: String, forceServer: Bool = false) {
        stopNativeSpeech(notifyEnd: false)
        speechGeneration += 1
        let generation = speechGeneration

        let requestedLocale = Locale(identifier: language)
        let resolvedRecognizer = (SFSpeechRecognizer(locale: requestedLocale)?.isAvailable == true
            ? SFSpeechRecognizer(locale: requestedLocale)
            : nil)
            ?? (SFSpeechRecognizer()?.isAvailable == true ? SFSpeechRecognizer() : nil)
            ?? SFSpeechRecognizer.supportedLocales().compactMap { SFSpeechRecognizer(locale: $0) }.first { $0.isAvailable }

        guard let recognizer = resolvedRecognizer else {
            sendNativeSpeechEvent(type: "error", error: "Pengenalan suara sistem macOS tidak aktif atau izin belum diberikan.")
            return
        }

        let beginCapture = { [weak self] in
            guard let self, self.speechGeneration == generation else { return }
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            request.contextualStrings = [
                "EduVis", "Gemma", "AI", "Halo", "Tolong", "Jelaskan",
                "Bagaimana", "Apa", "Terima kasih", "Indonesia"
            ]
            if !forceServer && recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                self.sendNativeSpeechEvent(type: "error", error: "Input mikrofon tidak tersedia.")
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            do {
                try engine.start()
            } catch {
                inputNode.removeTap(onBus: 0)
                self.sendNativeSpeechEvent(type: "error", error: "Tidak dapat memulai mikrofon: \(error.localizedDescription)")
                return
            }

            self.audioEngine = engine
            self.speechRequest = request
            self.speechRecognizer = recognizer
            self.speechTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.speechGeneration == generation else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        self.lastSpeechTranscription = text
                        self.sendNativeSpeechEvent(
                            type: "result",
                            transcript: text,
                            isFinal: result.isFinal
                        )
                        // Reset timer keheningan (VAD). Saat pengguna berhenti bicara selama 1.25 detik,
                        // finalisasi teks secara otomatis agar pesan terkirim ke AI.
                        self.speechSilenceTimer?.invalidate()
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !result.isFinal {
                            self.speechSilenceTimer = Timer.scheduledTimer(withTimeInterval: 1.25, repeats: false) { [weak self] _ in
                                DispatchQueue.main.async {
                                    guard let self, self.speechGeneration == generation else { return }
                                    let finalTranscript = self.lastSpeechTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !finalTranscript.isEmpty {
                                        self.speechRequest?.endAudio()
                                        self.sendNativeSpeechEvent(
                                            type: "result",
                                            transcript: finalTranscript,
                                            isFinal: true
                                        )
                                        self.stopNativeSpeech()
                                    }
                                }
                            }
                        }
                    }
                    if let error {
                        if request.requiresOnDeviceRecognition {
                            NSLog("Pengenalan suara on-device tidak tersedia (%@), fallback ke mode server...", error.localizedDescription)
                            self.speechSilenceTimer?.invalidate()
                            self.speechSilenceTimer = nil
                            self.startNativeSpeech(language: language, forceServer: true)
                            return
                        }
                        self.speechSilenceTimer?.invalidate()
                        self.speechSilenceTimer = nil
                        self.stopNativeSpeech(notifyEnd: false)
                        self.sendNativeSpeechEvent(type: "error", error: "Pengenalan suara: \(error.localizedDescription)")
                    } else if result?.isFinal == true {
                        self.speechSilenceTimer?.invalidate()
                        self.speechSilenceTimer = nil
                        self.stopNativeSpeech()
                    }
                }
            }
            self.sendNativeSpeechEvent(type: "start")
        }

        let requestMicrophone: (@escaping @Sendable (Bool) -> Void) -> Void = { completion in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                completion(true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
            default:
                completion(false)
            }
        }

        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard self.speechGeneration == generation else { return }
                guard status == .authorized else {
                    self.sendNativeSpeechEvent(
                        type: "error",
                        error: "Izin Pengenalan Suara ditolak. Aktifkan di Pengaturan Sistem > Privasi & Keamanan > Pengenalan Suara."
                    )
                    return
                }
                requestMicrophone { granted in
                    DispatchQueue.main.async {
                        guard self.speechGeneration == generation else { return }
                        guard granted else {
                            self.sendNativeSpeechEvent(
                                type: "error",
                                error: "Izin mikrofon ditolak. Aktifkan EduVis Native AI di Pengaturan Sistem > Privasi & Keamanan > Mikrofon."
                            )
                            return
                        }
                        beginCapture()
                    }
                }
            }
        }
    }

    private func stopNativeSpeech(notifyEnd: Bool = true) {
        speechGeneration += 1
        speechSilenceTimer?.invalidate()
        speechSilenceTimer = nil
        lastSpeechTranscription = ""
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        speechRequest?.endAudio()
        speechTask?.cancel()
        audioEngine = nil
        speechRequest = nil
        speechTask = nil
        speechRecognizer = nil
        if notifyEnd {
            sendNativeSpeechEvent(type: "end")
        }
    }

    private func sendNativeSpeechEvent(
        type: String,
        transcript: String? = nil,
        isFinal: Bool? = nil,
        error: String? = nil
    ) {
        var payload: [String: Any] = ["type": type]
        if let transcript { payload["transcript"] = transcript }
        if let isFinal { payload["isFinal"] = isFinal }
        if let error { payload["error"] = error }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('native-speech-event', { detail: \(json) }));",
            completionHandler: nil
        )
    }

    // MARK: - Save PNG / SVG / PDF / DOCX Native Dialogs

    private func handlePngSaveRequest(_ body: Any) {
        guard let payload = body as? [String: Any],
              let requestID = payload["requestID"] as? String,
              requestID.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { return }

        guard let filename = payload["filename"] as? String,
              let base64 = payload["base64"] as? String,
              base64.utf8.count <= 70 * 1024 * 1024,
              let imageData = Data(base64Encoded: base64),
              imageData.count >= 8,
              imageData.count <= 50 * 1024 * 1024 else {
            reportSaveCompletion(fn: "__nativePngSaveComplete", requestID: requestID, status: "error", detail: "Data PNG tidak valid.")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = URL(fileURLWithPath: filename).lastPathComponent

        presentSavePanel(panel) { [weak self] destination in
            guard let self else { return }
            guard let destination else {
                self.reportSaveCompletion(fn: "__nativePngSaveComplete", requestID: requestID, status: "cancelled")
                return
            }
            do {
                try imageData.write(to: destination, options: .atomic)
                self.reportSaveCompletion(fn: "__nativePngSaveComplete", requestID: requestID, status: "saved")
            } catch {
                self.reportSaveCompletion(fn: "__nativePngSaveComplete", requestID: requestID, status: "error", detail: error.localizedDescription)
            }
        }
    }

    private func handleSvgSaveRequest(_ body: Any) {
        guard let payload = body as? [String: Any],
              let requestID = payload["requestID"] as? String,
              requestID.range(of: "^[A-Za-z0-9_-]{1,96}$", options: .regularExpression) != nil else { return }

        guard let filename = payload["filename"] as? String,
              let markup = payload["markup"] as? String,
              let data = markup.data(using: .utf8),
              data.count <= 20 * 1024 * 1024,
              markup.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<svg"),
              markup.contains("</svg>"),
              !markup.localizedCaseInsensitiveContains("<!doctype"),
              !markup.localizedCaseInsensitiveContains("<!entity") else {
            reportSaveCompletion(fn: "__nativeSvgSaveComplete", requestID: requestID, status: "error", detail: "Data SVG tidak valid.")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = URL(fileURLWithPath: filename).lastPathComponent

        presentSavePanel(panel) { [weak self] destination in
            guard let self else { return }
            guard let destination else {
                self.reportSaveCompletion(fn: "__nativeSvgSaveComplete", requestID: requestID, status: "cancelled")
                return
            }
            do {
                try data.write(to: destination, options: .atomic)
                self.reportSaveCompletion(fn: "__nativeSvgSaveComplete", requestID: requestID, status: "saved")
            } catch {
                self.reportSaveCompletion(fn: "__nativeSvgSaveComplete", requestID: requestID, status: "error", detail: error.localizedDescription)
            }
        }
    }

    private func handleDocumentSaveRequest(_ body: Any) {
        guard let payload = body as? [String: Any],
              let requestID = payload["requestID"] as? String,
              requestID.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { return }

        guard let filename = payload["filename"] as? String,
              let rawMimeType = payload["mimeType"] as? String,
              let base64 = payload["base64"] as? String,
              let data = Data(base64Encoded: base64),
              data.count > 0,
              data.count <= 200 * 1024 * 1024 else {
            reportSaveCompletion(fn: "__nativeDocumentSaveComplete", requestID: requestID, status: "error", detail: "Data dokumen tidak valid.")
            return
        }

        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let contentType: UTType
        if ext == "pdf" {
            contentType = .pdf
        } else if ext == "docx" {
            contentType = UTType(filenameExtension: "docx") ?? .data
        } else if ext == "wav" {
            contentType = UTType(filenameExtension: "wav") ?? .audio
        } else if ext == "md" || ext == "markdown" {
            contentType = UTType(filenameExtension: "md") ?? .plainText
        } else if ext == "txt" {
            contentType = .plainText
        } else if let detected = UTType(mimeType: rawMimeType) {
            contentType = detected
        } else {
            contentType = .data
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.allowsOtherFileTypes = true
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = URL(fileURLWithPath: filename).lastPathComponent

        presentSavePanel(panel) { [weak self] destination in
            guard let self else { return }
            guard let destination else {
                self.reportSaveCompletion(fn: "__nativeDocumentSaveComplete", requestID: requestID, status: "cancelled")
                return
            }
            do {
                try data.write(to: destination, options: .atomic)
                self.reportSaveCompletion(fn: "__nativeDocumentSaveComplete", requestID: requestID, status: "saved")
            } catch {
                self.reportSaveCompletion(fn: "__nativeDocumentSaveComplete", requestID: requestID, status: "error", detail: error.localizedDescription)
            }
        }
    }

    private func presentSavePanel(_ panel: NSSavePanel, completion: @escaping (URL?) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        if let win = activeHostWindow(), win.isVisible && win.attachedSheet == nil {
            panel.beginSheetModal(for: win) { response in
                completion(response == .OK ? panel.url : nil)
            }
        } else {
            panel.begin { response in
                completion(response == .OK ? panel.url : nil)
            }
        }
    }

    private func reportSaveCompletion(fn: String, requestID: String, status: String, detail: String? = nil) {
        var arguments = [requestID, status]
        if let detail { arguments.append(detail) }
        guard let json = try? JSONSerialization.data(withJSONObject: arguments, options: [.fragmentsAllowed]),
              let encodedArguments = String(data: json, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript("window.\(fn)?.(...\(encodedArguments));", completionHandler: nil)
        }
    }

    // MARK: - WKUIDelegate (File Picker, Alerts, Confirms, Prompts)

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        if let win = activeHostWindow() {
            panel.beginSheetModal(for: win) { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        } else {
            panel.begin { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        }
    }

    @available(macOS 12.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Batal")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Batal")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input
        completionHandler(alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil)
    }

    // MARK: - WKNavigationDelegate

    func prepareForNewLoad(targetPort: Int) {
        cancelPendingRetry()
        self.targetPort = (targetPort == 1235 || targetPort <= 0) ? 1236 : targetPort
        self.retryCount = 0
        self.attemptedFallbackLoad = false
        self.isUsingFallbackServer = false
        self.hasLoadedSuccessfully = false
        self.isLoadingPage = true
    }

    func cancelPendingRetry() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoadingPage = true
        hasLoadedSuccessfully = false
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        isLoadingPage = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        cancelPendingRetry()
        retryCount = 0
        isLoadingPage = false
        hasLoadedSuccessfully = true
        let fallbackPort = NativeLocalWebServer.shared.currentPort
        if fallbackPort > 0 && webView.url?.port == fallbackPort {
            isUsingFallbackServer = true
        } else {
            isUsingFallbackServer = false
        }
        syncFontSize(lastFontSize)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(webView: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(webView: webView, error: error)
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           ["127.0.0.1", "localhost"].contains(challenge.protectionSpace.host),
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    private func handleNavigationFailure(webView: WKWebView, error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }

        if retryCount == 0 {
            NotificationCenter.default.post(name: .eduVisEnsureBackendRunning, object: nil)
        }

        if !attemptedFallbackLoad && retryCount < 3 {
            retryCount += 1
            cancelPendingRetry()
            let portToTry = (targetPort == 1235 || targetPort <= 0) ? 1236 : targetPort
            let targetFile = fileName
            let work = DispatchWorkItem { [weak webView] in
                guard let webView,
                      let url = URL(string: "http://127.0.0.1:\(portToTry)/\(targetFile)") else { return }
                let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4.0)
                webView.load(req)
            }
            retryWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            return
        }

        if !attemptedFallbackLoad {
            attemptedFallbackLoad = true
            let localPort = NativeLocalWebServer.shared.ensureStarted()
            if localPort > 0, let fallbackURL = URL(string: "http://127.0.0.1:\(localPort)/\(fileName)") {
                isUsingFallbackServer = true
                isLoadingPage = true
                let req = URLRequest(url: fallbackURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4.0)
                webView.load(req)
                return
            }
        }

        isLoadingPage = false
        let escapedError = error.localizedDescription
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let retryPort = (targetPort == 1235 || targetPort <= 0) ? 1236 : targetPort
        let fallbackHTML = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body {
              margin: 0; height: 100vh; display: flex; align-items: center; justify-content: center;
              font-family: -apple-system, BlinkMacSystemFont, sans-serif; color: #f5f5f7;
              background: transparent;
            }
            .card {
              max-width: 440px; padding: 24px; border-radius: 16px;
              background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.16);
              backdrop-filter: blur(20px); text-align: center;
            }
            h3 { margin: 0 0 8px; font-size: 16px; }
            p { margin: 0 0 16px; font-size: 13px; color: rgba(245,245,247,0.78); }
            button {
              padding: 8px 16px; border-radius: 10px; border: 0;
              background: #0a84ff; color: #fff; font-weight: 600; cursor: pointer;
            }
          </style>
        </head>
        <body>
          <div class="card">
            <h3>Gagal Memuat Web Studio (\(fileName))</h3>
            <p>\(escapedError)</p>
            <button onclick="window.location.href='http://127.0.0.1:\(retryPort)/\(fileName)'">Muat Ulang Sekarang</button>
          </div>
        </body>
        </html>
        """
        webView.loadHTMLString(fallbackHTML, baseURL: URL(string: "http://127.0.0.1:\(retryPort)/"))
    }

    func syncFontSize(_ size: Double) {
        lastFontSize = size
        let px = Int(max(11, min(32, size)))
        let js = """
        (() => {
            try {
                localStorage.setItem('gemma_chat_font_size', '\(px)');
                localStorage.removeItem('gemma_chat_font_size_minimized');
            } catch(_) {}
            document.documentElement.style.setProperty('--chat-font-size', '\(px)px');
            if (typeof window.setChatFontSize === 'function') {
                window.setChatFontSize(\(px));
            }
            if (typeof window.expandChatFontSizeWidget === 'function') {
                window.expandChatFontSizeWidget();
            } else {
                document.getElementById('gfc-pill')?.classList.remove('gfc-minimized');
            }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

final class WebKitWorkspacePool {
    static let shared = WebKitWorkspacePool()
    private var webViews: [String: WKWebView] = [:]
    private var bridges: [String: WorkspaceWebBridge] = [:]

    private init() {}

    @MainActor
    func getOrCreateWebView(for fileName: String, activePort: Int, initialFontSize: Double = 15.0) -> WKWebView {
        let safePort = (activePort == 1235 || activePort <= 0) ? 1236 : activePort
        if let existing = webViews[fileName], let bridge = bridges[fileName] {
            bridge.syncFontSize(initialFontSize)
            if !bridge.hasLoadedSuccessfully && !existing.isLoading {
                loadContent(into: existing, fileName: fileName, activePort: safePort)
            }
            return existing
        }

        let bridge = WorkspaceWebBridge(fileName: fileName)
        bridge.lastFontSize = initialFontSize
        bridge.targetPort = safePort
        let weakHandler = WorkspaceWeakScriptHandler(delegate: bridge)

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.setValue(true, forKey: "speechRecognitionEnabled")
        config.preferences.setValue(true, forKey: "mediaDevicesEnabled")
        config.preferences.setValue(false, forKey: "mediaCaptureRequiresSecureConnection")

        let controller = WKUserContentController()
        for handlerName in ["appTheme", "savePng", "saveSvg", "saveDocument", "nativeSpeech", "aiStatus", "openExternal"] {
            controller.add(weakHandler, name: handlerName)
        }

        let px = Int(max(11, min(32, initialFontSize)))
        controller.addUserScript(WKUserScript(
            source: """
            document.documentElement.classList.add('macos-native');
            try {
                localStorage.setItem('gemma_chat_font_size', '\(px)');
                localStorage.removeItem('gemma_chat_font_size_minimized');
            } catch(e) {}
            document.documentElement.style.setProperty('--chat-font-size', '\(px)px');
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        controller.addUserScript(WKUserScript(
            source: """
            (() => {
                document.documentElement.classList.add('macos-native');
                const existing = document.querySelector('link[href*="native-mac.css"]');
                if (existing) existing.remove();
                const link = document.createElement('link');
                link.rel = 'stylesheet';
                link.href = '/nano_asset/assets/css/native-mac.css?v=11';
                link.setAttribute('data-native-mac', '1');
                (document.body || document.documentElement).appendChild(link);

                if (!document.querySelector('script[src*="eduvis-liquid-engine.js"]')) {
                    const lgScript = document.createElement('script');
                    lgScript.src = '/nano_asset/assets/js/eduvis-liquid-engine.js?v=1';
                    lgScript.defer = true;
                    lgScript.setAttribute('data-eduvis-liquid-engine', '1');
                    (document.head || document.documentElement).appendChild(lgScript);
                }

                if (!document.querySelector('script[src*="eduvis-i18n.js"]')) {
                    const i18n = document.createElement('script');
                    i18n.src = '/nano_asset/assets/js/eduvis-i18n.js?v=1';
                    i18n.defer = true;
                    i18n.setAttribute('data-eduvis-i18n', '1');
                    (document.head || document.documentElement).appendChild(i18n);
                }

                try {
                    localStorage.removeItem('gemma_chat_font_size_minimized');
                } catch (_) {}
                if (!document.querySelector('script[src*="chat-font-size.js"]')) {
                    const fsScript = document.createElement('script');
                    fsScript.src = '/nano_asset/assets/js/chat-font-size.js?v=2';
                    fsScript.defer = true;
                    fsScript.setAttribute('data-chat-font-size', '1');
                    (document.head || document.documentElement).appendChild(fsScript);
                }
                if (typeof window.expandChatFontSizeWidget === 'function') {
                    window.expandChatFontSizeWidget();
                } else {
                    document.getElementById('gfc-pill')?.classList.remove('gfc-minimized');
                }
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        controller.addUserScript(WKUserScript(
            source: """
            (() => {
                const reportTheme = () => {
                    if (!document.body) return;
                    const isLight = document.body.classList.contains('light-theme') ||
                        document.documentElement.getAttribute('data-theme') === 'light';
                    const theme = isLight ? 'light' : 'dark';
                    window.webkit?.messageHandlers?.appTheme?.postMessage(theme);
                };
                reportTheme();
                if (document.body) {
                    new MutationObserver(reportTheme).observe(document.body, {
                        attributes: true,
                        attributeFilter: ['class']
                    });
                }
                new MutationObserver(reportTheme).observe(document.documentElement, {
                    attributes: true,
                    attributeFilter: ['data-theme']
                });
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.uiDelegate = bridge
        webView.navigationDelegate = bridge
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        bridge.webView = webView

        webViews[fileName] = webView
        bridges[fileName] = bridge

        loadContent(into: webView, fileName: fileName, activePort: safePort)
        return webView
    }

    @MainActor
    func loadContent(into webView: WKWebView, fileName: String, activePort: Int) {
        let safePort = (activePort == 1235 || activePort <= 0) ? 1236 : activePort
        bridges[fileName]?.prepareForNewLoad(targetPort: safePort)
        let httpURL = URL(string: "http://127.0.0.1:\(safePort)/\(fileName)")!
        let request = URLRequest(url: httpURL, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 4.0)
        webView.load(request)
    }

    @MainActor
    func reloadWorkspace(fileName: String, activePort: Int, clearCache: Bool = false) {
        let safePort = (activePort == 1235 || activePort <= 0) ? 1236 : activePort
        guard let wv = webViews[fileName] else { return }
        if clearCache {
            let cacheTypes = Set([WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache])
            wv.configuration.websiteDataStore.removeData(ofTypes: cacheTypes, modifiedSince: .distantPast) { [weak self, weak wv] in
                DispatchQueue.main.async {
                    guard let self, let wv else { return }
                    self.loadContent(into: wv, fileName: fileName, activePort: safePort)
                }
            }
        } else {
            if let bridge = bridges[fileName],
               ((bridge.hasLoadedSuccessfully && wv.url?.port == safePort) || (wv.isLoading && bridge.targetPort == safePort)),
               !bridge.isUsingFallbackServer {
                return
            }
            loadContent(into: wv, fileName: fileName, activePort: safePort)
        }
    }

    @MainActor
    func syncFontSize(_ size: Double, for fileName: String? = nil) {
        if let fileName {
            bridges[fileName]?.syncFontSize(size)
        } else {
            for bridge in bridges.values {
                bridge.syncFontSize(size)
            }
        }
    }

    @MainActor
    func syncTheme(_ theme: String, for fileName: String? = nil) {
        let isLight = theme == "light"
        let js = """
        (() => {
            if (!document.body) return;
            document.documentElement.setAttribute('data-theme', '\(isLight ? "light" : "dark")');
            document.body.classList.toggle('light-theme', \(isLight));
            document.body.classList.toggle('dark', \(!isLight));
            try { localStorage.setItem('gemma_theme', '\(isLight ? "light" : "dark")'); } catch(_) {}
        })();
        """
        if let fileName, let wv = webViews[fileName] {
            wv.evaluateJavaScript(js, completionHandler: nil)
        } else {
            for wv in webViews.values {
                wv.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    @MainActor
    func syncLiquidGlassOptics(blur: Double, specular: Double, saturate: Double) {
        let js = """
        (() => {
            const root = document.documentElement;
            if (!root) return;
            root.style.setProperty('--lg-blur', '\(Int(blur))px');
            root.style.setProperty('--lg-specular-opacity', '\(String(format: "%.2f", specular))');
            root.style.setProperty('--lg-saturate', '\(Int(saturate))%');
        })();
        """
        for wv in webViews.values {
            wv.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    @MainActor
    func purgeInactiveWebViews(keeping activeFileName: String) -> Int {
        let keysToRemove = webViews.keys.filter { $0 != activeFileName }
        for key in keysToRemove {
            webViews[key]?.removeFromSuperview()
            webViews.removeValue(forKey: key)
            bridges.removeValue(forKey: key)
        }
        return keysToRemove.count
    }
}

struct WorkspaceWebView: NSViewRepresentable {
    let fileName: String
    let activePort: Int
    var chatFontSize: Double = 15.0
    var reloadToken: UUID = UUID()

    final class Coordinator {
        var lastFileName: String = ""
        var lastPort: Int = 0
        var lastReloadToken: UUID = UUID()
        var lastFontSize: Double = -1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let webView = WebKitWorkspacePool.shared.getOrCreateWebView(
            for: fileName,
            activePort: activePort,
            initialFontSize: chatFontSize
        )
        attach(webView, to: container)
        context.coordinator.lastFileName = fileName
        context.coordinator.lastPort = activePort
        context.coordinator.lastReloadToken = reloadToken
        context.coordinator.lastFontSize = chatFontSize
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coord = context.coordinator
        let webView = WebKitWorkspacePool.shared.getOrCreateWebView(
            for: fileName,
            activePort: activePort,
            initialFontSize: chatFontSize
        )

        if coord.lastFileName != fileName || nsView.subviews.first !== webView {
            nsView.subviews.forEach { $0.removeFromSuperview() }
            attach(webView, to: nsView)
            coord.lastFileName = fileName
        }

        if coord.lastPort != activePort || coord.lastReloadToken != reloadToken {
            coord.lastPort = activePort
            coord.lastReloadToken = reloadToken
            WebKitWorkspacePool.shared.reloadWorkspace(fileName: fileName, activePort: activePort, clearCache: false)
        }

        if abs(coord.lastFontSize - chatFontSize) > 0.1 {
            coord.lastFontSize = chatFontSize
            WebKitWorkspacePool.shared.syncFontSize(chatFontSize, for: fileName)
        }
    }

    private func attach(_ webView: WKWebView, to container: NSView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
