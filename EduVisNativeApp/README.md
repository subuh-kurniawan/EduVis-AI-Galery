# EduVis Native AI — Aplikasi macOS SwiftUI Native Komprehensif

Aplikasi macOS **100% Native SwiftUI** yang mengimplementasikan **seluruh fitur dari aplikasi non-native (WebView)** ke dalam bentuk native murni dengan estetika modern **Liquid Glass** dan terhubung langsung ke model **Gemma 4** lokal via LiteRT-LM.

---

## 🌟 Seluruh 13 Ruang Kerja (Workspaces) Native

Setiap halaman portal web non-native telah dikonversi menjadi tampilan ruang kerja native:

| # | Ruang Kerja | Modul Native | Deskripsi Fitur |
| :-: | :--- | :--- | :--- |
| **1** | **Utama** | [`ContentView.swift`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/ContentView.swift) | Hub obrolan AI utama dengan streaming token real-time, Markdown, dan code highlighting. |
| **2** | **Utama V2** | [`ContentView.swift`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/ContentView.swift) | Antarmuka obrolan dengan kartu saran dan template instruksi terintegrasi. |
| **3** | **VS (Komparasi Model)** | [`VSComparisonWorkspaceView`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/WorkspacesViews.swift#L20) | Eksekusi prompt simultan ke 2 model secara side-by-side untuk evaluasi akurasi dan kecepatan. |
| **4** | **Claude & Artifacts** | [`ClaudeArtifactsWorkspaceView`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/WorkspacesViews.swift#L172) | Antarmuka split-screen: percakapan di kolom kiri, live preview kode/artifact di kolom kanan. |
| **5** | **EduVis (Edukasi)** | [`ContentView.swift`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/ContentView.swift) | Mode pembelajaran visual dengan konsep terstruktur dan ringkasan penjelasan. |
| **6** | **EduVis Live (Voice)** | [`GeminiLiveVoiceWorkspaceView`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/WorkspacesViews.swift#L274) | Percakapan suara dua arah interaktif dengan visualisasi gelombang suara (*audio level orb*) dan balasan audio TTS (`AVSpeechSynthesizer`). |
| **7** | **Liquid Chatbot** | [`LiquidGlassModifier.swift`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/LiquidGlassModifier.swift) | Desain obrolan dengan estetika Liquid Glass mendalam (*frosted glassmorphism & specular border*). |
| **8** | **Aurora Studio** | [`ContentView.swift`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/ContentView.swift) | Kanvas kreatif dengan aksen gradien aurora dinamis. |
| **9** | **Tanya AI** | [`ContentView.swift`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/ContentView.swift) | Antarmuka minimalis dan cepat untuk tanya-jawab langsung. |
| **10**| **Vision & Dokumen** | [`VisionDocWorkspaceView`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/WorkspacesViews.swift#L429) | Ekstraksi teks native berkas PDF (`PDFKit`), DOCX, CSV, TXT, dan kode sumber tanpa koneksi internet. |
| **11**| **Analisis Kode** | [`CodeAnalysisWorkspaceView`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/WorkspacesViews.swift#L571) | Workspace inspeksi kode dengan preset: Audit Bug, Refactor, Optimasi, dan Pembuatan Unit Test. |
| **12**| **Agen AI Otonom** | [`AutonomousAgentWorkspaceView`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/WorkspacesViews.swift#L697) | Loop pemikiran otonom multi-langkah (*Thought -> Action -> Observation -> Final Conclusion*). |
| **13**| **PGlite Vector SQL** | [`VectorSQLWorkspaceView`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/WorkspacesViews.swift#L807) | Pemeriksa kueri SQL dan pencarian semantik vektor pada basis data pengetahuan lokal (`SQLite RAG`). |

---

## ⚡ Fitur Sistem Tambahan

1. **Quick Ask Spotlight Panel (`⌘K`)**:
   - Panel mengambang bergaya Spotlight yang dapat dibuka dari mana saja dengan shortcut `⌘K` via [`QuickAskModalView.swift`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/QuickAskModalView.swift).
2. **Dikte Suara Native (Speech-to-Text)**:
   - Ditenagai oleh framework [`SpeechRecognizerService.swift`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/SpeechRecognizerService.swift) menggunakan `SFSpeechRecognizer` dan `AVAudioEngine`.
3. **Pemantau Memori Sistem Real-Time**:
   - Menampilkan penggunaan Unified Memory (RAM) Mac dan persentase *pressure* secara langsung pada sidebar via [`SystemMonitorService.swift`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/SystemMonitorService.swift).
4. **Lampiran Berkas pada Input Composer**:
   - Tombol klip kertas (*paperclip*) untuk langsung melampirkan berkas teks/PDF ke pertanyaan obrolan.
5. **Ekspor & Impor Sesi (JSON / Markdown)**:
   - Kompatibel penuh dengan sesi format browser lama melalui [`SessionExportImportManager.swift`](file:///Users/subuhkurniawan/Gemma4/EduVisNativeApp/SessionExportImportManager.swift).
6. **Auto-Start & Multi-Port Backend**:
   - Otomatis memindai dan memulai proses backend Python (`gemma_chat_gui.py --backend-only`) pada port 1236, 1235, atau 1234.

---

## 🚀 Build & Menjalankan Aplikasi

Prasyarat: macOS 14.0+ dengan Xcode Command Line Tools (`swiftc`, `xcrun`).

Untuk mengompilasi bundle `EduVis Native AI.app` dari folder root proyek:
```bash
cd EduVisNativeApp
chmod +x build_native_app.sh
./build_native_app.sh
```

Menjalankan aplikasi hasil build:
```bash
open "EduVisNativeApp/EduVis Native AI.app"
```
