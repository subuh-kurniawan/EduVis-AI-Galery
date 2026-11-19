//
//  NativeLiteRTEngine.swift
//  EduVis Native AI
//
//  Backend inferensi Pure Swift / In-Process C-API 1.0.0 untuk LiteRT-LM (tanpa Python).
//  Mendukung dependency resmi Swift Package `LiteRTLM` dari google-ai-edge/LiteRT-LM
//  serta pemuatan dinamis `liblitert-lm.dylib` di dalam bundle aplikasi macOS.
//

import Foundation
import Darwin
#if canImport(LiteRTLM)
import LiteRTLM
#endif

private final class NativeStreamContext: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var lastError: String?
    var finished = false
    var onTokenCallback: (@Sendable (String) -> Void)?
    weak var api: NativeLiteRTCBridge?

    func emitToken(_ text: String) {
        onTokenCallback?(text)
    }

    func complete(error: String? = nil) {
        lock.lock()
        let alreadyFinished = finished
        if !alreadyFinished {
            lastError = error
            finished = true
        }
        lock.unlock()
        if !alreadyFinished {
            semaphore.signal()
        }
    }
}

private let nativeLiteRTStreamCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { userData, chunkPtr in
    guard let userData else { return }
    let context = Unmanaged<NativeStreamContext>.fromOpaque(userData).takeUnretainedValue()
    guard let api = context.api else {
        context.complete(error: "Bridge LiteRT-LM tidak tersedia.")
        return
    }
    guard let chunkPtr else {
        context.complete()
        return
    }

    var errPtr: UnsafePointer<CChar>?
    if let getErr = api.streamChunkGetError, getErr(chunkPtr, &errPtr) == 0, let errPtr {
        let msg = String(cString: errPtr)
        if msg.contains("CANCELLED") || msg.contains("Max number of tokens reached") {
            context.complete()
        } else {
            context.complete(error: msg)
        }
        return
    }

    var textPtr: UnsafePointer<CChar>?
    if let getText = api.streamChunkGetText, getText(chunkPtr, &textPtr) == 0, let textPtr {
        let rawChunk = String(cString: textPtr)
        let extracted = NativeLiteRTEngine.extractTextFromStreamChunk(rawChunk)
        if !extracted.isEmpty {
            context.emitToken(extracted)
        }
    }

    var isFinal = false
    if let getFinal = api.streamChunkIsFinal, getFinal(chunkPtr, &isFinal) == 0, isFinal {
        context.complete()
    }
}

private final class NativeLiteRTCBridge: @unchecked Sendable {
    typealias FnLastError = @convention(c) () -> UnsafePointer<CChar>?
    typealias FnEngineSettingsCreate = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    typealias FnPtrDelete = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias FnSetInt = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    typealias FnSetStr = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Int32
    typealias FnSetBool = @convention(c) (UnsafeMutableRawPointer?, Bool) -> Int32
    typealias FnSetFloat = @convention(c) (UnsafeMutableRawPointer?, Float) -> Int32
    typealias FnSetPtr = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32
    typealias FnCreateOut = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    typealias FnCreateFromOne = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    typealias FnCreateFromTwo = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    typealias FnCreateWithStr = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    typealias FnCreateWithInt = @convention(c) (Int32, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    typealias FnConversationCancel = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias FnConversationSendStream = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>?,
        UnsafeMutableRawPointer?,
        @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void,
        UnsafeMutableRawPointer?
    ) -> Int32
    typealias FnChunkGetStr = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafePointer<CChar>?>) -> Int32
    typealias FnChunkIsFinal = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Bool>) -> Int32
    typealias FnLoadedFileGetBool = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Bool>) -> Int32
    typealias FnLoadedFileModalityBool = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafeMutablePointer<Bool>) -> Int32
    typealias FnLoadedFileMaxCtx = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>) -> Int32

    let libraryHandle: UnsafeMutableRawPointer
    let libraryPath: String

    let lastErrorMessage: FnLastError?
    let engineSettingsCreate: FnEngineSettingsCreate
    let engineSettingsDelete: FnPtrDelete
    let engineSettingsSetMaxTokens: FnSetInt?
    let engineSettingsSetCacheDir: FnSetStr?
    let engineSettingsSetSpeculativeConfig: FnSetPtr?
    let engineCreate: FnCreateFromOne
    let engineDelete: FnPtrDelete

    let speculativeConfigCreate: FnCreateOut?
    let speculativeConfigDelete: FnPtrDelete?
    let speculativeConfigSetMode: FnSetInt?

    let samplerParamsCreate: FnCreateWithInt
    let samplerParamsDelete: FnPtrDelete
    let samplerParamsSetTopK: FnSetInt?
    let samplerParamsSetTopP: FnSetFloat?
    let samplerParamsSetTemperature: FnSetFloat?

    let sessionConfigCreate: FnCreateOut
    let sessionConfigDelete: FnPtrDelete
    let sessionConfigSetMaxOutputTokens: FnSetInt?
    let sessionConfigSetSamplerParams: FnSetPtr?

    let thinkingConfigCreate: FnCreateOut?
    let thinkingConfigDelete: FnPtrDelete?
    let thinkingConfigSetEnable: FnSetBool?
    let thinkingConfigSetBudget: FnSetInt?

    let conversationConfigCreate: FnCreateOut
    let conversationConfigDelete: FnPtrDelete
    let conversationConfigSetSessionConfig: FnSetPtr
    let conversationConfigSetSystemMessage: FnSetStr?
    let conversationConfigSetMessages: FnSetStr?
    let conversationConfigSetThinkingConfig: FnSetPtr?

    let conversationCreate: FnCreateFromTwo
    let conversationDelete: FnPtrDelete
    let conversationCancelProcess: FnConversationCancel?
    let conversationSendMessageStream: FnConversationSendStream

    let streamChunkGetText: FnChunkGetStr?
    let streamChunkIsFinal: FnChunkIsFinal?
    let streamChunkGetError: FnChunkGetStr?

    let loadedFileCreate: FnCreateWithStr?
    let loadedFileDelete: FnPtrDelete?
    let loadedFileHasSpeculative: FnLoadedFileGetBool?
    let loadedFileSupportsModality: FnLoadedFileModalityBool?
    let loadedFileMaxContextTokens: FnLoadedFileMaxCtx?

    init?(dylibPath: String) {
        guard let handle = dlopen(dylibPath, RTLD_NOW | RTLD_LOCAL) else {
            return nil
        }

        func sym<T>(_ name: String) -> T? {
            guard let ptr = dlsym(handle, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }

        guard let engineSettingsCreate: FnEngineSettingsCreate = sym("litert_lm_engine_settings_create"),
              let engineSettingsDelete: FnPtrDelete = sym("litert_lm_engine_settings_delete"),
              let engineCreate: FnCreateFromOne = sym("litert_lm_engine_create"),
              let engineDelete: FnPtrDelete = sym("litert_lm_engine_delete"),
              let samplerParamsCreate: FnCreateWithInt = sym("litert_lm_sampler_params_create"),
              let samplerParamsDelete: FnPtrDelete = sym("litert_lm_sampler_params_delete"),
              let sessionConfigCreate: FnCreateOut = sym("litert_lm_session_config_create"),
              let sessionConfigDelete: FnPtrDelete = sym("litert_lm_session_config_delete"),
              let conversationConfigCreate: FnCreateOut = sym("litert_lm_conversation_config_create"),
              let conversationConfigDelete: FnPtrDelete = sym("litert_lm_conversation_config_delete"),
              let conversationConfigSetSessionConfig: FnSetPtr = sym("litert_lm_conversation_config_set_session_config"),
              let conversationCreate: FnCreateFromTwo = sym("litert_lm_conversation_create"),
              let conversationDelete: FnPtrDelete = sym("litert_lm_conversation_delete"),
              let conversationSendMessageStream: FnConversationSendStream = sym("litert_lm_conversation_send_message_stream") else {
            dlclose(handle)
            return nil
        }

        self.libraryHandle = handle
        self.libraryPath = dylibPath
        self.lastErrorMessage = sym("litert_lm_get_last_error_message")
        self.engineSettingsCreate = engineSettingsCreate
        self.engineSettingsDelete = engineSettingsDelete
        self.engineSettingsSetMaxTokens = sym("litert_lm_engine_settings_set_max_num_tokens")
        self.engineSettingsSetCacheDir = sym("litert_lm_engine_settings_set_cache_dir")
        self.engineSettingsSetSpeculativeConfig = sym("litert_lm_engine_settings_set_speculative_decoding_config")
        self.engineCreate = engineCreate
        self.engineDelete = engineDelete

        self.speculativeConfigCreate = sym("litert_lm_speculative_decoding_config_create")
        self.speculativeConfigDelete = sym("litert_lm_speculative_decoding_config_delete")
        self.speculativeConfigSetMode = sym("litert_lm_speculative_decoding_config_set_mode")

        self.samplerParamsCreate = samplerParamsCreate
        self.samplerParamsDelete = samplerParamsDelete
        self.samplerParamsSetTopK = sym("litert_lm_sampler_params_set_top_k")
        self.samplerParamsSetTopP = sym("litert_lm_sampler_params_set_top_p")
        self.samplerParamsSetTemperature = sym("litert_lm_sampler_params_set_temperature")

        self.sessionConfigCreate = sessionConfigCreate
        self.sessionConfigDelete = sessionConfigDelete
        self.sessionConfigSetMaxOutputTokens = sym("litert_lm_session_config_set_max_output_tokens")
        self.sessionConfigSetSamplerParams = sym("litert_lm_session_config_set_sampler_params")

        self.thinkingConfigCreate = sym("litert_lm_thinking_config_create")
        self.thinkingConfigDelete = sym("litert_lm_thinking_config_delete")
        self.thinkingConfigSetEnable = sym("litert_lm_thinking_config_set_enable_thinking")
        self.thinkingConfigSetBudget = sym("litert_lm_thinking_config_set_thinking_token_budget")

        self.conversationConfigCreate = conversationConfigCreate
        self.conversationConfigDelete = conversationConfigDelete
        self.conversationConfigSetSessionConfig = conversationConfigSetSessionConfig
        self.conversationConfigSetSystemMessage = sym("litert_lm_conversation_config_set_system_message")
        self.conversationConfigSetMessages = sym("litert_lm_conversation_config_set_messages")
        self.conversationConfigSetThinkingConfig = sym("litert_lm_conversation_config_set_thinking_config")

        self.conversationCreate = conversationCreate
        self.conversationDelete = conversationDelete
        self.conversationCancelProcess = sym("litert_lm_conversation_cancel_process")
        self.conversationSendMessageStream = conversationSendMessageStream

        self.streamChunkGetText = sym("litert_lm_stream_chunk_get_text")
        self.streamChunkIsFinal = sym("litert_lm_stream_chunk_is_final")
        self.streamChunkGetError = sym("litert_lm_stream_chunk_get_error")

        self.loadedFileCreate = sym("litert_lm_loaded_file_create")
        self.loadedFileDelete = sym("litert_lm_loaded_file_delete")
        self.loadedFileHasSpeculative = sym("litert_lm_loaded_file_has_speculative_decoding_support")
        self.loadedFileSupportsModality = sym("litert_lm_loaded_file_supports_input_modality")
        self.loadedFileMaxContextTokens = sym("litert_lm_loaded_file_max_context_tokens")
    }

    func errorDescription(for funcName: String, code: Int32) -> String {
        let detail = lastErrorMessage?().map { String(cString: $0) } ?? "Kesalahan internal LiteRT-LM"
        return "\(funcName) gagal (kode \(code)): \(detail)"
    }
}

final class NativeLiteRTEngine: @unchecked Sendable {
    static let shared = NativeLiteRTEngine()

    private let lock = NSLock()
    private var bridge: NativeLiteRTCBridge?
    private var cachedEnginePtr: UnsafeMutableRawPointer?
    private var cachedEngineSignature: String?
    private var activeConversationPtr: UnsafeMutableRawPointer?

    private init() {
        self.bridge = Self.loadBridge()
    }

    var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        if bridge == nil {
            bridge = Self.loadBridge()
        }
        return bridge != nil
    }

    var statusSummary: String {
        lock.lock()
        defer { lock.unlock() }
        if bridge == nil {
            bridge = Self.loadBridge()
        }
        if let bridge {
            return "Pure Swift C-API 1.0.0 siap (\(URL(fileURLWithPath: bridge.libraryPath).lastPathComponent))"
        }
        return "liblitert-lm.dylib tidak ditemukan (gunakan Mode Otomatis / Server Python)"
    }

    private static func loadBridge() -> NativeLiteRTCBridge? {
        for path in candidateDylibPaths() {
            if FileManager.default.fileExists(atPath: path),
               let loaded = NativeLiteRTCBridge(dylibPath: path) {
                return loaded
            }
        }
        return nil
    }

    private static func candidateDylibPaths() -> [String] {
        var candidates: [String] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        if let frameworksDir = Bundle.main.privateFrameworksPath {
            candidates.append(URL(fileURLWithPath: frameworksDir).appendingPathComponent("liblitert-lm.dylib").path)
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/liblitert-lm.dylib").path)

        for version in ["3.14", "3.13", "3.12", "3.11", "3.10", "Current"] {
            candidates.append("/Library/Frameworks/Python.framework/Versions/\(version)/lib/python\(version)/site-packages/litert_lm/liblitert-lm.dylib")
        }

        let appSupportVenv = home.appendingPathComponent("Library/Application Support/Gemma AI Gallery/litert-lm-venv/lib")
        if let subdirs = try? fm.contentsOfDirectory(atPath: appSupportVenv.path) {
            for sub in subdirs where sub.hasPrefix("python") {
                candidates.append(appSupportVenv.appendingPathComponent("\(sub)/site-packages/litert_lm/liblitert-lm.dylib").path)
            }
        }

        candidates.append("/opt/homebrew/lib/liblitert-lm.dylib")
        candidates.append("/usr/local/lib/liblitert-lm.dylib")
        return candidates
    }

    static func extractTextFromStreamChunk(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return raw
        }
        if let contentList = json["content"] as? [[String: Any]] {
            let texts = contentList.compactMap { part -> String? in
                guard (part["type"] as? String) == "text" else { return nil }
                return part["text"] as? String
            }
            if !texts.isEmpty {
                return texts.joined()
            }
        }
        if let singleText = json["content"] as? String {
            return singleText
        }
        return ""
    }

    private static func isValidLiteRTLMContainer(at path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let magic = try? handle.read(upToCount: 8), magic.count == 8 else { return false }
        return String(data: magic, encoding: .ascii) == "LITERTLM"
    }

    private func modelSearchDirectories() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var dirs: [URL] = [
            home.appendingPathComponent("Gemma4", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/EduVis AI Gallery/models", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
            Bundle.main.bundleURL.deletingLastPathComponent(),
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent(),
        ]
        if let resApp = Bundle.main.resourceURL?.appendingPathComponent("app", isDirectory: true) {
            dirs.append(resApp)
        }
        return dirs
    }

    func discoverLocalModels() -> [ModelOption] {
        let inspected = inspectLocalModels().filter { $0.containerFormat == "litertlm" }
        return inspected.map { info in
            ModelOption(
                id: info.id,
                displayName: info.id.replacingOccurrences(of: ".litertlm", with: ""),
                tag: info.supportsMTP ? "Pure Swift · MTP" : "Pure Swift",
                isRecommended: info.id.contains("E2B")
            )
        }
    }

    func inspectLocalModels() -> [ModelInspectionInfo] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var results: [ModelInspectionInfo] = []
        var seenResolved = Set<String>()

        func inspectCandidate(fileURL: URL, id: String, registered: Bool) {
            let resolved = fileURL.resolvingSymlinksInPath().path
            guard !seenResolved.contains(resolved), fm.fileExists(atPath: resolved) else { return }
            seenResolved.insert(resolved)

            let sizeBytes = (try? fm.attributesOfItem(atPath: resolved)[.size] as? NSNumber)?.doubleValue ?? 0
            let sizeMB = (sizeBytes / (1024 * 1024) * 10).rounded() / 10
            let isLitertlm = Self.isValidLiteRTLMContainer(at: resolved)

            var modalities = ["text"]
            var supportsMTP = false
            var maxContext: Int? = nil

            if isLitertlm, let bridge, let createFile = bridge.loadedFileCreate {
                var filePtr: UnsafeMutableRawPointer?
                if createFile(resolved, &filePtr) == 0, let filePtr {
                    defer { bridge.loadedFileDelete?(filePtr) }
                    var hasSpec = false
                    if bridge.loadedFileHasSpeculative?(filePtr, &hasSpec) == 0 {
                        supportsMTP = hasSpec
                    }
                    var hasVision = false
                    if bridge.loadedFileSupportsModality?(filePtr, 1, &hasVision) == 0, hasVision {
                        modalities.append("vision")
                    }
                    var hasAudio = false
                    if bridge.loadedFileSupportsModality?(filePtr, 2, &hasAudio) == 0, hasAudio {
                        modalities.append("audio")
                    }
                    var ctx: UInt32 = 0
                    if bridge.loadedFileMaxContextTokens?(filePtr, &ctx) == 0, ctx > 0 {
                        maxContext = Int(ctx)
                    }
                }
            }

            results.append(
                ModelInspectionInfo(
                    id: id,
                    filename: fileURL.lastPathComponent,
                    sizeMB: sizeMB,
                    containerFormat: isLitertlm ? "litertlm" : "tflite_web",
                    modalities: modalities,
                    supportsMTP: supportsMTP,
                    defaultBackend: isLitertlm ? "gpu" : "webgpu",
                    maxContextTokens: maxContext,
                    registered: registered
                )
            )
        }

        let registryBase = home.appendingPathComponent(".litert-lm/models", isDirectory: true)
        if let entries = try? fm.contentsOfDirectory(at: registryBase, includingPropertiesForKeys: nil) {
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let modelFile = entry.appendingPathComponent("model.litertlm")
                if fm.fileExists(atPath: modelFile.path) {
                    let modelID = entry.lastPathComponent.replacingOccurrences(of: "--", with: "/")
                    inspectCandidate(fileURL: modelFile, id: modelID, registered: true)
                }
            }
        }

        for dir in modelSearchDirectories() {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension.lowercased() == "litertlm" {
                let stem = file.deletingPathExtension().lastPathComponent
                inspectCandidate(fileURL: file, id: stem, registered: false)
            }
        }

        return results
    }

    func resolveModelPath(for requestedModel: String) -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let cleanID = requestedModel.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? requestedModel
        let stem = cleanID.hasSuffix(".litertlm") ? String(cleanID.dropLast(9)) : cleanID

        var directCandidates: [URL] = []
        let registryBase = home.appendingPathComponent(".litert-lm/models", isDirectory: true)
        for name in [cleanID, stem, "\(stem).litertlm"] where !name.isEmpty {
            directCandidates.append(registryBase.appendingPathComponent(name.replacingOccurrences(of: "/", with: "--")).appendingPathComponent("model.litertlm"))
        }
        for dir in modelSearchDirectories() {
            directCandidates.append(dir.appendingPathComponent("\(stem).litertlm"))
            directCandidates.append(dir.appendingPathComponent(cleanID))
        }

        for candidate in directCandidates {
            let resolved = candidate.resolvingSymlinksInPath().path
            if fm.fileExists(atPath: resolved), Self.isValidLiteRTLMContainer(at: resolved) {
                return resolved
            }
        }

        for dir in modelSearchDirectories() {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension.lowercased() == "litertlm" {
                    let resolved = file.resolvingSymlinksInPath().path
                    if Self.isValidLiteRTLMContainer(at: resolved) {
                        return resolved
                    }
                }
            }
        }
        if let entries = try? fm.contentsOfDirectory(at: registryBase, includingPropertiesForKeys: nil) {
            for entry in entries {
                let resolved = entry.appendingPathComponent("model.litertlm").resolvingSymlinksInPath().path
                if fm.fileExists(atPath: resolved), Self.isValidLiteRTLMContainer(at: resolved) {
                    return resolved
                }
            }
        }
        return nil
    }

    func cancel() {
        lock.lock()
        let conv = activeConversationPtr
        let api = bridge
        lock.unlock()
        if let conv, let api {
            _ = api.conversationCancelProcess?(conv)
        }
    }

    func generateStream(
        history: [ChatMessage],
        model: String,
        config: GenerationConfig,
        onToken: @escaping @MainActor (String) -> Void,
        onCompletion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try self.runStreamSync(history: history, model: model, config: config, onToken: onToken)
                await MainActor.run { onCompletion(.success(())) }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { onCompletion(.failure(error)) }
                }
            }
        }
    }

    private func getOrCreateEngine(
        api: NativeLiteRTCBridge,
        modelPath: String,
        backend: String,
        maxTokens: Int,
        speculativeDecoding: Bool
    ) throws -> UnsafeMutableRawPointer {
        let normalizedBackend = ["gpu", "cpu", "npu"].contains(backend.lowercased()) ? backend.lowercased() : "gpu"
        let effectiveMaxTokens = max(2048, maxTokens)
        let signature = "\(modelPath)|\(normalizedBackend)|\(effectiveMaxTokens)|\(speculativeDecoding)"

        lock.lock()
        if let existing = cachedEnginePtr, cachedEngineSignature == signature {
            lock.unlock()
            return existing
        }
        if let old = cachedEnginePtr {
            api.engineDelete(old)
            cachedEnginePtr = nil
            cachedEngineSignature = nil
        }
        lock.unlock()

        var supportsVision = false
        var supportsAudio = false
        var supportsSpeculative = false
        if let createFile = api.loadedFileCreate {
            var filePtr: UnsafeMutableRawPointer?
            if createFile(modelPath, &filePtr) == 0, let filePtr {
                defer { api.loadedFileDelete?(filePtr) }
                _ = api.loadedFileSupportsModality?(filePtr, 1, &supportsVision)
                _ = api.loadedFileSupportsModality?(filePtr, 2, &supportsAudio)
                _ = api.loadedFileHasSpeculative?(filePtr, &supportsSpeculative)
            }
        }

        let visionBackend = supportsVision ? "cpu" : nil
        let audioBackend = supportsAudio ? "cpu" : nil

        var settingsPtr: UnsafeMutableRawPointer?
        let createSettingsStatus: Int32 = modelPath.withCString { mp in
            normalizedBackend.withCString { bk in
                if let vb = visionBackend, let ab = audioBackend {
                    return vb.withCString { vPtr in
                        ab.withCString { aPtr in
                            api.engineSettingsCreate(mp, bk, vPtr, aPtr, &settingsPtr)
                        }
                    }
                } else if let vb = visionBackend {
                    return vb.withCString { vPtr in
                        api.engineSettingsCreate(mp, bk, vPtr, nil, &settingsPtr)
                    }
                } else if let ab = audioBackend {
                    return ab.withCString { aPtr in
                        api.engineSettingsCreate(mp, bk, nil, aPtr, &settingsPtr)
                    }
                } else {
                    return api.engineSettingsCreate(mp, bk, nil, nil, &settingsPtr)
                }
            }
        }
        guard createSettingsStatus == 0, let settingsPtr else {
            throw NSError(domain: "NativeLiteRTEngine", code: Int(createSettingsStatus), userInfo: [
                NSLocalizedDescriptionKey: api.errorDescription(for: "litert_lm_engine_settings_create", code: createSettingsStatus)
            ])
        }
        defer { api.engineSettingsDelete(settingsPtr) }

        _ = api.engineSettingsSetMaxTokens?(settingsPtr, Int32(effectiveMaxTokens))

        let cacheURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/EduVisNativeAI/litert-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        cacheURL.path.withCString { cp in
            _ = api.engineSettingsSetCacheDir?(settingsPtr, cp)
        }

        if speculativeDecoding && supportsSpeculative,
           let specCreate = api.speculativeConfigCreate,
           let specDelete = api.speculativeConfigDelete,
           let specSetMode = api.speculativeConfigSetMode,
           let settingsSetSpec = api.engineSettingsSetSpeculativeConfig {
            var specPtr: UnsafeMutableRawPointer?
            if specCreate(&specPtr) == 0, let specPtr {
                defer { specDelete(specPtr) }
                _ = specSetMode(specPtr, 1)
                _ = settingsSetSpec(settingsPtr, specPtr)
            }
        }

        var enginePtr: UnsafeMutableRawPointer?
        let engineStatus = api.engineCreate(settingsPtr, &enginePtr)
        guard engineStatus == 0, let enginePtr else {
            throw NSError(domain: "NativeLiteRTEngine", code: Int(engineStatus), userInfo: [
                NSLocalizedDescriptionKey: api.errorDescription(for: "litert_lm_engine_create", code: engineStatus)
            ])
        }

        lock.lock()
        cachedEnginePtr = enginePtr
        cachedEngineSignature = signature
        lock.unlock()
        return enginePtr
    }

    private func runStreamSync(
        history: [ChatMessage],
        model: String,
        config: GenerationConfig,
        onToken: @escaping @MainActor (String) -> Void
    ) throws {
        guard let api = {
            lock.lock()
            defer { lock.unlock() }
            if bridge == nil { bridge = Self.loadBridge() }
            return bridge
        }() else {
            throw NSError(domain: "NativeLiteRTEngine", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Pustaka native liblitert-lm.dylib tidak ditemukan."
            ])
        }

        guard let modelPath = resolveModelPath(for: model) else {
            throw NSError(domain: "NativeLiteRTEngine", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "File model .litertlm (format LITERTLM) tidak ditemukan untuk '\(model)'."
            ])
        }

        guard let lastMsg = history.last else {
            return
        }

        let enginePtr = try getOrCreateEngine(
            api: api,
            modelPath: modelPath,
            backend: config.backend,
            maxTokens: config.maxTokens,
            speculativeDecoding: config.speculativeDecoding
        )

        var samplerPtr: UnsafeMutableRawPointer?
        let samplerStatus = api.samplerParamsCreate(2, &samplerPtr)
        guard samplerStatus == 0, let samplerPtr else {
            throw NSError(domain: "NativeLiteRTEngine", code: Int(samplerStatus), userInfo: [
                NSLocalizedDescriptionKey: api.errorDescription(for: "litert_lm_sampler_params_create", code: samplerStatus)
            ])
        }
        defer { api.samplerParamsDelete(samplerPtr) }
        _ = api.samplerParamsSetTopK?(samplerPtr, Int32(max(1, config.topK)))
        _ = api.samplerParamsSetTopP?(samplerPtr, Float(config.topP))
        _ = api.samplerParamsSetTemperature?(samplerPtr, Float(config.temperature))

        var sessionCfgPtr: UnsafeMutableRawPointer?
        let sessStatus = api.sessionConfigCreate(&sessionCfgPtr)
        guard sessStatus == 0, let sessionCfgPtr else {
            throw NSError(domain: "NativeLiteRTEngine", code: Int(sessStatus), userInfo: [
                NSLocalizedDescriptionKey: api.errorDescription(for: "litert_lm_session_config_create", code: sessStatus)
            ])
        }
        defer { api.sessionConfigDelete(sessionCfgPtr) }
        _ = api.sessionConfigSetMaxOutputTokens?(sessionCfgPtr, Int32(config.maxTokens))
        _ = api.sessionConfigSetSamplerParams?(sessionCfgPtr, samplerPtr)

        var convCfgPtr: UnsafeMutableRawPointer?
        let convCfgStatus = api.conversationConfigCreate(&convCfgPtr)
        guard convCfgStatus == 0, let convCfgPtr else {
            throw NSError(domain: "NativeLiteRTEngine", code: Int(convCfgStatus), userInfo: [
                NSLocalizedDescriptionKey: api.errorDescription(for: "litert_lm_conversation_config_create", code: convCfgStatus)
            ])
        }
        defer { api.conversationConfigDelete(convCfgPtr) }
        _ = api.conversationConfigSetSessionConfig(convCfgPtr, sessionCfgPtr)

        let trimmedSystem = config.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystem.isEmpty {
            trimmedSystem.withCString { sp in
                _ = api.conversationConfigSetSystemMessage?(convCfgPtr, sp)
            }
        }

        let priorMessages = history.dropLast().map { msg -> [String: String] in
            ["role": msg.role.rawValue, "content": msg.content]
        }
        if !priorMessages.isEmpty,
           let priorData = try? JSONSerialization.data(withJSONObject: priorMessages),
           let priorStr = String(data: priorData, encoding: .utf8) {
            priorStr.withCString { mp in
                _ = api.conversationConfigSetMessages?(convCfgPtr, mp)
            }
        }

        if config.reasoningEffort != "none",
           let tcCreate = api.thinkingConfigCreate,
           let tcDelete = api.thinkingConfigDelete,
           let tcSetEnable = api.thinkingConfigSetEnable,
           let tcSetBudget = api.thinkingConfigSetBudget,
           let convSetThinking = api.conversationConfigSetThinkingConfig {
            var tcPtr: UnsafeMutableRawPointer?
            if tcCreate(&tcPtr) == 0, let tcPtr {
                defer { tcDelete(tcPtr) }
                _ = tcSetEnable(tcPtr, true)
                _ = tcSetBudget(tcPtr, -1)
                _ = convSetThinking(convCfgPtr, tcPtr)
            }
        }

        var convPtr: UnsafeMutableRawPointer?
        let convStatus = api.conversationCreate(enginePtr, convCfgPtr, &convPtr)
        guard convStatus == 0, let convPtr else {
            throw NSError(domain: "NativeLiteRTEngine", code: Int(convStatus), userInfo: [
                NSLocalizedDescriptionKey: api.errorDescription(for: "litert_lm_conversation_create", code: convStatus)
            ])
        }
        defer {
            lock.lock()
            if activeConversationPtr == convPtr {
                activeConversationPtr = nil
            }
            lock.unlock()
            api.conversationDelete(convPtr)
        }

        lock.lock()
        activeConversationPtr = convPtr
        lock.unlock()

        let currentPayload: [String: String] = ["role": lastMsg.role.rawValue, "content": lastMsg.content]
        let currentData = try JSONSerialization.data(withJSONObject: currentPayload)
        let currentStr = String(data: currentData, encoding: .utf8) ?? "{}"

        let streamContext = NativeStreamContext()
        streamContext.api = api
        streamContext.onTokenCallback = { token in
            Task { @MainActor in
                onToken(token)
            }
        }

        let retainedCtx = Unmanaged.passRetained(streamContext)
        let streamStatus = currentStr.withCString { msgC in
            "{}".withCString { ctxC in
                api.conversationSendMessageStream(
                    convPtr,
                    msgC,
                    ctxC,
                    nil,
                    nativeLiteRTStreamCallback,
                    retainedCtx.toOpaque()
                )
            }
        }

        if streamStatus != 0 {
            retainedCtx.release()
            throw NSError(domain: "NativeLiteRTEngine", code: Int(streamStatus), userInfo: [
                NSLocalizedDescriptionKey: api.errorDescription(for: "litert_lm_conversation_send_message_stream", code: streamStatus)
            ])
        }

        while streamContext.semaphore.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            if Task.isCancelled {
                _ = api.conversationCancelProcess?(convPtr)
                _ = streamContext.semaphore.wait(timeout: .now() + .seconds(2))
                break
            }
        }
        retainedCtx.release()

        streamContext.lock.lock()
        let err = streamContext.lastError
        streamContext.lock.unlock()

        if let err {
            throw NSError(domain: "NativeLiteRTEngine", code: 1, userInfo: [
                NSLocalizedDescriptionKey: err
            ])
        }
    }
}
