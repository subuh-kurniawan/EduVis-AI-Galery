//
//  SidebarView.swift
//  EduVis Native AI
//
//  Bilah samping navigasi (sidebar) dengan Liquid Glass surface:
//  Pemilihan 13 Ruang Kerja (Workspaces), Riwayat Sesi, Ekspor/Impor,
//  Pemantau RAM Sistem, dan Pengendali Backend Gemma 4.
//

import SwiftUI

struct SidebarView: View {
    @Binding var currentWorkspace: WorkspaceMode
    @Binding var sessions: [ChatSession]
    @Binding var selectedSessionID: UUID?
    @ObservedObject var aiService: LocalAIService
    @ObservedObject var systemMonitor: SystemMonitorService
    @Binding var selectedModelID: String
    var onNewChat: () -> Void
    var onOpenSettings: () -> Void
    var onTriggerQuickAsk: () -> Void
    var onImportSession: () -> Void
    var onExportSession: () -> Void
    var onOpenLauncher: (() -> Void)? = nil
    var onOpenModelCenter: (() -> Void)? = nil
    var onOpenLanQR: (() -> Void)? = nil
    var onOpenAbout: (() -> Void)? = nil

    @State private var searchText = ""

    private var filteredSessions: [ChatSession] {
        let matchingWorkspace = sessions.filter { $0.workspace == currentWorkspace }
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return matchingWorkspace
        }
        return matchingWorkspace.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.messages.contains { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bilah samping
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("EduVis AI Studio")
                        .font(.system(size: 14, weight: .bold))

                    Spacer()

                    Button(action: onTriggerQuickAsk) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                    .help("Tanya Cepat (⌘K)")

                    Button(action: onOpenSettings) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Pengaturan Model & Jaringan")
                }

                // Pemilih Ruang Kerja (Workspace Switcher)
                Menu {
                    ForEach(WorkspaceMode.allCases) { ws in
                        Button {
                            currentWorkspace = ws
                        } label: {
                            Label(ws.displayName, systemImage: ws.iconName)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: currentWorkspace.iconName)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(currentWorkspace.displayName)
                                .font(.system(size: 12, weight: .semibold))
                            Text(currentWorkspace.subtitle)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .menuStyle(.borderlessButton)

                Button(action: onNewChat) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.bubble.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Obrolan Baru")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .liquidGlass(cornerRadius: 8, strokeOpacity: 0.2, tint: .blue)
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Cari sesi...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(12)

            Divider().opacity(0.2)

            // Daftar sesi obrolan
            List(selection: $selectedSessionID) {
                Section(currentWorkspace.displayName) {
                    ForEach(filteredSessions) { session in
                        NavigationLink(value: session.id) {
                            HStack(spacing: 8) {
                                Image(systemName: "message")
                                    .font(.system(size: 11))
                                    .foregroundStyle(selectedSessionID == session.id ? .blue : .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .font(.system(size: 12, weight: selectedSessionID == session.id ? .semibold : .regular))
                                        .lineLimit(1)

                                    Text(session.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                        .contextMenu {
                            Button {
                                onExportSession()
                            } label: {
                                Label("Ekspor Sesi (JSON/MD)", systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                deleteSession(id: session.id)
                            } label: {
                                Label("Hapus Obrolan", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider().opacity(0.2)

                HStack(spacing: 10) {
                    Button(action: onImportSession) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Impor")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: onExportSession) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Ekspor")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if let onOpenLauncher {
                        Button(action: onOpenLauncher) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 11))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Peluncur 13 Ruang Kerja (⇧⌘L)")
                    }

                    if let onOpenModelCenter {
                        Button(action: onOpenModelCenter) {
                            Image(systemName: "cube.box")
                                .font(.system(size: 11))
                                .foregroundStyle(.purple)
                        }
                        .buttonStyle(.plain)
                        .help("Pusat Model .litertlm (⇧⌘M)")
                    }

                    if let onOpenLanQR {
                        Button(action: onOpenLanQR) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Akses LAN HTTPS & QR Code (⇧⌘Q)")
                    }

                    if let onOpenAbout {
                        Button(action: onOpenAbout) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Tentang Aplikasi & Developer")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)

            Divider().opacity(0.2)

            // Panel Pemantau Memori Sistem & Backend
            VStack(alignment: .leading, spacing: 6) {
                // Info Memori RAM Mac + Telemetry Suhu & Kecepatan
                HStack(spacing: 4) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(String(format: "RAM: %.1f / %.0f GB (%.0f%%)", systemMonitor.usedMemoryGB, systemMonitor.totalMemoryGB, systemMonitor.memoryPressurePercentage))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(systemMonitor.thermalStateLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(aiService.health.isOnline ? Color.green : (aiService.isStartingBackend ? Color.orange : Color.red))
                        .frame(width: 7, height: 7)

                    Text(aiService.health.isOnline ? "Backend Aktif" : (aiService.isStartingBackend ? "Memulai..." : "Offline"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        Task { await aiService.probeAndRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if !aiService.health.isOnline {
                    Button {
                        Task { _ = await aiService.startLocalBackend() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                            Text("Nyalakan Backend")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.18))
                        .foregroundStyle(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }

                Picker("Model", selection: $selectedModelID) {
                    ForEach(aiService.availableModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(.system(size: 10))
            }
            .padding(10)
            .liquidGlass(cornerRadius: 10, strokeOpacity: 0.12)
            .padding(8)
        }
    }

    private func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        if selectedSessionID == id {
            selectedSessionID = sessions.first?.id
        }
    }
}
