//
//  ContentView.swift
//  EduVis Native AI
//
//  Tampilan utama NavigationSplitView 3-Pane (Apple HIG Liquid Glass):
//  - Sidebar kiri sesi & pemantau memori
//  - Area kerja tengah (💎 Native SwiftUI atau 🌐 Web Canvas Asli dengan 13 Studio)
//  - Inspector Kanan (⌘⌥I): Optik Liquid Glass & Font Aa, Parameter LiteRT-LM, SQLite RAG, & Live Canvas
//  - Floating Pill Toolbar lengkap: Peluncur 13 Studio, Ukuran Font Aa, Pusat Model .litertlm,
//    Akses LAN HTTPS & QR Code, Tema Gelap/Terang, Quick Ask (⌘K), dan Profil Developer.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var aiService = LocalAIService()
    @StateObject private var systemMonitor = SystemMonitorService()
    @State private var currentWorkspace: WorkspaceMode = .utama
    @State private var interfaceStyle: InterfaceStyle = .nativeSwiftUI
    @State private var sessions: [ChatSession] = [
        ChatSession(title: "Obrolan Utama", workspace: .utama)
    ]
    @State private var selectedSessionID: UUID?
    @State private var selectedModelID: String = "gemma-4-E2B-it"
    @State private var inputText: String = ""
    @State private var config = GenerationConfig()
    @State private var errorMessage: String?

    @AppStorage("gemma_chat_font_size") private var chatFontSize: Double = 15.0
    @AppStorage("eduvis_theme_mode") private var themeMode: String = "dark"

    @State private var showSettings = false
    @State private var showQuickAsk = false
    @State private var showModelCenter = false
    @State private var showLanQR = false
    @State private var showAboutSheet = false
    @State private var showLauncherGallery = false
    @State private var showRightInspector = false
    @State private var showShortcutSheet = false
    @State private var showHermesHub = false
    @State private var webReloadToken = UUID()

    private var combinedWebReloadToken: UUID {
        var a = webReloadToken.uuid
        let b = aiService.webServerReadyToken.uuid
        a.0 ^= b.0; a.1 ^= b.1; a.2 ^= b.2; a.3 ^= b.3
        a.4 ^= b.4; a.5 ^= b.5; a.6 ^= b.6; a.7 ^= b.7
        a.8 ^= b.8; a.9 ^= b.9; a.10 ^= b.10; a.11 ^= b.11
        a.12 ^= b.12; a.13 ^= b.13; a.14 ^= b.14; a.15 ^= b.15
        return UUID(uuid: a)
    }

    private var activeSessionIndex: Int? {
        if let id = selectedSessionID {
            return sessions.firstIndex(where: { $0.id == id })
        }
        return sessions.firstIndex(where: { $0.workspace == currentWorkspace })
    }

    var body: some View {
        mainNavigationSplitView
            .preferredColorScheme(themeMode == "light" ? .light : (themeMode == "dark" ? .dark : nil))
            .onChange(of: interfaceStyle) { _, newStyle in
                if newStyle == .originalGallery {
                    Task {
                        await aiService.ensureWebServerRunning()
                    }
                }
            }
            .modifier(ContentSheetsModifier(
                showSettings: $showSettings,
                showQuickAsk: $showQuickAsk,
                showLauncherGallery: $showLauncherGallery,
                showModelCenter: $showModelCenter,
                showLanQR: $showLanQR,
                showAboutSheet: $showAboutSheet,
                showShortcutSheet: $showShortcutSheet,
                showHermesHub: $showHermesHub,
                config: $config,
                currentWorkspace: $currentWorkspace,
                interfaceStyle: $interfaceStyle,
                selectedModelID: $selectedModelID,
                aiService: aiService,
                systemMonitor: systemMonitor
            ))
            .modifier(ContentLifecycleModifier(
                selectedSessionID: $selectedSessionID,
                sessions: sessions,
                currentWorkspace: $currentWorkspace,
                chatFontSize: $chatFontSize,
                showRightInspector: $showRightInspector,
                showModelCenter: $showModelCenter,
                showLanQR: $showLanQR,
                showAboutSheet: $showAboutSheet,
                showLauncherGallery: $showLauncherGallery,
                showQuickAsk: $showQuickAsk,
                showSettings: $showSettings,
                showShortcutSheet: $showShortcutSheet,
                showHermesHub: $showHermesHub,
                onCreateNewSession: createNewSession,
                onEnsureWorkspaceSession: ensureSessionForWorkspace,
                onToggleTheme: toggleThemeMode
            ))
    }

    private var mainNavigationSplitView: some View {
        NavigationSplitView {
            SidebarView(
                currentWorkspace: $currentWorkspace,
                sessions: $sessions,
                selectedSessionID: $selectedSessionID,
                aiService: aiService,
                systemMonitor: systemMonitor,
                selectedModelID: $selectedModelID,
                onNewChat: createNewSession,
                onOpenSettings: { showSettings = true },
                onTriggerQuickAsk: { showQuickAsk = true },
                onImportSession: importSession,
                onExportSession: exportSession,
                onOpenLauncher: { showLauncherGallery = true },
                onOpenModelCenter: { showModelCenter = true },
                onOpenLanQR: { showLanQR = true },
                onOpenAbout: { showAboutSheet = true }
            )
            .navigationSplitViewColumnWidth(min: 245, ideal: 280, max: 345)
        } detail: {
            VStack(spacing: 0) {
                toolbarHeaderView

                Divider().opacity(0.15)

                if !aiService.health.isOnline {
                    offlineBannerView
                }

                workspaceMainAreaView
            }
            .background {
                if themeMode == "light" {
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor),
                            Color(nsColor: .underPageBackgroundColor)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(red: 0.086, green: 0.035, blue: 0.204),
                                Color(red: 0.141, green: 0.067, blue: 0.329),
                                Color(red: 0.071, green: 0.027, blue: 0.161)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        RadialGradient(
                            colors: [
                                Color(red: 0.925, green: 0.282, blue: 0.600).opacity(0.16),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.80, y: 0.25),
                            startRadius: 20,
                            endRadius: 520
                        )
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    private var workspaceMainAreaView: some View {
        HStack(spacing: 0) {
            Group {
                if interfaceStyle == .originalGallery {
                    WorkspaceWebView(
                        fileName: currentWorkspace.htmlFileName,
                        activePort: aiService.webUIPort,
                        chatFontSize: chatFontSize,
                        reloadToken: combinedWebReloadToken
                    )
                } else {
                    nativeWorkspaceContentView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showRightInspector {
                RightInspectorDrawerView(
                    config: $config,
                    aiService: aiService,
                    currentSession: currentSession,
                    themeMode: $themeMode,
                    onClose: { withAnimation(.easeInOut(duration: 0.2)) { showRightInspector = false } }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var nativeWorkspaceContentView: some View {
        switch currentWorkspace {
        case .vsComparison:
            VSComparisonWorkspaceView(aiService: aiService)
        case .claudeArtifacts:
            ClaudeArtifactsWorkspaceView(
                aiService: aiService,
                currentSession: Binding(
                    get: { self.currentSession },
                    set: { if let s = $0, let idx = self.activeSessionIndex { self.sessions[idx] = s } }
                ),
                inputText: $inputText,
                onSend: sendMessage
            )
        case .geminiLive:
            GeminiLiveVoiceWorkspaceView(aiService: aiService)
        case .visionDoc:
            VisionDocWorkspaceView(aiService: aiService)
        case .codeAnalysis:
            CodeAnalysisWorkspaceView(aiService: aiService)
        case .autonomousAgent:
            AutonomousAgentWorkspaceView(aiService: aiService)
        case .pgliteVectorSQL:
            VectorSQLWorkspaceView(aiService: aiService)
        case .ttsStudio, .geminiLiveFuturistik:
            WorkspaceWebView(
                fileName: currentWorkspace.htmlFileName,
                activePort: aiService.webUIPort,
                chatFontSize: chatFontSize,
                reloadToken: combinedWebReloadToken
            )
        case .utama, .utamaV2, .liquidChatbot, .aurora, .tanyaAI, .eduVis:
            standardChatWorkspaceView
        }
    }

    // MARK: - Toolbar Terpadu Apple Liquid Glass

    private var toolbarHeaderView: some View {
        HStack(spacing: 10) {
            // Tombol Peluncur Galeri 13 Studio
            Button {
                showLauncherGallery = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
                    .padding(6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Peluncur Galeri 13 Ruang Kerja (⇧⌘L)")

            // Menu Pengalih Ruang Kerja di Toolbar
            Menu {
                ForEach(WorkspaceMode.allCases) { ws in
                    Button {
                        currentWorkspace = ws
                    } label: {
                        Label(ws.displayName, systemImage: ws.iconName)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: currentWorkspace.iconName)
                        .foregroundStyle(.blue)
                    Text(currentWorkspace.displayName)
                        .font(.system(size: 12.5, weight: .bold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.borderlessButton)

            // Sakelar Antarmuka: 💎 Native vs 🌐 Web Canvas Asli
            Picker("", selection: $interfaceStyle) {
                Text("💎 Native").tag(InterfaceStyle.nativeSwiftUI)
                Text("🌐 Web Asli").tag(InterfaceStyle.originalGallery)
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 155, idealWidth: 175, maxWidth: 195)

            // Pill Pengaturan Ukuran Font Aa langsung di Toolbar
            ChatFontSizePillView(compact: true)

            Spacer()

            if let err = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.12))
                .clipShape(Capsule())
            }

            // Pill Aksi Kanan (Liquid Glass Bar)
            HStack(spacing: 8) {
                Button {
                    showQuickAsk = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.yellow)
                        Text("⌘K")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                }
                .buttonStyle(.plain)
                .help("Tanya Cepat AI / Spotlight (⌘K)")

                Button {
                    showHermesHub = true
                } label: {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)
                .help("Hermes Agent Hub: Skills, FTS5 Memory, Subagents & Cron (⇧⌘H)")

                Button(action: toggleThemeMode) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Ganti Tema Gelap / Terang")

                Button {
                    showLanQR = true
                } label: {
                    Image(systemName: "qrcode")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Akses LAN HTTPS & QR Code (⇧⌘Q)")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showRightInspector.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 12))
                        .foregroundStyle(showRightInspector ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help("Tampilkan/Sembunyikan Inspector Kanan (⌘⌥I)")

                if interfaceStyle == .originalGallery {
                    Button {
                        WebKitWorkspacePool.shared.reloadWorkspace(
                            fileName: currentWorkspace.htmlFileName,
                            activePort: aiService.webUIPort,
                            clearCache: true
                        )
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Bersihkan cache & muat ulang Web Canvas")

                    Button {
                        if let url = URL(string: "http://127.0.0.1:\(aiService.webUIPort)/\(currentWorkspace.htmlFileName)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "safari")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Buka di Safari eksternal")
                }

                Button {
                    showAboutSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Tentang Aplikasi, Cara Kerja & Developer")

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Pengaturan Model & Inferensi (⌘,)")

                if interfaceStyle == .nativeSwiftUI {
                    Button(action: clearCurrentSession) {
                        Image(systemName: "trash")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Bersihkan pesan di obrolan ini")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .liquidGlassBar()

            // Status Model aktif -> klik membuka Pusat Model
            Button {
                showModelCenter = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(aiService.health.isOnline ? Color.green : (aiService.isStartingBackend ? Color.orange : Color.red))
                        .frame(width: 7, height: 7)

                    Text(selectedModelID)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .liquidGlassBar()
            }
            .buttonStyle(.plain)
            .help("Buka Pusat Model .litertlm (⇧⌘M)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
    }

    private var offlineBannerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 16))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(aiService.isStartingBackend ? "Sedang menyiapkan runtime AI lokal..." : "Backend AI lokal belum terhubung")
                    .font(.system(size: 12, weight: .semibold))

                Text(aiService.backendStatusMessage.isEmpty ? "Server Python/LiteRT-LM diperlukan untuk inferensi Gemma 4 & SQLite RAG." : aiService.backendStatusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if aiService.isStartingBackend {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { _ = await aiService.startLocalBackend() }
                } label: {
                    Text("Nyalakan Sekarang")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    // Tampilan Chat Standard untuk workspace Utama, EduVis, Liquid, Aurora, Tanya AI
    private var standardChatWorkspaceView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        VStack(spacing: 0) {
                            if let currentSession, !currentSession.messages.isEmpty {
                                LazyVStack(spacing: 16) {
                                    let lastAssistantID = currentSession.messages.last(where: { $0.role == .assistant && !$0.isStreaming })?.id
                                    ForEach(currentSession.messages) { message in
                                        ChatBubbleView(
                                            message: message,
                                            activePort: aiService.activePort,
                                            isLatestAssistant: message.id == lastAssistantID,
                                            onSelectFollowUp: { followUp in
                                                inputText = followUp
                                                sendMessage()
                                            }
                                        )
                                        .id(message.id)
                                    }

                                    Color.clear
                                        .frame(height: 1)
                                        .id("chatBottomAnchor")
                                }
                                .padding(.vertical, 16)
                            } else {
                                EmptyStateGreetingView { prompt in
                                    inputText = prompt
                                    sendMessage()
                                }
                            }
                        }
                        .frame(maxWidth: 880)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: currentSession?.messages.count) { _, _ in
                        scrollToChatBottom(proxy: proxy, animated: true)
                    }
                    .onChange(of: currentSession?.messages.last?.content) { _, _ in
                        scrollToChatBottom(proxy: proxy, animated: true)
                    }
                    .onChange(of: selectedSessionID) { _, _ in
                        scrollToChatBottom(proxy: proxy, animated: false)
                    }

                    // Tombol Melayang Scroll ke Bawah
                    if let msgs = currentSession?.messages, msgs.count > 1 {
                        Button {
                            scrollToChatBottom(proxy: proxy, animated: true)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                                if aiService.isStreaming {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.primary.opacity(0.14), lineWidth: 1))
                            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 24)
                        .padding(.bottom, 12)
                        .help("Gulir ke pesan terbaru")
                    }
                }
            }

            ComposerBarView(
                text: $inputText,
                isStreaming: aiService.isStreaming,
                useKnowledgeBase: $config.useKnowledgeBase,
                onSend: sendMessage,
                onStop: { aiService.stopStreaming() }
            )
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
        }
    }

    private func scrollToChatBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
        }
    }

    private var currentSession: ChatSession? {
        if let idx = activeSessionIndex, sessions.indices.contains(idx) {
            return sessions[idx]
        }
        return nil
    }

    private func ensureSessionForWorkspace(_ ws: WorkspaceMode) {
        if let existing = sessions.first(where: { $0.workspace == ws }) {
            selectedSessionID = existing.id
        } else {
            let s = ChatSession(title: "\(ws.displayName) 1", workspace: ws, modelName: selectedModelID)
            sessions.insert(s, at: 0)
            selectedSessionID = s.id
        }
    }

    private func toggleThemeMode() {
        let next = themeMode == "light" ? "dark" : "light"
        themeMode = next
        WebKitWorkspacePool.shared.syncTheme(next)
    }

    private func createNewSession() {
        let newSession = ChatSession(
            title: "\(currentWorkspace.displayName) Baru \(sessions.count + 1)",
            workspace: currentWorkspace,
            modelName: selectedModelID
        )
        sessions.insert(newSession, at: 0)
        selectedSessionID = newSession.id
    }

    private func clearCurrentSession() {
        guard let idx = activeSessionIndex else { return }
        sessions[idx].messages.removeAll()
    }

    private func exportSession() {
        guard let session = currentSession else { return }
        SessionExportImportManager.exportSessionAsMarkdown(session)
    }

    private func importSession() {
        if let imported = SessionExportImportManager.importSessionFromJSON() {
            sessions.insert(imported, at: 0)
            selectedSessionID = imported.id
            currentWorkspace = imported.workspace
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = activeSessionIndex else { return }

        errorMessage = nil
        let userMessage = ChatMessage(role: .user, content: trimmed)
        sessions[idx].messages.append(userMessage)

        if sessions[idx].title.hasPrefix("Obrolan")
            || sessions[idx].title.hasPrefix("\(currentWorkspace.displayName) ")
            || sessions[idx].title.hasPrefix("\(currentWorkspace.rawValue) ") {
            sessions[idx].title = String(trimmed.prefix(32))
        }

        inputText = ""

        let assistantMessageID = UUID()
        let assistantPlaceholder = ChatMessage(
            id: assistantMessageID,
            role: .assistant,
            content: "",
            isStreaming: true
        )
        sessions[idx].messages.append(assistantPlaceholder)

        let history = sessions[idx].messages.dropLast()
        NSApp.dockTile.badgeLabel = "⚡ AI"

        aiService.sendMessageStream(
            history: Array(history),
            model: selectedModelID,
            config: config
        ) { [self] token in
            guard let sessionIdx = activeSessionIndex,
                  let msgIdx = sessions[sessionIdx].messages.firstIndex(where: { $0.id == assistantMessageID }) else {
                return
            }
            sessions[sessionIdx].messages[msgIdx].content += token
            sessions[sessionIdx].updatedAt = Date()
        } onCompletion: { [self] result in
            NSApp.dockTile.badgeLabel = nil
            guard let sessionIdx = activeSessionIndex,
                  let msgIdx = sessions[sessionIdx].messages.firstIndex(where: { $0.id == assistantMessageID }) else {
                return
            }
            sessions[sessionIdx].messages[msgIdx].isStreaming = false

            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
                if sessions[sessionIdx].messages[msgIdx].content.isEmpty {
                    sessions[sessionIdx].messages[msgIdx].content = "⚠️ Terjadi kendala: \(error.localizedDescription)\n\nPastikan backend lokal Python/LiteRT sedang berjalan di port \(aiService.activePort)."
                }
            }
        }
    }
}

private struct ContentSheetsModifier: ViewModifier {
    @Binding var showSettings: Bool
    @Binding var showQuickAsk: Bool
    @Binding var showLauncherGallery: Bool
    @Binding var showModelCenter: Bool
    @Binding var showLanQR: Bool
    @Binding var showAboutSheet: Bool
    @Binding var showShortcutSheet: Bool
    @Binding var showHermesHub: Bool
    @Binding var config: GenerationConfig
    @Binding var currentWorkspace: WorkspaceMode
    @Binding var interfaceStyle: InterfaceStyle
    @Binding var selectedModelID: String
    @ObservedObject var aiService: LocalAIService
    @ObservedObject var systemMonitor: SystemMonitorService

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showSettings) {
                SettingsSheet(config: $config)
            }
            .sheet(isPresented: $showQuickAsk) {
                QuickAskModalView(aiService: aiService)
            }
            .sheet(isPresented: $showLauncherGallery) {
                PeluncurGallerySheet(
                    currentWorkspace: $currentWorkspace,
                    interfaceStyle: $interfaceStyle,
                    aiService: aiService
                )
            }
            .sheet(isPresented: $showModelCenter) {
                ModelCenterSheet(
                    aiService: aiService,
                    systemMonitor: systemMonitor,
                    selectedModelID: $selectedModelID,
                    config: $config
                )
            }
            .sheet(isPresented: $showLanQR) {
                LanQRSheet(
                    aiService: aiService,
                    currentWorkspace: currentWorkspace
                )
            }
            .sheet(isPresented: $showAboutSheet) {
                AboutDeveloperSheet(aiService: aiService)
            }
            .sheet(isPresented: $showShortcutSheet) {
                ShortcutCheatSheetModalView {
                    showQuickAsk = true
                }
            }
            .sheet(isPresented: $showHermesHub) {
                HermesAgentHubSheet(aiService: aiService)
            }
    }
}

private struct ContentLifecycleModifier: ViewModifier {
    @Binding var selectedSessionID: UUID?
    let sessions: [ChatSession]
    @Binding var currentWorkspace: WorkspaceMode
    @Binding var chatFontSize: Double
    @Binding var showRightInspector: Bool
    @Binding var showModelCenter: Bool
    @Binding var showLanQR: Bool
    @Binding var showAboutSheet: Bool
    @Binding var showLauncherGallery: Bool
    @Binding var showQuickAsk: Bool
    @Binding var showSettings: Bool
    @Binding var showShortcutSheet: Bool
    @Binding var showHermesHub: Bool
    let onCreateNewSession: () -> Void
    let onEnsureWorkspaceSession: (WorkspaceMode) -> Void
    let onToggleTheme: () -> Void

    func body(content: Content) -> some View {
        let step1 = content
            .onAppear {
                if selectedSessionID == nil {
                    selectedSessionID = sessions.first?.id
                }
            }
            .onChange(of: currentWorkspace) { _, newWorkspace in
                onEnsureWorkspaceSession(newWorkspace)
            }
            .onChange(of: chatFontSize) { _, newSize in
                WebKitWorkspacePool.shared.syncFontSize(newSize)
            }
            .onReceive(NotificationCenter.default.publisher(for: .newChatNotification)) { _ in
                onCreateNewSession()
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchWorkspaceNotification)) { note in
                if let ws = note.object as? WorkspaceMode {
                    currentWorkspace = ws
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .increaseChatFontSizeNotification)) { _ in
                chatFontSize = min(32.0, chatFontSize + 1.0)
            }

        return step1
            .onReceive(NotificationCenter.default.publisher(for: .decreaseChatFontSizeNotification)) { _ in
                chatFontSize = max(11.0, chatFontSize - 1.0)
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetChatFontSizeNotification)) { _ in
                chatFontSize = 15.0
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspectorNotification)) { _ in
                withAnimation(.easeInOut(duration: 0.2)) { showRightInspector.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openModelCenterNotification)) { _ in
                showModelCenter = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLanQRNotification)) { _ in
                showLanQR = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAboutDeveloperNotification)) { _ in
                showAboutSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLauncherGalleryNotification)) { _ in
                showLauncherGallery = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleQuickAskNotification)) { _ in
                showQuickAsk.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleThemeNotification)) { _ in
                onToggleTheme()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsNotification)) { _ in
                showSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleShortcutSheetNotification)) { _ in
                showShortcutSheet.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openHermesHubNotification)) { _ in
                showHermesHub = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .captureScreenNotification)) { _ in
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                proc.arguments = ["-i", "-c"]
                proc.terminationHandler = { finished in
                    DispatchQueue.main.async {
                        if finished.terminationStatus == 0 {
                            currentWorkspace = .visionDoc
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                }
                try? proc.run()
            }
    }
}
