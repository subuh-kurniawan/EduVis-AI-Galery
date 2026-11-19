//
//  LocalAIService.swift
//  EduVis Native AI
//
//  Layanan jaringan asynchronous native & pengelola proses backend lokal Gemma 4.
//  Mendukung HTTP port 1236, 1235 (LiteRT-LM), dan HTTPS port 1234 (dengan self-signed bypass).
//

import Foundation
import AppKit

extension Notification.Name {
    static let eduVisEnsureBackendRunning = Notification.Name("eduVisEnsureBackendRunning")
}

final class SelfSignedSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}

@MainActor
final class LocalAIService: ObservableObject {
    @Published var health: BackendHealth = .checking
    @Published var availableModels: [ModelOption] = [
        ModelOption(id: "gemma-4-E2B-it", displayName: "Gemma 4 (E2B-IT)", tag: "Cepat & Ringan", isRecommended: true),
        ModelOption(id: "gemma-4-E4B-it", displayName: "Gemma 4 (E4B-IT)", tag: "Akurasi Tinggi", isRecommended: false),
        ModelOption(id: "gemma-3n-E4B-it-int4-Web", displayName: "Gemma 3n (E4B-IT)", tag: "Multimodal", isRecommended: false)
    ]
    @Published var inspectedModels: [ModelInspectionInfo] = []
    @Published var litertVersion: String = "0.19.x"
    @Published var nativeEngineAvailable: Bool = false
    @Published var activeRuntimeLabel: String = "Server Lokal"
    @Published var activePort: Int = 1236
    @Published var isWebServerOnline: Bool = false
    @Published var webUIPort: Int = 1236
    @Published var webServerReadyToken: UUID = UUID()
    @Published var isStreaming: Bool = false
    @Published var isStartingBackend: Bool = false
    @Published var backendStatusMessage: String = ""

    private var activeTask: Task<Void, Never>?
    private var backendProcess: Process?
    private var session: URLSession
    private var syncObserver: NSObjectProtocol?
    private var backendEnsureObserver: NSObjectProtocol?

    // Prioritas: port 1236 (HTTP UI/API), 1235 (LiteRT-LM direct HTTP), 1234 (HTTPS)
    private let targetEndpoints: [(scheme: String, port: Int)] = [
        ("http", 1236),
        ("http", 1235),
        ("https", 1234)
    ]

    private var activeScheme: String = "http"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: config, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)

        Task {
            await probeAndRefresh()
            if !isWebServerOnline {
                // Pastikan server web lokal (port 1236) selalu dimulai meskipun Pure Swift tersedia
                _ = await startLocalBackend()
            }
        }

        syncObserver = NotificationCenter.default.addObserver(
            forName: .eduVisModelsDidSync,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.probeAndRefresh()
            }
        }

        backendEnsureObserver = NotificationCenter.default.addObserver(
            forName: .eduVisEnsureBackendRunning,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.ensureWebServerRunning()
            }
        }
    }

    deinit {
        if let syncObserver {
            NotificationCenter.default.removeObserver(syncObserver)
        }
        if let backendEnsureObserver {
            NotificationCenter.default.removeObserver(backendEnsureObserver)
        }
        backendProcess?.terminate()
    }

    func ensureWebServerRunning() async {
        if await testWebUIEndpoint(port: 1236) {
            let changed = !isWebServerOnline || webUIPort != 1236
            isWebServerOnline = true
            webUIPort = 1236
            if activePort == 1235 {
                activePort = 1236
            }
            if changed {
                webServerReadyToken = UUID()
            }
            return
        }
        isWebServerOnline = false
        if !isStartingBackend {
            _ = await startLocalBackend()
        }
    }

    func testWebUIEndpoint(port: Int = 1236) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/utama.html") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.5

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
        } catch {
            // Port web UI belum siap
        }
        return false
    }

    func probeAndRefresh() async {
        health = .checking
        nativeEngineAvailable = NativeLiteRTEngine.shared.isAvailable

        let webReady = await testWebUIEndpoint(port: 1236)
        if webReady {
            let changed = !isWebServerOnline || webUIPort != 1236
            isWebServerOnline = true
            webUIPort = 1236
            if changed {
                webServerReadyToken = UUID()
            }
        } else {
            isWebServerOnline = false
        }

        for target in targetEndpoints {
            if await testEndpoint(scheme: target.scheme, port: target.port) {
                activeScheme = target.scheme
                // Jangan pernah gunakan port 1235 sebagai port WebView/UI
                activePort = (target.port == 1235 && webReady) ? 1236 : target.port
                if webReady {
                    webUIPort = 1236
                }
                let modelPort = target.port
                if modelPort == 1235 && !webReady && nativeEngineAvailable {
                    loadModelsFromPureSwift()
                    activeRuntimeLabel = "Server Lokal (HTTP:1235)"
                } else {
                    activeRuntimeLabel = "Server Lokal (\(target.scheme.uppercased()):\(activePort))"
                    await loadModelsFromBackend(scheme: target.scheme, port: target.port)
                }
                health = .online(details: "Tersambung ke \(target.scheme.uppercased()) port \(target.port)")
                return
            }
        }

        if webReady {
            activePort = 1236
            webUIPort = 1236
        }

        if nativeEngineAvailable {
            loadModelsFromPureSwift()
            activeRuntimeLabel = "Pure Swift LiteRTLM"
            health = .online(details: webReady
                ? "Pure Swift LiteRTLM + Web Server Lokal :1236"
                : "Pure Swift LiteRTLM Aktif (Tanpa Python)")
            return
        }
        health = .offline(error: "Backend belum aktif di port 1236 / 1235 / 1234")
    }

    private func loadModelsFromPureSwift() {
        let localModels = NativeLiteRTEngine.shared.discoverLocalModels()
        if !localModels.isEmpty {
            self.availableModels = localModels
        }
        let inspected = NativeLiteRTEngine.shared.inspectLocalModels()
        if !inspected.isEmpty {
            self.inspectedModels = inspected
        }
        self.litertVersion = "0.19.2 (Pure Swift)"
    }

    private func testEndpoint(scheme: String, port: Int) async -> Bool {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/v1/models") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.0

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return true
            }
        } catch {
            // Port belum siap
        }
        return false
    }

    private func loadModelsFromBackend(scheme: String, port: Int) async {
        // Sinkronisasi zero-copy model proyek & muat metadata ModelInfo (v0.19)
        await syncLocalModels(scheme: scheme, port: port)

        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/v1/models") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0

        do {
            let (data, _) = try await session.data(for: request)
            struct ModelResponse: Decodable {
                struct Item: Decodable {
                    let id: String
                }
                let data: [Item]?
            }
            if let parsed = try? JSONDecoder().decode(ModelResponse.self, from: data),
               let items = parsed.data, !items.isEmpty {
                let models = items.map { item in
                    ModelOption(
                        id: item.id,
                        displayName: item.id.replacingOccurrences(of: ".litertlm", with: ""),
                        tag: "Lokal",
                        isRecommended: item.id.contains("E2B")
                    )
                }
                self.availableModels = models
            }
        } catch {
            // Tetap gunakan model bawaan jika parsing gagal
        }

        await fetchInspectedModels(scheme: scheme, port: port)
    }

    private func syncLocalModels(scheme: String, port: Int) async {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/api/models/sync-local") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        _ = try? await session.data(for: request)
    }

    private func fetchInspectedModels(scheme: String, port: Int) async {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/api/models/inspect") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            struct InspectPayload: Decodable {
                let models: [ModelInspectionInfo]?
                let litertLMVersion: String?
                enum CodingKeys: String, CodingKey {
                    case models
                    case litertLMVersion = "litert_lm_version"
                }
            }
            let parsed = try JSONDecoder().decode(InspectPayload.self, from: data)
            if let version = parsed.litertLMVersion, !version.isEmpty {
                self.litertVersion = version
            }
            if let models = parsed.models {
                self.inspectedModels = models
            }
        } catch {
            // Abaikan jika endpoint inspect belum tersedia
        }
    }

    func resolveProjectURL() -> URL? {
        let fm = FileManager.default
        let currentExecutable = Bundle.main.bundleURL
        var candidates: [URL] = [
            currentExecutable.deletingLastPathComponent().deletingLastPathComponent(),
            currentExecutable.deletingLastPathComponent(),
            URL(fileURLWithPath: "/Users/subuhkurniawan/Gemma4", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Gemma4")
        ]
        if let bundledApp = Bundle.main.resourceURL?.appendingPathComponent("app", isDirectory: true) {
            candidates.append(bundledApp)
        }
        for url in candidates {
            if fm.fileExists(atPath: url.appendingPathComponent("gemma_chat_gui.py").path)
                && fm.fileExists(atPath: url.appendingPathComponent("utama.html").path) {
                return url
            }
        }
        return nil
    }

    func resolvePythonExecutable() -> String? {
        let fm = FileManager.default
        let venvPython = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Gemma AI Gallery/litert-lm-venv/bin/python3").path
        let candidates = [
            venvPython,
            "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/Library/Developer/CommandLineTools/usr/bin/python3",
            "/usr/bin/python3"
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    func startLocalBackend() async -> Bool {
        guard !isStartingBackend else { return false }
        nativeEngineAvailable = NativeLiteRTEngine.shared.isAvailable
        guard let projectURL = resolveProjectURL(),
              let pythonPath = resolvePythonExecutable() else {
            if nativeEngineAvailable {
                loadModelsFromPureSwift()
                activeRuntimeLabel = "Pure Swift LiteRTLM"
                health = .online(details: "Pure Swift LiteRTLM Aktif (Tanpa Python)")
                backendStatusMessage = "Menggunakan mesin Pure Swift LiteRTLM in-process."
                return true
            }
            backendStatusMessage = "File gemma_chat_gui.py atau Python 3.10+ tidak ditemukan."
            return false
        }

        let scriptURL = projectURL.appendingPathComponent("gemma_chat_gui.py")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            if nativeEngineAvailable {
                loadModelsFromPureSwift()
                activeRuntimeLabel = "Pure Swift LiteRTLM"
                health = .online(details: "Pure Swift LiteRTLM Aktif (Tanpa Python)")
                return true
            }
            backendStatusMessage = "Skrip backend tidak ditemukan di \(scriptURL.path)"
            return false
        }

        isStartingBackend = true
        backendStatusMessage = "Menyiapkan environment LiteRT-LM (pertama kali dijalankan)..."

        let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/EduVis AI Gallery", isDirectory: true)
        let readinessURL = appSupportDir.appendingPathComponent("ready")

        do {
            try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: readinessURL)
        } catch {
            // Lanjutkan jika folder sudah ada
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            scriptURL.path,
            "--backend-only",
            "--readiness",
            readinessURL.path
        ]

        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/Library/Frameworks/Python.framework/Versions/3.14/bin",
            "/Library/Frameworks/Python.framework/Versions/Current/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin"
        ]
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = extraPaths.joined(separator: ":") + ":" + currentPath
        process.environment = env
        process.currentDirectoryURL = projectURL

        do {
            try process.run()
            self.backendProcess = process
            backendStatusMessage = "Memulai runtime LiteRT-LM & memuat model..."

            let bootstrapStatusURL = appSupportDir.appendingPathComponent("bootstrap_status.json")
            // Tunggu hingga backend merespons (hingga 180 detik pada eksekusi pertama untuk auto-setup)
            for _ in 0..<720 {
                try await Task.sleep(nanoseconds: 250_000_000)
                if !process.isRunning {
                    break
                }
                if let bData = try? Data(contentsOf: bootstrapStatusURL),
                   let bJson = try? JSONSerialization.jsonObject(with: bData) as? [String: Any],
                   let msg = bJson["message"] as? String, !msg.isEmpty {
                    backendStatusMessage = msg
                }

                if !isWebServerOnline, await testWebUIEndpoint(port: 1236) {
                    isWebServerOnline = true
                    webUIPort = 1236
                    activePort = 1236
                    webServerReadyToken = UUID()
                }

                let readinessReady = FileManager.default.fileExists(atPath: readinessURL.path)
                let litertReady = await testEndpoint(scheme: "http", port: 1235)
                if readinessReady || litertReady {
                    var webReady = isWebServerOnline
                    if !webReady {
                        webReady = await testWebUIEndpoint(port: 1236)
                    }
                    if webReady {
                        let changed = !isWebServerOnline || webUIPort != 1236
                        isWebServerOnline = true
                        webUIPort = 1236
                        activePort = 1236
                        if changed {
                            webServerReadyToken = UUID()
                        }
                    }

                    if webReady, await testEndpoint(scheme: "http", port: 1236) {
                        activeScheme = "http"
                        activePort = 1236
                        if !litertReady && nativeEngineAvailable {
                            loadModelsFromPureSwift()
                            activeRuntimeLabel = "Pure Swift LiteRTLM"
                            health = .online(details: "Pure Swift LiteRTLM + Web Server Lokal :1236")
                        } else {
                            activeRuntimeLabel = "Server Lokal (HTTP:1236)"
                            health = .online(details: "Tersambung ke HTTP port 1236")
                            await loadModelsFromBackend(scheme: "http", port: 1236)
                        }
                        isStartingBackend = false
                        backendStatusMessage = "Backend siap!"
                        return true
                    }

                    for target in targetEndpoints {
                        if await testEndpoint(scheme: target.scheme, port: target.port) {
                            activeScheme = target.scheme
                            activePort = (target.port == 1235 && webReady) ? 1236 : target.port
                            activeRuntimeLabel = "Server Lokal (\(target.scheme.uppercased()):\(activePort))"
                            health = .online(details: "Tersambung ke \(target.scheme.uppercased()) port \(target.port)")
                            await loadModelsFromBackend(scheme: target.scheme, port: target.port)
                            isStartingBackend = false
                            backendStatusMessage = "Backend siap!"
                            return true
                        }
                    }
                }
            }
        } catch {
            backendStatusMessage = "Gagal memulai backend: \(error.localizedDescription)"
        }

        isStartingBackend = false
        await probeAndRefresh()
        return health.isOnline
    }

    func stopStreaming() {
        activeTask?.cancel()
        activeTask = nil
        NativeLiteRTEngine.shared.cancel()
        isStreaming = false
    }

    func sendMessageStream(
        history: [ChatMessage],
        model: String,
        config: GenerationConfig,
        onToken: @escaping @MainActor (String) -> Void,
        onCompletion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) {
        stopStreaming()
        isStreaming = true

        let nativeReady = NativeLiteRTEngine.shared.isAvailable
        nativeEngineAvailable = nativeReady
        let preferPureSwift = config.runtimeMode == "pure_swift"
            || (config.runtimeMode == "auto" && activeRuntimeLabel.hasPrefix("Pure Swift") && nativeReady)

        if preferPureSwift {
            guard nativeReady else {
                isStreaming = false
                onCompletion(.failure(NSError(domain: "NativeLiteRTEngine", code: 503, userInfo: [
                    NSLocalizedDescriptionKey: "Mode Pure Swift dipilih, namun liblitert-lm.dylib belum tersedia di bundle."
                ])))
                return
            }
            activeRuntimeLabel = "Pure Swift LiteRTLM"
            activeTask = NativeLiteRTEngine.shared.generateStream(
                history: history,
                model: model,
                config: config,
                onToken: onToken,
                onCompletion: { [weak self] result in
                    self?.isStreaming = false
                    onCompletion(result)
                }
            )
            return
        }

        activeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isStreaming = false
            }

            let endpointURL = URL(string: "\(self.activeScheme)://\(config.serverHost):\(self.activePort)/v1/chat/completions")!
            var request = URLRequest(url: endpointURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

            var messagesPayload: [[String: String]] = []
            let activeSysPrompt = config.resolvedSystemPrompt
            if !activeSysPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messagesPayload.append(["role": "system", "content": activeSysPrompt])
            }

            var kbContext = ""
            if config.useKnowledgeBase {
                request.setValue("1", forHTTPHeaderField: "X-EduVis-Use-KB")
                if let snapshotURL = URL(string: "\(self.activeScheme)://\(config.serverHost):\(self.activePort)/api/kb/snapshot"),
                   let (snapData, snapRes) = try? await self.session.data(from: snapshotURL),
                   (snapRes as? HTTPURLResponse)?.statusCode == 200,
                   let snapJson = try? JSONSerialization.jsonObject(with: snapData) as? [String: Any] {
                    let files = snapJson["files"] as? [[String: Any]] ?? []
                    if !files.isEmpty {
                        let names = files.compactMap { f -> String? in
                            guard let n = f["name"] as? String else { return nil }
                            let size = (f["size"] as? Int) ?? 0
                            return "- \(n) (\(size / 1024) KB)"
                        }.joined(separator: "\n")
                        kbContext = "\n\n[KONTEKS BASIS DATA PENGETAHUAN LOKAL TERPUSAT (SQLite RAG)]\nTersimpan \(files.count) dokumen aktif di basis data lokal:\n\(names)\n[AKHIR KONTEKS BASIS DATA]\n"
                    } else {
                        kbContext = "\n\n[KONTEKS BASIS DATA PENGETAHUAN LOKAL TERPUSAT (SQLite RAG)]\nSaat ini belum ada berkas dokumen yang tersimpan di basis data lokal SQLite.\n[AKHIR KONTEKS BASIS DATA]\n"
                    }
                }
            }

            for (idx, msg) in history.enumerated() {
                var content = msg.content
                if idx == history.count - 1 && !kbContext.isEmpty && msg.role == .user {
                    content += kbContext
                }
                messagesPayload.append(["role": msg.role.rawValue, "content": content])
            }

            let effectiveModel: String
            if !config.backend.isEmpty, !model.contains(",") {
                effectiveModel = "\(model),\(config.backend)"
            } else {
                effectiveModel = model
            }

            var bodyDict: [String: Any] = [
                "model": effectiveModel,
                "messages": messagesPayload,
                "temperature": config.temperature,
                "top_p": config.topP,
                "top_k": config.topK,
                "max_tokens": config.maxTokens,
                "max_completion_tokens": config.maxTokens,
                "use_shared_kb": config.useKnowledgeBase,
                "stream": true
            ]
            if config.reasoningEffort != "none" && !config.reasoningEffort.isEmpty {
                bodyDict["reasoning_effort"] = config.reasoningEffort
            }

            guard let jsonData = try? JSONSerialization.data(withJSONObject: bodyDict) else {
                onCompletion(.failure(URLError(.cannotDecodeContentData)))
                return
            }
            request.httpBody = jsonData

            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 500
                    onCompletion(.failure(NSError(domain: "EduVisError", code: code, userInfo: [
                        NSLocalizedDescriptionKey: "Server mengembalikan kode status \(code)"
                    ])))
                    return
                }

                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.hasPrefix("data:") else { continue }
                    let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { break }

                    guard let lineData = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let first = choices.first,
                          let delta = first["delta"] as? [String: Any],
                          let deltaContent = delta["content"] as? String else {
                        continue
                    }

                    onToken(deltaContent)
                }

                onCompletion(.success(()))
            } catch {
                if !Task.isCancelled {
                    if config.runtimeMode == "auto" && NativeLiteRTEngine.shared.isAvailable {
                        self.activeRuntimeLabel = "Pure Swift LiteRTLM"
                        self.health = .online(details: "Pure Swift LiteRTLM Aktif (Fallback Tanpa Python)")
                        let fallbackTask = NativeLiteRTEngine.shared.generateStream(
                            history: history,
                            model: model,
                            config: config,
                            onToken: onToken,
                            onCompletion: { [weak self] fallbackResult in
                                self?.isStreaming = false
                                onCompletion(fallbackResult)
                            }
                        )
                        self.activeTask = fallbackTask
                        await fallbackTask.value
                        return
                    }
                    onCompletion(.failure(error))
                }
            }
        }
    }
}
