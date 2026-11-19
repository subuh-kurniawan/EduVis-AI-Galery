//
//  Models.swift
//  EduVis Native AI
//
//  Model data komprehensif: 13 Ruang Kerja (Workspaces), Pesan, Sesi,
//  Lampiran Dokumen, Langkah Agen Otonom, dan Pemantau Memori Sistem.
//

import Foundation
import SwiftUI

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

struct AttachedFile: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let fileExtension: String
    let fileSize: Int64
    let contentSnippet: String

    init(id: UUID = UUID(), name: String, fileExtension: String, fileSize: Int64, contentSnippet: String) {
        self.id = id
        self.name = name
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.contentSnippet = contentSnippet
    }
}

struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date
    var isStreaming: Bool
    var attachments: [AttachedFile]?
    var artifactContent: String?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        attachments: [AttachedFile]? = nil,
        artifactContent: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.attachments = attachments
        self.artifactContent = artifactContent
    }
}

enum WorkspaceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case utama = "Utama"
    case utamaV2 = "Utama V2"
    case ttsStudio = "TTS Studio AI"
    case vsComparison = "VS (Komparasi)"
    case claudeArtifacts = "Claude & Artifacts"
    case eduVis = "EduVis"
    case geminiLive = "Gemini Live (Voice)"
    case geminiLiveFuturistik = "Gemini Live Futuristik"
    case liquidChatbot = "Liquid Chatbot"
    case aurora = "Aurora"
    case tanyaAI = "Tanya AI"
    case visionDoc = "Vision & Dokumen"
    case codeAnalysis = "Analisis Kode"
    case autonomousAgent = "Agen AI Otonom"
    case pgliteVectorSQL = "PGlite Vector SQL"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .geminiLive: return "EduVis Live (Voice)"
        case .geminiLiveFuturistik: return "EduVis Live Futuristik"
        default: return rawValue
        }
    }

    var iconName: String {
        switch self {
        case .utama: return "bubble.left.and.bubble.right.fill"
        case .utamaV2: return "sparkles.rectangle.stack.fill"
        case .ttsStudio: return "waveform.and.mic"
        case .vsComparison: return "square.split.2x1.fill"
        case .claudeArtifacts: return "sidebar.right"
        case .eduVis: return "graduationcap.fill"
        case .geminiLive: return "waveform.circle.fill"
        case .geminiLiveFuturistik: return "sparkles.tv.fill"
        case .liquidChatbot: return "drop.fill"
        case .aurora: return "moon.stars.fill"
        case .tanyaAI: return "bolt.fill"
        case .visionDoc: return "doc.text.magnifyingglass"
        case .codeAnalysis: return "curlybraces.square.fill"
        case .autonomousAgent: return "cpu.fill"
        case .pgliteVectorSQL: return "cylinder.split.1x2.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .utama: return "Hub Obrolan & Visualisasi Utama"
        case .utamaV2: return "Antarmuka V2 dengan Template Cepat"
        case .ttsStudio: return "Studio Produksi Audio & Narasi AI"
        case .vsComparison: return "Komparasi Dua Model Side-by-Side"
        case .claudeArtifacts: return "Obrolan & Panel Artifact Interaktif"
        case .eduVis: return "Canvas Visualisasi Pembelajaran"
        case .geminiLive: return "Obrolan Suara Native Interaktif"
        case .geminiLiveFuturistik: return "Asisten Suara Duplex Aurora & Subtitle Visual"
        case .liquidChatbot: return "Estetika Liquid Glass Frosted"
        case .aurora: return "Antarmuka Kreatif & Aurora Glow"
        case .tanyaAI: return "Tanya Cepat AI Ringkas"
        case .visionDoc: return "Analisis PDF, DOCX, CSV & Kode"
        case .codeAnalysis: return "Review & Debugger Kode Otomatis"
        case .autonomousAgent: return "Agen Berpikir Mandiri Multi-Langkah"
        case .pgliteVectorSQL: return "Query Vektor & Basis Pengetahuan SQLite"
        }
    }

    var htmlFileName: String {
        switch self {
        case .utama: return "utama.html"
        case .utamaV2: return "utamaV2.html"
        case .ttsStudio: return "tts_studio_lokal.html"
        case .vsComparison: return "VS.html"
        case .claudeArtifacts: return "claude.html"
        case .eduVis: return "eduVis.html"
        case .geminiLive: return "gemini_live.html"
        case .geminiLiveFuturistik: return "gemini_live_futuristik.html"
        case .liquidChatbot: return "liquid_chatbot.html"
        case .aurora: return "aurora.html"
        case .tanyaAI: return "tanya-ai-standalone.html"
        case .visionDoc: return "vision_ulti.html"
        case .codeAnalysis: return "analisis-kode.html"
        case .autonomousAgent: return "agen-ai-otonom.html"
        case .pgliteVectorSQL: return "mesin-pglite-rag.html"
        }
    }
}

enum InterfaceStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case nativeSwiftUI = "Native Liquid Glass"
    case originalGallery = "Web Studio Asli (Gallery)"

    var id: String { rawValue }
}

struct ChatSession: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var workspace: WorkspaceMode
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date
    var modelName: String

    init(
        id: UUID = UUID(),
        title: String = "Obrolan Baru",
        workspace: WorkspaceMode = .utama,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        modelName: String = "gemma-4-E2B-it"
    ) {
        self.id = id
        self.title = title
        self.workspace = workspace
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelName = modelName
    }
}

struct ModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let tag: String
    let isRecommended: Bool
}

struct ModelInspectionInfo: Identifiable, Decodable, Sendable {
    let id: String
    let filename: String?
    let sizeMB: Double?
    let containerFormat: String?
    let modalities: [String]
    let supportsMTP: Bool
    let defaultBackend: String?
    let maxContextTokens: Int?
    let registered: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case filename
        case sizeMB = "size_mb"
        case containerFormat = "container_format"
        case modalities
        case supportsMTP = "supports_mtp"
        case defaultBackend = "default_backend"
        case maxContextTokens = "max_context_tokens"
        case registered
    }

    init(
        id: String,
        filename: String? = nil,
        sizeMB: Double? = nil,
        containerFormat: String? = nil,
        modalities: [String] = ["text"],
        supportsMTP: Bool = false,
        defaultBackend: String? = nil,
        maxContextTokens: Int? = nil,
        registered: Bool? = nil
    ) {
        self.id = id
        self.filename = filename
        self.sizeMB = sizeMB
        self.containerFormat = containerFormat
        self.modalities = modalities
        self.supportsMTP = supportsMTP
        self.defaultBackend = defaultBackend
        self.maxContextTokens = maxContextTokens
        self.registered = registered
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.filename = try container.decodeIfPresent(String.self, forKey: .filename)
        self.sizeMB = try container.decodeIfPresent(Double.self, forKey: .sizeMB)
        self.containerFormat = try container.decodeIfPresent(String.self, forKey: .containerFormat)
        self.modalities = try container.decodeIfPresent([String].self, forKey: .modalities) ?? ["text"]
        self.supportsMTP = try container.decodeIfPresent(Bool.self, forKey: .supportsMTP) ?? false
        self.defaultBackend = try container.decodeIfPresent(String.self, forKey: .defaultBackend)
        self.maxContextTokens = try container.decodeIfPresent(Int.self, forKey: .maxContextTokens)
        self.registered = try container.decodeIfPresent(Bool.self, forKey: .registered)
    }
}

extension Notification.Name {
    static let eduVisModelsDidSync = Notification.Name("eduVisModelsDidSync")
}

struct GenerationConfig: Codable, Sendable {
    var temperature: Double = 0.7
    var topP: Double = 0.95
    var maxTokens: Int = 3400
    var systemPrompt: String = "Anda adalah EduVis AI, asisten AI cerdas berbahasa Indonesia yang ditenagai oleh model Gemma 4. ATURAN WAJIB: 1) Jika diminta grafik/chart, WAJIB berikan konfigurasi JSON murni tanpa komentar di dalam blok kode dengan format ```chart\\n(isi JSON)\\n``` (JANGAN gunakan ```json). 2) Jika diminta flowchart/diagram, WAJIB gunakan sintaks Mermaid di dalam blok kode ```mermaid\\n(isi mermaid)\\n```. 3) Berikan jawaban yang informatif, terstruktur, ramah, profesional, dan gunakan pemformatan Markdown yang rapi dengan tabel atau daftar poin jika relevan."
    var useKnowledgeBase: Bool = true
    var serverHost: String = "127.0.0.1"
    var serverPort: Int = 1236
    var backend: String = "gpu"
    var speculativeDecoding: Bool = true
    var reasoningEffort: String = "none"
    var topK: Int = 40
    var runtimeMode: String = "auto"
    var appLanguage: String = "auto" // "auto" | "en" | "id"

    var effectiveLanguage: String {
        if appLanguage == "auto" {
            let pref = Locale.preferredLanguages.first?.lowercased() ?? Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
            return pref.starts(with: "id") ? "id" : "en"
        }
        return appLanguage
    }

    static let defaultSystemPromptEN = "You are EduVis AI, an intelligent native AI assistant powered by Gemma 4. RULES: 1) When asked for charts/graphs, provide pure JSON configuration inside ```chart\\n(JSON body)\\n``` code blocks (DO NOT use ```json). 2) When asked for flowcharts/diagrams, use Mermaid syntax inside ```mermaid\\n(mermaid content)\\n``` code blocks. 3) Provide informative, structured, friendly, and professional responses formatted in clean Markdown with tables or bullet lists where appropriate."

    var resolvedSystemPrompt: String {
        if effectiveLanguage == "en" && systemPrompt.contains("berbahasa Indonesia") {
            return GenerationConfig.defaultSystemPromptEN
        }
        return systemPrompt
    }

    init(
        temperature: Double = 0.7,
        topP: Double = 0.95,
        maxTokens: Int = 3400,
        systemPrompt: String = "Anda adalah EduVis AI, asisten AI cerdas berbahasa Indonesia yang ditenagai oleh model Gemma 4. ATURAN WAJIB: 1) Jika diminta grafik/chart, WAJIB berikan konfigurasi JSON murni tanpa komentar di dalam blok kode dengan format ```chart\\n(isi JSON)\\n``` (JANGAN gunakan ```json). 2) Jika diminta flowchart/diagram, WAJIB gunakan sintaks Mermaid di dalam blok kode ```mermaid\\n(isi mermaid)\\n```. 3) Berikan jawaban yang informatif, terstruktur, ramah, profesional, dan gunakan pemformatan Markdown yang rapi dengan tabel atau daftar poin jika relevan.",
        useKnowledgeBase: Bool = true,
        serverHost: String = "127.0.0.1",
        serverPort: Int = 1236,
        backend: String = "gpu",
        speculativeDecoding: Bool = true,
        reasoningEffort: String = "none",
        topK: Int = 40,
        runtimeMode: String = "auto",
        appLanguage: String = "auto"
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
        self.useKnowledgeBase = useKnowledgeBase
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.backend = backend
        self.speculativeDecoding = speculativeDecoding
        self.reasoningEffort = reasoningEffort
        self.topK = topK
        self.runtimeMode = runtimeMode
        self.appLanguage = appLanguage
    }
}

extension GenerationConfig {
    enum CodingKeys: String, CodingKey {
        case temperature, topP, maxTokens, systemPrompt, useKnowledgeBase, serverHost, serverPort
        case backend, speculativeDecoding, reasoningEffort, topK, runtimeMode, appLanguage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GenerationConfig()
        self.temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? defaults.temperature
        self.topP = try c.decodeIfPresent(Double.self, forKey: .topP) ?? defaults.topP
        self.maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? defaults.maxTokens
        self.systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt) ?? defaults.systemPrompt
        self.useKnowledgeBase = try c.decodeIfPresent(Bool.self, forKey: .useKnowledgeBase) ?? defaults.useKnowledgeBase
        self.serverHost = try c.decodeIfPresent(String.self, forKey: .serverHost) ?? defaults.serverHost
        self.serverPort = try c.decodeIfPresent(Int.self, forKey: .serverPort) ?? defaults.serverPort
        self.backend = try c.decodeIfPresent(String.self, forKey: .backend) ?? defaults.backend
        self.speculativeDecoding = try c.decodeIfPresent(Bool.self, forKey: .speculativeDecoding) ?? defaults.speculativeDecoding
        self.reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort) ?? defaults.reasoningEffort
        self.topK = try c.decodeIfPresent(Int.self, forKey: .topK) ?? defaults.topK
        self.runtimeMode = try c.decodeIfPresent(String.self, forKey: .runtimeMode) ?? defaults.runtimeMode
        self.appLanguage = try c.decodeIfPresent(String.self, forKey: .appLanguage) ?? defaults.appLanguage
    }
}

enum BackendHealth: Sendable {
    case checking
    case online(details: String)
    case offline(error: String)

    var isOnline: Bool {
        if case .online = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .checking:
            return "Memeriksa..."
        case .online(let details):
            return details
        case .offline(let err):
            return "Offline: \(err)"
        }
    }
}

struct AgentStep: Identifiable, Sendable {
    let id: UUID = UUID()
    let stepNumber: Int
    let thought: String
    let action: String
    let observation: String
}
