//
//  FeatureModalsAndInspectorView.swift
//  EduVis Native AI
//
//  Adopsi seluruh fitur lanjutan dari EduVis AI Gallery.app ke SwiftUI Native + Liquid Glass HIG:
//  - ChatFontSizePillView (Pill Aa − 15px + ↺ persis seperti standar macOS WebView)
//  - PeluncurGallerySheet (Peluncur Visual 13 Ruang Kerja dengan filter & pratinjau)
//  - ModelCenterSheet (Pusat Model .litertlm: Drag & Drop, Upload, Delete, Zero-Copy Sync, ModelInfo & RAM check)
//  - LanQRSheet (Akses LAN HTTPS, pemilihan IP, generator QR Code native CIQRCodeGenerator, unduh CA .cer)
//  - AboutDeveloperSheet (Profil Subuh Kurniawan + dev.jpeg, arsitektur hybrid, & pintasan keyboard)
//  - RightInspectorDrawerView (3-Pane Inspector Kanan: Optik Liquid Glass & Aa, Parameter LiteRT-LM, SQLite RAG DB, & Live Canvas)
//

import SwiftUI
import AppKit
import WebKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import Darwin

// MARK: - 1. Pill Pengatur Ukuran Font Chat (Aa − 15px + ↺)

struct ChatFontSizePillView: View {
    @AppStorage("gemma_chat_font_size") private var chatFontSize: Double = 15.0
    var compact: Bool = false

    private var intFontSize: Int {
        Int(max(11, min(32, chatFontSize.rounded())))
    }

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            Text("Aa")
                .font(.system(size: compact ? 11 : 12, weight: .bold))
                .foregroundStyle(Color(red: 0.38, green: 0.68, blue: 0.98))
                .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                .background(Color(red: 0.14, green: 0.34, blue: 0.56).opacity(0.45))
                .clipShape(Circle())

            Button {
                updateFont(max(11.0, chatFontSize - 1.0))
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: compact ? 10 : 11, weight: .bold))
                    .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(intFontSize <= 11)
            .help("Perkecil ukuran font chat (⌘-)")

            Text("\(intFontSize)px")
                .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, compact ? 7 : 10)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.08))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )

            Button {
                updateFont(min(32.0, chatFontSize + 1.0))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: compact ? 10 : 11, weight: .bold))
                    .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(intFontSize >= 32)
            .help("Perbesar ukuran font chat (⌘+)")

            Button {
                updateFont(15.0)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reset ukuran font ke 15px (⇧⌘0)")
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .liquidGlassBar()
    }

    private func updateFont(_ newValue: Double) {
        let clamped = max(11.0, min(32.0, newValue.rounded()))
        chatFontSize = clamped
        WebKitWorkspacePool.shared.syncFontSize(clamped)
    }
}

// MARK: - 2. Peluncur Ruang Kerja Visual (13 Workspace Bento Grid)

struct PeluncurGallerySheet: View {
    @Binding var currentWorkspace: WorkspaceMode
    @Binding var interfaceStyle: InterfaceStyle
    @ObservedObject var aiService: LocalAIService
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var selectedCategory = "Semua"

    private let categories = ["Semua", "Obrolan & UI", "Visi & STEM", "Agen & Kode", "Basis Data"]

    private var filteredWorkspaces: [WorkspaceMode] {
        WorkspaceMode.allCases.filter { ws in
            let matchesSearch = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || ws.displayName.localizedCaseInsensitiveContains(searchQuery)
                || ws.rawValue.localizedCaseInsensitiveContains(searchQuery)
                || ws.subtitle.localizedCaseInsensitiveContains(searchQuery)
            let matchesCat: Bool
            switch selectedCategory {
            case "Obrolan & UI":
                matchesCat = [.utama, .utamaV2, .liquidChatbot, .aurora, .tanyaAI, .vsComparison].contains(ws)
            case "Visi & STEM":
                matchesCat = [.eduVis, .visionDoc, .geminiLive].contains(ws)
            case "Agen & Kode":
                matchesCat = [.claudeArtifacts, .codeAnalysis, .autonomousAgent].contains(ws)
            case "Basis Data":
                matchesCat = [.pgliteVectorSQL].contains(ws)
            default:
                matchesCat = true
            }
            return matchesSearch && matchesCat
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [.blue.opacity(0.35), .purple.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Peluncur Ruang Kerja EduVis AI (13 Studio)")
                        .font(.system(size: 18, weight: .bold))
                    Text("Pilih ruang kerja khusus dalam mode 💎 Native Liquid Glass atau 🌐 Web Canvas Asli")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(aiService.health.isOnline ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(aiService.health.isOnline ? "LiteRT-LM \(aiService.litertVersion)" : "Menyiapkan Engine...")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .liquidGlassBar()

                Button("Tutup") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(18)
            .background(.ultraThinMaterial)

            Divider().opacity(0.2)

            // Filter Bar
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Cari ruang kerja...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 240)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(categories, id: \.self) { cat in
                            Button {
                                selectedCategory = cat
                            } label: {
                                Text(cat)
                                    .font(.system(size: 11, weight: selectedCategory == cat ? .bold : .medium))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 5)
                                    .background(selectedCategory == cat ? Color.blue.opacity(0.24) : Color.primary.opacity(0.06))
                                    .foregroundStyle(selectedCategory == cat ? .blue : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            // Bento Grid 13 Workspace
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 14) {
                    ForEach(filteredWorkspaces) { ws in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: ws.iconName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.blue)
                                    .frame(width: 34, height: 34)
                                    .background(Color.blue.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                                Spacer()

                                if ws == currentWorkspace {
                                    Text("AKTIF")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundStyle(.green)
                                        .clipShape(Capsule())
                                }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(ws.displayName)
                                    .font(.system(size: 14, weight: .bold))
                                Text(ws.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .frame(height: 30, alignment: .topLeading)
                            }

                            HStack(spacing: 6) {
                                Button {
                                    currentWorkspace = ws
                                    interfaceStyle = .nativeSwiftUI
                                    dismiss()
                                } label: {
                                    Text("💎 Native")
                                        .font(.system(size: 11, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.22))
                                        .foregroundStyle(.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 7))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    currentWorkspace = ws
                                    interfaceStyle = .originalGallery
                                    dismiss()
                                } label: {
                                    Text("🌐 Web Asli")
                                        .font(.system(size: 11, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 5)
                                        .background(Color.primary.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 7))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                        .liquidGlassCard(cornerRadius: 16, tint: ws == currentWorkspace ? .blue : nil)
                    }
                }
                .padding(18)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

// MARK: - 3. Pusat Model (.litertlm Drag & Drop, Upload, Delete, Zero-Copy Sync)

struct ModelCenterSheet: View {
    @ObservedObject var aiService: LocalAIService
    @ObservedObject var systemMonitor: SystemMonitorService
    @Binding var selectedModelID: String
    @Binding var config: GenerationConfig
    @Environment(\.dismiss) private var dismiss

    @State private var customModelID: String = ""
    @State private var statusMessage: String = "Tarik & letakkan file .litertlm atau pilih dari Finder untuk mengimpor."
    @State private var isUploading: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var isRefreshing: Bool = false

    private var backendScheme: String {
        aiService.activePort == 1234 ? "https" : "http"
    }

    private func apiURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        var components = URLComponents()
        components.scheme = backendScheme
        components.host = config.serverHost
        components.port = aiService.activePort
        components.path = path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "cube.box.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pusat Model Lokal LiteRT-LM (.litertlm)")
                        .font(.system(size: 17, weight: .bold))
                    Text("Engine \(aiService.litertVersion) · \(aiService.activeRuntimeLabel) · RAM Terpasang \(String(format: "%.0f", systemMonitor.totalMemoryGB)) GB")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Tutup") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(.ultraThinMaterial)

            Divider().opacity(0.2)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Drop Zone + Impor .litertlm
                    VStack(spacing: 10) {
                        Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "tray.and.arrow.down.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(isDropTargeted ? .green : .blue)

                        Text("Impor Model .litertlm Lokal (Drag & Drop atau Pilih File)")
                            .font(.system(size: 13, weight: .semibold))

                        HStack(spacing: 8) {
                            TextField("Opsional: Nama ID Model (mis. gemma-4-custom)", text: $customModelID)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 320)

                            Button {
                                pickModelFile()
                            } label: {
                                Label(isUploading ? "Mengimpor..." : "Pilih .litertlm...", systemImage: "folder.badge.plus")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .disabled(isUploading)
                        }

                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(isDropTargeted ? Color.blue.opacity(0.14) : Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isDropTargeted ? Color.blue : Color.primary.opacity(0.16),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                            )
                    )
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                        handleDrop(providers: providers)
                    }

                    // Aksi Pemeliharaan Engine
                    HStack(spacing: 10) {
                        Button {
                            Task { await syncLocalModelsZeroCopy() }
                        } label: {
                            Label("Sinkronkan Zero-Copy Proyek", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .disabled(isRefreshing)

                        Button {
                            Task { await restartModelServerMemory() }
                        } label: {
                            Label("Segarkan Memori Model (Restart)", systemImage: "memorychip")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .disabled(isRefreshing)

                        Spacer()

                        Button {
                            Task { await aiService.probeAndRefresh() }
                        } label: {
                            Label("Muat Ulang Daftar", systemImage: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                    }

                    // Daftar Model Terdaftar + ModelInfo Spec
                    Text("Model Terdaftar (\(aiService.availableModels.count))")
                        .font(.system(size: 13, weight: .bold))

                    ForEach(aiService.availableModels) { model in
                        let inspected = aiService.inspectedModels.first(where: { $0.id == model.id })
                        HStack(spacing: 12) {
                            Image(systemName: selectedModelID == model.id ? "checkmark.circle.fill" : "cpu")
                                .font(.system(size: 18))
                                .foregroundStyle(selectedModelID == model.id ? .green : .blue)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(model.displayName)
                                        .font(.system(size: 13, weight: .bold))
                                    if selectedModelID == model.id {
                                        Text("AKTIF")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.2))
                                            .foregroundStyle(.green)
                                            .clipShape(Capsule())
                                    }
                                    if let fmt = inspected?.containerFormat {
                                        Text(fmt.uppercased())
                                            .font(.system(size: 9, design: .monospaced))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.primary.opacity(0.08))
                                            .clipShape(Capsule())
                                    }
                                }

                                HStack(spacing: 8) {
                                    if let mb = inspected?.sizeMB {
                                        let gb = mb / 1024.0
                                        Text(gb >= 1.0 ? String(format: "%.2f GB", gb) : String(format: "%.0f MB", mb))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    if let mods = inspected?.modalities, !mods.isEmpty {
                                        Text("Modalitas: \(mods.joined(separator: " · ").capitalized)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    if inspected?.supportsMTP == true {
                                        Text("MTP Drafter")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.purple)
                                    }
                                }
                            }

                            Spacer()

                            if selectedModelID != model.id {
                                Button("Pilih") {
                                    selectedModelID = model.id
                                    statusMessage = "Model aktif beralih ke \(model.displayName)."
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }

                            Button(role: .destructive) {
                                Task { await deleteModel(modelID: model.id) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Hapus model dari penyimpanan LiteRT-LM")
                        }
                        .padding(12)
                        .liquidGlassCard(cornerRadius: 12, tint: selectedModelID == model.id ? .green : nil)
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .onAppear {
            Task { await aiService.probeAndRefresh() }
        }
    }

    private func pickModelFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Pilih file model LiteRT-LM (.litertlm)"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await importModelFile(url: url) }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                await importModelFile(url: url)
            }
        }
        return true
    }

    @MainActor
    private func importModelFile(url: URL) async {
        guard url.pathExtension.lowercased() == "litertlm" else {
            statusMessage = "Hanya file berekstensi .litertlm yang didukung."
            return
        }
        let cleanID = customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: " ", with: "-")
            : customModelID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let endpoint = apiURL(
            path: "/api/import-model-upload",
            queryItems: [
                URLQueryItem(name: "model_id", value: cleanID),
                URLQueryItem(name: "filename", value: url.lastPathComponent)
            ]
        ) else {
            statusMessage = "Endpoint server lokal tidak tersedia."
            return
        }

        isUploading = true
        statusMessage = "Mengunggah \(url.lastPathComponent) sebagai '\(cleanID)'..."
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            isUploading = false
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
        do {
            let (data, res) = try await session.upload(for: req, fromFile: url)
            if let http = res as? HTTPURLResponse, http.statusCode == 200 {
                selectedModelID = cleanID
                customModelID = ""
                statusMessage = "Model \(cleanID) berhasil diimpor dan diaktifkan."
                await aiService.probeAndRefresh()
            } else {
                let errText = String(data: data, encoding: .utf8) ?? "Gagal mengimpor model."
                statusMessage = "Impor gagal: \(errText)"
            }
        } catch {
            statusMessage = "Kesalahan unggah: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func deleteModel(modelID: String) async {
        guard let url = apiURL(path: "/api/delete-model") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model_id": modelID])
        let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
        do {
            let (data, res) = try await session.data(for: req)
            if let http = res as? HTTPURLResponse, http.statusCode == 200 {
                statusMessage = "Model \(modelID) berhasil dihapus."
                await aiService.probeAndRefresh()
            } else {
                statusMessage = String(data: data, encoding: .utf8) ?? "Gagal menghapus model."
            }
        } catch {
            statusMessage = "Kesalahan hapus: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func syncLocalModelsZeroCopy() async {
        isRefreshing = true
        defer { isRefreshing = false }
        guard let url = apiURL(path: "/api/models/sync-local") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
        _ = try? await session.data(for: req)
        await aiService.probeAndRefresh()
        statusMessage = "Sinkronisasi Zero-Copy selesai (\(aiService.availableModels.count) model aktif)."
    }

    @MainActor
    private func restartModelServerMemory() async {
        isRefreshing = true
        defer { isRefreshing = false }
        guard let url = apiURL(path: "/api/system/restart-model-server") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
        do {
            let (_, res) = try await session.data(for: req)
            if (res as? HTTPURLResponse)?.statusCode == 200 {
                statusMessage = "Memori server model LiteRT-LM berhasil disegarkan."
                await aiService.probeAndRefresh()
            } else {
                statusMessage = "Server model tidak merespons restart."
            }
        } catch {
            statusMessage = "Gagal menyegarkan server model: \(error.localizedDescription)"
        }
    }
}

// MARK: - 4. Akses LAN HTTPS & QR Code Generator (Native CoreImage)

struct LanQRSheet: View {
    @ObservedObject var aiService: LocalAIService
    let currentWorkspace: WorkspaceMode
    @Environment(\.dismiss) private var dismiss

    @State private var addresses: [String] = []
    @State private var selectedAddress: String = ""
    @State private var selectedPage: String = ""
    @State private var copyFeedback: String = ""
    @State private var qrImage: NSImage?

    private var activeURLString: String {
        let host = selectedAddress.isEmpty ? "127.0.0.1" : selectedAddress
        let file = selectedPage.isEmpty ? currentWorkspace.htmlFileName : selectedPage
        // HTTPS berjalan pada port 1234 jika host bukan 127.0.0.1 atau jika akses LAN
        let scheme = host == "127.0.0.1" ? "http" : "https"
        let port = host == "127.0.0.1" ? aiService.activePort : 1234
        return "\(scheme)://\(host):\(port)/\(file)"
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "qrcode")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Akses LAN HTTPS & QR Code")
                        .font(.system(size: 17, weight: .bold))
                    Text("Pindai dari iPhone, iPad, atau perangkat lain di jaringan Wi-Fi yang sama")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Tutup") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 10) {
                    if let qrImage {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 210, height: 210)
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
                    } else {
                        ProgressView()
                            .frame(width: 210, height: 210)
                    }

                    Text(activeURLString)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Alamat IP Jaringan Lokal")
                        .font(.system(size: 12, weight: .bold))

                    Picker("IP", selection: $selectedAddress) {
                        ForEach(addresses, id: \.self) { addr in
                            Text(addr).tag(addr)
                        }
                    }
                    .labelsHidden()

                    Text("Ruang Kerja Target")
                        .font(.system(size: 12, weight: .bold))

                    Picker("Ruang Kerja", selection: $selectedPage) {
                        ForEach(WorkspaceMode.allCases) { ws in
                            Text("\(ws.displayName) (\(ws.htmlFileName))").tag(ws.htmlFileName)
                        }
                    }
                    .labelsHidden()

                    HStack(spacing: 8) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(activeURLString, forType: .string)
                            copyFeedback = "Tautan disalin ke Clipboard!"
                        } label: {
                            Label("Salin URL", systemImage: "doc.on.doc")
                        }

                        Button {
                            if let url = URL(string: activeURLString) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label("Buka Browser", systemImage: "safari")
                        }
                    }

                    Button {
                        downloadCACertificate()
                    } label: {
                        Label("Unduh Sertifikat CA LAN (.cer)", systemImage: "lock.shield")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Pasang sertifikat ini di iPhone/iPad/Mac lain agar koneksi HTTPS tepercaya penuh (WebGPU & Mikrofon aktif)")

                    if !copyFeedback.isEmpty {
                        Text(copyFeedback)
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 580, height: 390)
        .onAppear {
            selectedPage = currentWorkspace.htmlFileName
            loadNetworkAddresses()
        }
        .onChange(of: selectedAddress) { _, _ in regenerateQR() }
        .onChange(of: selectedPage) { _, _ in regenerateQR() }
    }

    private func loadNetworkAddresses() {
        var found = detectLocalIPv4Addresses()
        if found.isEmpty { found = ["127.0.0.1"] }
        addresses = found
        selectedAddress = found.first ?? "127.0.0.1"
        regenerateQR()

        let scheme = aiService.activePort == 1234 ? "https" : "http"
        if let url = URL(string: "\(scheme)://127.0.0.1:\(aiService.activePort)/api/network-info") {
            let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
            Task {
                if let (data, _) = try? await session.data(from: url),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let apiAddrs = json["addresses"] as? [String], !apiAddrs.isEmpty {
                    await MainActor.run {
                        self.addresses = apiAddrs
                        if !apiAddrs.contains(self.selectedAddress) {
                            self.selectedAddress = apiAddrs[0]
                        }
                        self.regenerateQR()
                    }
                }
            }
        }
    }

    private func detectLocalIPv4Addresses() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp && !isLoopback, let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    if !result.contains(ip) {
                        result.append(ip)
                    }
                }
            }
            if let next = ptr.pointee.ifa_next {
                ptr = next
            } else {
                break
            }
        }
        return result
    }

    private func regenerateQR() {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(activeURLString.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        if let cgimg = context.createCGImage(scaled, from: scaled.extent) {
            qrImage = NSImage(cgImage: cgimg, size: NSSize(width: 210, height: 210))
        }
    }

    private func downloadCACertificate() {
        let scheme = aiService.activePort == 1234 ? "https" : "http"
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(aiService.activePort)/api/lan-ca") else { return }
        let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
        Task {
            do {
                let (data, res) = try await session.data(from: url)
                guard (res as? HTTPURLResponse)?.statusCode == 200 else {
                    await MainActor.run { copyFeedback = "Sertifikat CA tidak tersedia saat ini." }
                    return
                }
                await MainActor.run {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "eduvis-ai-gallery-lan-ca.cer"
                    if panel.runModal() == .OK, let dest = panel.url {
                        try? data.write(to: dest, options: .atomic)
                        copyFeedback = "Sertifikat CA disimpan!"
                    }
                }
            } catch {
                await MainActor.run { copyFeedback = "Gagal mengunduh CA: \(error.localizedDescription)" }
            }
        }
    }
}

// MARK: - 5. Panel Tentang Aplikasi, Cara Kerja & Developer (Subuh Kurniawan + dev.jpeg)

struct AboutDeveloperSheet: View {
    @ObservedObject var aiService: LocalAIService
    @Environment(\.dismiss) private var dismiss

    private func loadDeveloperImage() -> NSImage? {
        var candidates: [String] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("dev.jpeg").path)
            candidates.append(res.appendingPathComponent("app/nano_asset/dev.jpeg").path)
        }
        if let proj = aiService.resolveProjectURL() {
            candidates.append(proj.appendingPathComponent("nano_asset/dev.jpeg").path)
        }
        candidates.append("/Users/subuhkurniawan/Gemma4/nano_asset/dev.jpeg")

        for path in candidates where FileManager.default.fileExists(atPath: path) {
            if let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        return NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tentang EduVis Native AI, Cara Kerja & Developer")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Tutup") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(.ultraThinMaterial)

            Divider().opacity(0.2)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Kartu Profil Developer (Subuh Kurniawan + nano_asset/dev.jpeg)
                    HStack(spacing: 16) {
                        if let devImg = loadDeveloperImage() {
                            Image(nsImage: devImg)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 82, height: 82)
                                .clipShape(Circle())
                                .overlay(
                                    Circle().stroke(Color.blue.opacity(0.7), lineWidth: 2)
                                )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("DEVELOPER · EDUVIS PROJECT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.blue)
                            Text("Subuh Kurniawan")
                                .font(.system(size: 19, weight: .bold))
                            Text("Membangun pengalaman AI lokal yang praktis untuk pembelajaran, kerja, dan eksplorasi model di perangkat sendiri dengan kedaulatan data penuh.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("Local LLM · LiteRT-LM v\(aiService.litertVersion) · Pure Swift · WebGPU · Vector RAG")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(16)
                    .liquidGlassCard(cornerRadius: 16, tint: .blue)

                    aboutCard(
                        title: "TENTANG APLIKASI — EDUVIS NATIVE AI STUDIO (HYBRID SUITE)",
                        content: "EduVis Native AI menggabungkan kecepatan antarmuka SwiftUI Liquid Glass murni dengan kekuatan penuh 13 Ruang Kerja dari EduVis AI Gallery (Utama, Utama V2, VS, Claude & Artifacts, EduVis, EduVis Live Voice, Liquid Chatbot, Aurora, Tanya AI, Vision & Dokumen, Analisis Kode, Agen AI Otonom, dan PGlite Vector SQL)."
                    )

                    aboutCard(
                        title: "CARA KERJA & ARSITEKTUR SISTEM",
                        content: """
                        1. Dual Engine (Pure Swift LiteRTLM + Python LiteRT-LM Server): Menjalankan model .litertlm (Gemma 4 E2B/E4B) secara lokal dengan akselerasi Apple Silicon GPU Metal / CPU / NPU serta Multi-Token Prediction (MTP).
                        2. SQLiteVectorStore (RAG Terpusat): Menyimpan dokumen lokal Anda dengan pencarian semantik lintas seluruh 13 ruang kerja dan mode Native.
                        3. Jembatan macOS Penuh: Ekspor instan PNG/SVG/PDF/DOCX, pengenalan & sintesis suara Bahasa Indonesia (SFSpeechRecognizer + AVSpeechSynthesizer), Quick Ask Spotlight (⌘K), serta kontrol ukuran font real-time (⌘+ / ⌘-).
                        """
                    )

                    aboutCard(
                        title: "PINTASAN KEYBOARD CEPAT MACOS",
                        content: """
                        • ⌘1 – ⌘9 : Pindah Ruang Kerja cepat
                        • ⌘K : Tanya Cepat AI (Spotlight)
                        • ⌘⌥I : Buka/Tutup Inspector Kanan (Optik Liquid Glass, Engine, RAG & Canvas)
                        • ⌘+ / ⌘- / ⇧⌘0 : Perbesar, Perkecil & Reset Ukuran Font Chat (Aa)
                        • ⇧⌘M : Buka Pusat Model .litertlm · ⇧⌘Q : Akses LAN & QR Code
                        """
                    )
                }
                .padding(16)
            }
        }
        .frame(width: 630, height: 590)
    }

    private func aboutCard(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .bold))
            Text(content)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlass(cornerRadius: 14, strokeOpacity: 0.16)
    }
}

// MARK: - 6. Right Inspector Drawer (Optik Liquid Glass & Aa, Parameter Mesin, RAG DB, Live Canvas)

struct RightInspectorDrawerView: View {
    @Binding var config: GenerationConfig
    @ObservedObject var aiService: LocalAIService
    let currentSession: ChatSession?
    @Binding var themeMode: String
    var onClose: () -> Void

    @AppStorage("gemma_chat_font_size") private var chatFontSize: Double = 15.0
    @AppStorage("lg_blur") private var lgBlur: Double = 24.0
    @AppStorage("lg_specular") private var lgSpecular: Double = 0.28
    @AppStorage("lg_saturate") private var lgSaturate: Double = 185.0
    @AppStorage("lg_sound") private var lgSound: Bool = false

    @State private var selectedTab: Int = 0
    @State private var kbFiles: [[String: Any]] = []
    @State private var kbSearchQuery: String = ""
    @State private var kbSearchResults: [[String: Any]] = []
    @State private var kbStatus: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header Inspector
            HStack {
                Text("Inspector")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Picker("", selection: $selectedTab) {
                Text("Optik & Aa").tag(0)
                Text("Mesin").tag(1)
                Text("RAG DB").tag(2)
                Text("Canvas").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider().opacity(0.2)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedTab {
                    case 0:
                        opticsAndFontTab
                    case 1:
                        engineParametersTab
                    case 2:
                        knowledgeBaseTab
                    default:
                        liveCanvasTab
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 310)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1)
        }
    }

    // Tab 0: Optik Liquid Glass & Ukuran Font Aa
    private var opticsAndFontTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("UKURAN FONT & TIPOGRAFI (Aa)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)

                ChatFontSizePillView(compact: true)
                    .frame(maxWidth: .infinity)

                Slider(value: $chatFontSize, in: 11.0...32.0, step: 1.0)
                    .onChange(of: chatFontSize) { _, val in
                        WebKitWorkspacePool.shared.syncFontSize(val)
                    }
            }
            .padding(10)
            .liquidGlass(cornerRadius: 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("TEMA ANTARMUKA")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)

                Picker("Tema", selection: $themeMode) {
                    Text("Gelap").tag("dark")
                    Text("Terang").tag("light")
                    Text("Sistem").tag("system")
                }
                .pickerStyle(.segmented)
                .onChange(of: themeMode) { _, newTheme in
                    if newTheme == "light" || newTheme == "dark" {
                        WebKitWorkspacePool.shared.syncTheme(newTheme)
                    }
                }
            }
            .padding(10)
            .liquidGlass(cornerRadius: 12)

            VStack(alignment: .leading, spacing: 10) {
                Text("LIQUID GLASS CONTROL CENTER")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)

                sliderRow(title: "Intensitas Blur", value: $lgBlur, range: 8...40, unit: "px")
                sliderRow(title: "Specular Highlight", value: $lgSpecular, range: 0.05...0.65, format: "%.2f")
                sliderRow(title: "Saturasi Warna", value: $lgSaturate, range: 100...240, unit: "%")

                Toggle("Efek Suara & Haptik UI", isOn: $lgSound)
                    .font(.system(size: 11))
            }
            .padding(10)
            .liquidGlass(cornerRadius: 12)
            .onChange(of: lgBlur) { _, _ in syncOptics() }
            .onChange(of: lgSpecular) { _, _ in syncOptics() }
            .onChange(of: lgSaturate) { _, _ in syncOptics() }
        }
    }

    private func syncOptics() {
        WebKitWorkspacePool.shared.syncLiquidGlassOptics(blur: lgBlur, specular: lgSpecular, saturate: lgSaturate)
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String = "", format: String = "%.0f") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11))
                Spacer()
                Text(String(format: format, value.wrappedValue) + unit)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.blue)
            }
            Slider(value: value, in: range)
        }
    }

    // Tab 1: Parameter Mesin & LiteRT-LM v0.19
    private var engineParametersTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("PARAMETER SAMPLING")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)

                sliderRow(title: "Temperature", value: $config.temperature, range: 0.0...1.5, format: "%.2f")
                sliderRow(title: "Top P", value: $config.topP, range: 0.1...1.0, format: "%.2f")
                sliderRow(
                    title: "Top K",
                    value: Binding(get: { Double(config.topK) }, set: { config.topK = Int($0) }),
                    range: 1...100
                )
                sliderRow(
                    title: "Max Tokens",
                    value: Binding(get: { Double(config.maxTokens) }, set: { config.maxTokens = Int($0) }),
                    range: 256...4096
                )
            }
            .padding(10)
            .liquidGlass(cornerRadius: 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("AKSELERATOR LITERT-LM V0.19")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)

                Picker("Backend", selection: $config.backend) {
                    Text("GPU Metal").tag("gpu")
                    Text("CPU XNNPACK").tag("cpu")
                    Text("NPU").tag("npu")
                }
                .pickerStyle(.segmented)

                Picker("Thinking Effort", selection: $config.reasoningEffort) {
                    Text("Mati").tag("none")
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }

                Toggle("Speculative Decoding (MTP)", isOn: $config.speculativeDecoding)
                    .font(.system(size: 11))

                Toggle("Basis Pengetahuan SQLite RAG", isOn: $config.useKnowledgeBase)
                    .font(.system(size: 11))
            }
            .padding(10)
            .liquidGlass(cornerRadius: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("SYSTEM PROMPT")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $config.systemPrompt)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(10)
            .liquidGlass(cornerRadius: 12)
        }
    }

    // Tab 2: SQLiteVectorStore Knowledge Base (RAG)
    private var knowledgeBaseTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DOKUMEN SQLITE RAG")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await loadKBFiles() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Button {
                    ingestTextDocument()
                } label: {
                    Label("Unggah Dokumen", systemImage: "doc.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(role: .destructive) {
                    Task { await clearKB() }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Kosongkan seluruh Basis Pengetahuan")
            }

            HStack(spacing: 6) {
                TextField("Cari semantik RAG...", text: $kbSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Button("Cari") {
                    Task { await searchKB() }
                }
                .controlSize(.small)
            }

            if !kbStatus.isEmpty {
                Text(kbStatus)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            if !kbSearchResults.isEmpty {
                Text("Hasil Pencarian (\(kbSearchResults.count))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.blue)
                ForEach(Array(kbSearchResults.enumerated()), id: \.offset) { _, res in
                    VStack(alignment: .leading, spacing: 3) {
                        Text((res["name"] as? String) ?? "Dokumen")
                            .font(.system(size: 11, weight: .semibold))
                        Text((res["text"] as? String) ?? "")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(8)
                    .liquidGlass(cornerRadius: 8)
                }
            }

            ForEach(Array(kbFiles.enumerated()), id: \.offset) { _, file in
                let name = (file["name"] as? String) ?? "Berkas"
                let fileID = (file["id"] as? String) ?? ""
                let chunks = (file["chunk_count"] as? Int) ?? 0
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text("\(chunks) potongan vektor").font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !fileID.isEmpty {
                        Button(role: .destructive) {
                            Task { await deleteKBFile(id: fileID) }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .liquidGlass(cornerRadius: 8)
            }
        }
        .onAppear {
            Task { await loadKBFiles() }
        }
    }

    // Tab 3: Live Canvas Preview untuk blok kode HTML / SVG / Mermaid
    private var liveCanvasTab: some View {
        let extracted = extractLatestArtifact(from: currentSession)
        return VStack(alignment: .leading, spacing: 10) {
            Text("PRATINJAU LIVE CANVAS / ARTIFACT")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.secondary)

            if let artifact = extracted {
                LiveCanvasHTMLWebView(htmlBody: artifact, activePort: aiService.activePort)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                    )

                Button {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.html]
                    panel.nameFieldStringValue = "eduvis-artifact.html"
                    if panel.runModal() == .OK, let dest = panel.url {
                        try? artifact.write(to: dest, atomically: true, encoding: .utf8)
                    }
                } label: {
                    Label("Ekspor HTML Canvas", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("Belum ada blok ```html, ```svg, atau ```mermaid pada sesi ini.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .liquidGlass(cornerRadius: 12)
            }
        }
    }

    private func extractLatestArtifact(from session: ChatSession?) -> String? {
        guard let messages = session?.messages else { return nil }
        for msg in messages.reversed() where msg.role == .assistant {
            let text = msg.content
            for lang in ["html", "svg"] {
                let marker = "```\(lang)"
                if let startRange = text.range(of: marker, options: .backwards) {
                    let afterStart = text[startRange.upperBound...]
                    if let endRange = afterStart.range(of: "```") {
                        return String(afterStart[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        return nil
    }

    private func kbBaseScheme() -> String {
        aiService.activePort == 1234 ? "https" : "http"
    }

    @MainActor
    private func loadKBFiles() async {
        guard let url = URL(string: "\(kbBaseScheme())://\(config.serverHost):\(aiService.activePort)/api/kb/files") else { return }
        let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
        do {
            let (data, res) = try await session.data(from: url)
            if (res as? HTTPURLResponse)?.statusCode == 200,
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let files = json["files"] as? [[String: Any]] {
                kbFiles = files
                kbStatus = files.isEmpty ? "Basis data kosong." : "\(files.count) dokumen tersedia."
            }
        } catch {
            kbStatus = "KB offline: \(error.localizedDescription)"
        }
    }

    private func ingestTextDocument() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Pilih file teks/MD/CSV/JSON/Kode untuk disimpan ke SQLiteVectorStore"
        if panel.runModal() == .OK, let url = panel.url,
           let content = try? String(contentsOf: url, encoding: .utf8) {
            let chunks = stride(from: 0, to: content.count, by: 900).map { offset -> [String: Any] in
                let start = content.index(content.startIndex, offsetBy: offset)
                let end = content.index(start, offsetBy: min(900, content.distance(from: start, to: content.endIndex)))
                return ["text": String(content[start..<end])]
            }
            Task {
                await postKB(path: "/api/kb/ingest", payload: [
                    "id": UUID().uuidString,
                    "name": url.lastPathComponent,
                    "size": content.utf8.count,
                    "chunks": chunks,
                    "collection": "Umum"
                ])
                await loadKBFiles()
            }
        }
    }

    @MainActor
    private func deleteKBFile(id: String) async {
        await postKB(path: "/api/kb/delete", payload: ["id": id])
        await loadKBFiles()
    }

    @MainActor
    private func clearKB() async {
        await postKB(path: "/api/kb/clear", payload: [:])
        kbSearchResults = []
        await loadKBFiles()
    }

    @MainActor
    private func searchKB() async {
        let q = kbSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let url = URL(string: "\(kbBaseScheme())://\(config.serverHost):\(aiService.activePort)/api/kb/search") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["query": q, "top_k": 4, "min_score": 0.1])
        let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
        if let (data, _) = try? await session.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = json["results"] as? [[String: Any]] {
            kbSearchResults = results
        }
    }

    @MainActor
    private func postKB(path: String, payload: [String: Any]) async {
        guard let url = URL(string: "\(kbBaseScheme())://\(config.serverHost):\(aiService.activePort)\(path)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
        _ = try? await session.data(for: req)
    }
}

struct LiveCanvasHTMLWebView: NSViewRepresentable {
    let htmlBody: String
    let activePort: Int

    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero)
        wv.setValue(false, forKey: "drawsBackground")
        loadHTML(into: wv)
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        loadHTML(into: nsView)
    }

    private func loadHTML(into webView: WKWebView) {
        let wrapped: String
        if htmlBody.localizedCaseInsensitiveContains("<html") || htmlBody.localizedCaseInsensitiveContains("<!doctype") {
            wrapped = htmlBody
        } else {
            wrapped = """
            <!DOCTYPE html><html><head><meta charset="utf-8">
            <style>body{margin:12px;font-family:-apple-system,sans-serif;color:#f8fafc;background:#0f172a;}</style>
            </head><body>\(htmlBody)</body></html>
            """
        }
        webView.loadHTMLString(wrapped, baseURL: URL(string: "http://127.0.0.1:\(activePort)/"))
    }
}

struct ShortcutCheatSheetModalView: View {
    @Environment(\.dismiss) private var dismiss
    var onTryQuickAsk: () -> Void

    private let shortcuts: [(String, String, String)] = [
        ("⌘K", "Tanya Cepat AI & Command Palette", "Ketik `>` untuk perintah sistem"),
        ("⌘1 – ⌘9", "Pindah Ruang Kerja 1–9", "Akses cepat semua studio"),
        ("⇧⌘L", "Peluncur Galeri 13 Studio", "Beralih Native vs Web Canvas"),
        ("⇧⌘2", "Tangkap Layar ke Vision AI", "Potong area layar untuk OCR/analisis"),
        ("⌘⌥I", "Buka/Tutup Inspector Kanan", "Optik Glass, Mesin, RAG & Canvas"),
        ("⌘+ / ⌘-", "Atur Ukuran Font Chat (Aa)", "Skala teks chat secara instan"),
        ("⌘,", "Pengaturan Inferensi AI", "Konfigurasi backend & prompt sistem"),
        ("⌘/", "Panduan Pintasan Keyboard ini", "Onboarding interaktif cepat")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pintasan Keyboard & Panduan Cepat")
                        .font(.system(size: 16, weight: .bold))
                    Text("Belajar langsung dengan mencoba pintasan utama macOS.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Tutup") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(.ultraThinMaterial)

            Divider().opacity(0.2)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(shortcuts, id: \.0) { kbd, title, desc in
                        HStack(spacing: 12) {
                            Text(kbd)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.16))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .frame(minWidth: 88)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(desc)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .liquidGlass(cornerRadius: 10, strokeOpacity: 0.12)
                    }
                }
                .padding(16)
            }

            Divider().opacity(0.2)

            HStack {
                Spacer()
                Button("Coba Command Palette (⌘K) Sekarang →") {
                    dismiss()
                    onTryQuickAsk()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .frame(width: 520, height: 480)
    }
}

struct HermesAgentHubSheet: View {
    @ObservedObject var aiService: LocalAIService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Int = 0
    @State private var statusMessage: String = "Memuat Hermes Agent Core..."
    @State private var stages: [[String: Any]] = []
    @State private var skills: [[String: Any]] = []
    @State private var memories: [[String: Any]] = []
    @State private var cronJobs: [[String: Any]] = []

    @State private var newSkillName: String = ""
    @State private var newSkillContent: String = ""
    @State private var newMemoryFact: String = ""
    @State private var subagentTask: String = ""
    @State private var subagentSynthesis: String = ""
    @State private var isDelegating: Bool = false
    @State private var enabledToolsets: Set<String> = [
        "Code & Terminal", "Vision & OCR", "RAG & FTS5 Memory", "STEM Simulation"
    ]

    @State private var cronName: String = ""
    @State private var cronPrompt: String = ""
    @State private var cronMinutes: String = "60"
    @State private var gatewayEnabled: Bool = false
    @State private var telegramToken: String = ""
    @State private var telegramChatID: String = ""
    @State private var webhookURL: String = ""

    private func hermesURL(_ path: String) -> URL? {
        let scheme = aiService.activePort == 1234 ? "https" : "http"
        return URL(string: "\(scheme)://127.0.0.1:\(aiService.activePort)\(path)")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hermes Agent Hub")
                        .font(.system(size: 16, weight: .bold))
                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Muat Ulang") { Task { await refreshAll() } }
                Button("Tutup") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(.ultraThinMaterial)

            Picker("", selection: $selectedTab) {
                Text("Bootstrap & Self-Heal").tag(0)
                Text("Skills & Memory FTS5").tag(1)
                Text("Subagents & Toolsets").tag(2)
                Text("Cron & Telegram").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider().opacity(0.2)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedTab {
                    case 0: bootstrapTab
                    case 1: skillsAndMemoryTab
                    case 2: subagentsTab
                    default: cronAndGatewayTab
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 680, height: 540)
        .onAppear { Task { await refreshAll() } }
    }

    private var bootstrapTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Staged Visual Bootstrapper & Self-Healing Runtime")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button {
                    Task { await runSelfHeal() }
                } label: {
                    Label("Self-Heal & Sinkronkan", systemImage: "bolt.shield.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            ForEach(Array(stages.enumerated()), id: \.offset) { _, st in
                HStack(spacing: 10) {
                    let ok = (st["status"] as? String) == "ready"
                    Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(ok ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text((st["title"] as? String) ?? "")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text((st["detail"] as? String) ?? "")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\((st["durationMs"] as? Int) ?? 0) ms")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .liquidGlass(cornerRadius: 10, strokeOpacity: 0.14)
            }
        }
    }

    private var skillsAndMemoryTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tambah Procedural Skill (.md) & Memori Episodik FTS5")
                .font(.system(size: 13, weight: .bold))

            HStack {
                TextField("Nama Skill", text: $newSkillName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                TextField("Instruksi prosedur Skill...", text: $newSkillContent)
                    .textFieldStyle(.roundedBorder)
                Button("Simpan Skill") { Task { await saveSkill() } }
            }

            HStack {
                TextField("Tambah fakta memori lintas sesi (mis: Preferensi saya SwiftUI)...", text: $newMemoryFact)
                    .textFieldStyle(.roundedBorder)
                Button("Simpan Memori") { Task { await saveMemory() } }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Skills Tersimpan (\(skills.count))")
                        .font(.system(size: 11.5, weight: .bold))
                    ForEach(Array(skills.enumerated()), id: \.offset) { _, sk in
                        VStack(alignment: .leading, spacing: 2) {
                            Text((sk["name"] as? String) ?? "")
                                .font(.system(size: 12, weight: .semibold))
                            Text((sk["description"] as? String) ?? "")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .liquidGlass(cornerRadius: 8, strokeOpacity: 0.12)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Memori Episodik FTS5 (\(memories.count))")
                        .font(.system(size: 11.5, weight: .bold))
                    ForEach(Array(memories.enumerated()), id: \.offset) { _, mem in
                        VStack(alignment: .leading, spacing: 2) {
                            Text((mem["category"] as? String) ?? "Memori")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.blue)
                            Text((mem["fact"] as? String) ?? "")
                                .font(.system(size: 11))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .liquidGlass(cornerRadius: 8, strokeOpacity: 0.12)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var subagentsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scoped Toolsets & Parallel Subagent Delegation (3 Agen)")
                .font(.system(size: 13, weight: .bold))

            HStack(spacing: 8) {
                ForEach(["Code & Terminal", "Vision & OCR", "RAG & FTS5 Memory", "STEM Simulation"], id: \.self) { tool in
                    let active = enabledToolsets.contains(tool)
                    Button {
                        if active { enabledToolsets.remove(tool) } else { enabledToolsets.insert(tool) }
                    } label: {
                        Label(tool, systemImage: active ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("Tugas untuk 3 Subagent paralel (Arsitek, Analis RAG, Verifikator)...", text: $subagentTask)
                    .textFieldStyle(.roundedBorder)
                Button(isDelegating ? "Memproses..." : "Delegasikan") {
                    Task { await delegateSubagents() }
                }
                .disabled(isDelegating || subagentTask.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !subagentSynthesis.isEmpty {
                Text(subagentSynthesis)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(cornerRadius: 10, strokeOpacity: 0.14)
            }
        }
    }

    private var cronAndGatewayTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jadwal Otomasi AI (Cron) & Jembatan Telegram / Webhook")
                .font(.system(size: 13, weight: .bold))

            HStack {
                TextField("Nama Cron", text: $cronName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                TextField("Menit", text: $cronMinutes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                TextField("Prompt otomatis...", text: $cronPrompt)
                    .textFieldStyle(.roundedBorder)
                Button("Simpan") { Task { await saveCron() } }
                Button("Jalankan") { Task { await runCronNow() } }
            }

            ForEach(Array(cronJobs.enumerated()), id: \.offset) { _, job in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\((job["name"] as? String) ?? "") · tiap \((job["schedule_minutes"] as? Int) ?? 60) mnt")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text((job["prompt"] as? String) ?? "")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    if let res = job["last_result"] as? String, !res.isEmpty {
                        Text("Terakhir: \(res)")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 8, strokeOpacity: 0.12)
            }

            Divider().opacity(0.2)

            Toggle("Aktifkan Telegram Bot / Webhook Gateway", isOn: $gatewayEnabled)
            HStack {
                TextField("Telegram Bot Token", text: $telegramToken)
                    .textFieldStyle(.roundedBorder)
                TextField("Chat ID", text: $telegramChatID)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            TextField("Webhook URL (opsional)", text: $webhookURL)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Simpan Gateway") { Task { await saveGateway() } }
                Button("Tes Kirim Pesan") { Task { await testGateway() } }
            }
        }
    }

    @MainActor
    private func getJSON(_ path: String) async -> [String: Any]? {
        guard let url = hermesURL(path) else { return nil }
        let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @MainActor
    private func postJSON(_ path: String, payload: [String: Any]) async -> [String: Any]? {
        guard let url = hermesURL(path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let session = URLSession(configuration: .default, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
        guard let (data, _) = try? await session.data(for: req) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @MainActor
    private func refreshAll() async {
        if let st = await getJSON("/api/hermes/status") {
            stages = (st["stages"] as? [[String: Any]]) ?? []
            let sc = (st["skills_count"] as? Int) ?? 0
            let mc = (st["memories_count"] as? Int) ?? 0
            let cc = (st["cron_count"] as? Int) ?? 0
            statusMessage = "Hermes Core · \(sc) Skills · \(mc) Memori FTS5 · \(cc) Cron"
            if let gw = st["gateway"] as? [String: Any] {
                gatewayEnabled = (gw["enabled"] as? Bool) ?? false
                telegramToken = (gw["telegram_bot_token"] as? String) ?? ""
                telegramChatID = (gw["telegram_chat_id"] as? String) ?? ""
                webhookURL = (gw["webhook_url"] as? String) ?? ""
            }
        }
        if let sk = await getJSON("/api/hermes/skills") {
            skills = (sk["skills"] as? [[String: Any]]) ?? []
        }
        if let mem = await getJSON("/api/hermes/memories") {
            memories = (mem["memories"] as? [[String: Any]]) ?? []
        }
        if let cr = await getJSON("/api/hermes/cron") {
            cronJobs = (cr["jobs"] as? [[String: Any]]) ?? []
        }
    }

    @MainActor
    private func runSelfHeal() async {
        statusMessage = "Menjalankan Self-Heal runtime..."
        _ = await postJSON("/api/hermes/self-heal", payload: [:])
        await refreshAll()
    }

    @MainActor
    private func saveSkill() async {
        let name = newSkillName.trimmingCharacters(in: .whitespaces)
        let content = newSkillContent.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !content.isEmpty else { return }
        _ = await postJSON("/api/hermes/skills", payload: [
            "action": "save",
            "name": name,
            "description": String(content.prefix(100)),
            "content": content
        ])
        newSkillName = ""
        newSkillContent = ""
        await refreshAll()
    }

    @MainActor
    private func saveMemory() async {
        let fact = newMemoryFact.trimmingCharacters(in: .whitespaces)
        guard !fact.isEmpty else { return }
        _ = await postJSON("/api/hermes/memories", payload: [
            "action": "add",
            "fact": fact,
            "category": "Preferensi"
        ])
        newMemoryFact = ""
        await refreshAll()
    }

    @MainActor
    private func delegateSubagents() async {
        isDelegating = true
        let res = await postJSON("/api/hermes/delegate", payload: [
            "task": subagentTask,
            "toolsets": Array(enabledToolsets)
        ])
        isDelegating = false
        subagentSynthesis = (res?["synthesis"] as? String) ?? "Gagal menjalankan delegasi Subagent."
    }

    @MainActor
    private func saveCron() async {
        guard !cronName.trimmingCharacters(in: .whitespaces).isEmpty,
              !cronPrompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        _ = await postJSON("/api/hermes/cron", payload: [
            "action": "upsert",
            "name": cronName,
            "prompt": cronPrompt,
            "schedule_minutes": Int(cronMinutes) ?? 60,
            "enabled": true
        ])
        await refreshAll()
    }

    @MainActor
    private func runCronNow() async {
        let slug = cronName.lowercased().replacingOccurrences(of: " ", with: "-")
        _ = await postJSON("/api/hermes/cron", payload: [
            "action": "run_now",
            "id": slug,
            "prompt": cronPrompt
        ])
        await refreshAll()
    }

    @MainActor
    private func saveGateway() async {
        _ = await postJSON("/api/hermes/gateway", payload: [
            "enabled": gatewayEnabled,
            "telegram_bot_token": telegramToken,
            "telegram_chat_id": telegramChatID,
            "webhook_url": webhookURL
        ])
        statusMessage = "Konfigurasi Telegram/Webhook Gateway tersimpan."
    }

    @MainActor
    private func testGateway() async {
        let res = await postJSON("/api/hermes/gateway", payload: [
            "action": "test_send",
            "message": "Tes jembatan Hermes Gateway dari EduVis Native AI!"
        ])
        let sent = (res?["sent"] as? Bool) ?? false
        statusMessage = sent ? "Pesan tes Gateway berhasil dikirim!" : "Aktifkan gateway & lengkapi token terlebih dahulu."
    }
}
