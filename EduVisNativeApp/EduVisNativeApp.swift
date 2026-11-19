//
//  EduVisNativeApp.swift
//  EduVis Native AI
//
//  Titik masuk aplikasi utama SwiftUI untuk macOS dengan MenuBar commands lengkap,
//  MenuBarExtra status item, serta pintasan keyboard untuk 13 Ruang Kerja, Font Aa,
//  Inspector Kanan, Pusat Model LiteRT-LM, dan Akses LAN QR.
//

import SwiftUI
import AppKit

@main
struct EduVisNativeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, idealWidth: 1220, minHeight: 620, idealHeight: 820)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .appInfo) {
                Button("Tentang EduVis Native AI & Developer...") {
                    NotificationCenter.default.post(name: .openAboutDeveloperNotification, object: nil)
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button("Pengaturan Inferensi AI...") {
                    NotificationCenter.default.post(name: .openSettingsNotification, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("Obrolan Baru") {
                    NotificationCenter.default.post(name: .newChatNotification, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Tanya Cepat AI (Spotlight)...") {
                    NotificationCenter.default.post(name: .toggleQuickAskNotification, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Tangkap Layar ke Vision AI...") {
                    NotificationCenter.default.post(name: .captureScreenNotification, object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])
            }

            CommandMenu("Ruang Kerja") {
                Button("Peluncur Galeri 13 Ruang Kerja...") {
                    NotificationCenter.default.post(name: .openLauncherGalleryNotification, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                ForEach(Array(WorkspaceMode.allCases.enumerated()), id: \.1.id) { index, ws in
                    if index < 9 {
                        Button(ws.displayName) {
                            NotificationCenter.default.post(name: .switchWorkspaceNotification, object: ws)
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    } else {
                        Button(ws.displayName) {
                            NotificationCenter.default.post(name: .switchWorkspaceNotification, object: ws)
                        }
                    }
                }
            }

            CommandMenu("Tampilan & Font") {
                Button("Perbesar Ukuran Font Chat (Aa+)") {
                    NotificationCenter.default.post(name: .increaseChatFontSizeNotification, object: nil)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Perkecil Ukuran Font Chat (Aa-)") {
                    NotificationCenter.default.post(name: .decreaseChatFontSizeNotification, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Ukuran Font Chat (15px)") {
                    NotificationCenter.default.post(name: .resetChatFontSizeNotification, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])

                Divider()

                Button("Tampilkan/Sembunyikan Inspector Kanan") {
                    NotificationCenter.default.post(name: .toggleInspectorNotification, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button("Ganti Tema Gelap / Terang") {
                    NotificationCenter.default.post(name: .toggleThemeNotification, object: nil)
                }

                Button("Pintasan Keyboard & Panduan (⌘/)...") {
                    NotificationCenter.default.post(name: .toggleShortcutSheetNotification, object: nil)
                }
                .keyboardShortcut("/", modifiers: .command)
            }

            CommandMenu("Model & LAN") {
                Button("Pusat Model LiteRT-LM (.litertlm)...") {
                    NotificationCenter.default.post(name: .openModelCenterNotification, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button("Akses LAN HTTPS & QR Code...") {
                    NotificationCenter.default.post(name: .openLanQRNotification, object: nil)
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])

                Button("Hermes Agent Hub (Skills, Memory, Cron)...") {
                    NotificationCenter.default.post(name: .openHermesHubNotification, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("EduVis AI", systemImage: "circle.hexagongrid.fill") {
            Button("Tampilkan Jendela Utama") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            Button("Tanya Cepat AI (⌘K)") {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .toggleQuickAskNotification, object: nil)
            }
            Button("Peluncur 13 Ruang Kerja (⇧⌘L)") {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openLauncherGalleryNotification, object: nil)
            }
            Divider()
            Button("Pusat Model .litertlm (⇧⌘M)") {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openModelCenterNotification, object: nil)
            }
            Button("Akses LAN & QR Code (⇧⌘Q)") {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openLanQRNotification, object: nil)
            }
            Button("Tentang & Developer") {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openAboutDeveloperNotification, object: nil)
            }
            Divider()
            Button("Keluar EduVis Native AI") {
                NSApp.terminate(nil)
            }
        }
    }
}

extension Notification.Name {
    static let newChatNotification = Notification.Name("EduVisNewChatNotification")
    static let switchWorkspaceNotification = Notification.Name("EduVisSwitchWorkspaceNotification")
    static let increaseChatFontSizeNotification = Notification.Name("EduVisIncreaseFontSize")
    static let decreaseChatFontSizeNotification = Notification.Name("EduVisDecreaseFontSize")
    static let resetChatFontSizeNotification = Notification.Name("EduVisResetFontSize")
    static let toggleInspectorNotification = Notification.Name("EduVisToggleInspector")
    static let openModelCenterNotification = Notification.Name("EduVisOpenModelCenter")
    static let openLanQRNotification = Notification.Name("EduVisOpenLanQR")
    static let openAboutDeveloperNotification = Notification.Name("EduVisOpenAbout")
    static let openLauncherGalleryNotification = Notification.Name("EduVisOpenLauncher")
    static let toggleQuickAskNotification = Notification.Name("EduVisToggleQuickAsk")
    static let toggleThemeNotification = Notification.Name("EduVisToggleTheme")
    static let openSettingsNotification = Notification.Name("EduVisOpenSettings")
    static let toggleShortcutSheetNotification = Notification.Name("EduVisToggleShortcutSheet")
    static let captureScreenNotification = Notification.Name("EduVisCaptureScreen")
    static let openHermesHubNotification = Notification.Name("EduVisOpenHermesHub")
}
