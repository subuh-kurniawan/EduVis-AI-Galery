# 📝 Catatan Perubahan & Changelog EduVis AI Gallery (Gemma 4)

Dokumen ini mencatat seluruh pembaruan, audit dependensi, stabilisasi fitur, modernisasi antarmuka web (HTML/CSS/JS), serta kepatuhan sistem terhadap prinsip integritas aplikasi *on-device/fully offline*.

---

## 📅 [2026-10-28] — Standarisasi UI Modal LAN QR Code Lintas Workspace Independen & Kebal Tema (`nano_asset/assets/js/lan-qrcode.js` & `ai-renderers.css`)

### 🎯 Akar Permasalahan & Solusi Diterapkan
- **Penyebab Masalah (Root Cause):**
  - Pada tema terang (`body.light-theme`), selector global `.light-theme .text-slate-100`, `.light-theme .text-slate-200`, `.light-theme .text-slate-300`, dan `.light-theme .text-slate-400` menggunakan `!important` untuk memaksakan teks menjadi gelap (`#1f1f1f` / `#3c4043` / `#5f6368`).
  - Modal LAN QR (`#lan-qr-modal`) memiliki kartu latar belakang gelap `#131314` tanpa isolasi CSS sendiri, sehingga seluruh teks (judul *Buka di perangkat lain*, subjudul, label form, dropdown `select`, dan status monospace URL) dipaksa menjadi gelap di atas latar belakang gelap (menjadi nyaris tidak terbaca / *unreadable*).
  - Tombol aksi *Salin tautan* yang menggunakan `.bg-white/5` berubah menjadi abu-abu terang `#e9eef6`, merusak keselarasan kartu modal.
  - Dropdown `<select>` bawaan WebKit mewarisi appearance terang sistem tanpa penegasan `color-scheme: dark`.

- **Solusi Standarisasi Mandiri & Kebal Tema:**
  1. **Isolasi Gaya Penuh di `lan-qrcode.js`:**
     - Menginjeksi `<style id="lan-qr-styles">` mandiri langsung ke `<head>` secara dinamis.
     - Mengganti utility classes Tailwind yang rentan (`text-slate-*`, `bg-white/5`) dengan kelas semantik terisolasi (`lan-qr-card`, `lan-qr-header`, `lan-qr-title`, `lan-qr-subtitle`, `lan-qr-close`, `lan-qr-body-box`, `lan-qr-field`, `lan-qr-btn-group`, `lan-qr-notice`).
     - Mengunci `color-scheme: dark !important;` pada modal root, dialog card, dan elemen input/select.
     - Memastikan typography judul (`#ffffff`), subjudul (`#94a3b8`), label (`#cbd5e1`), dropdown pilihan (`#f8fafc` dengan background `#1a1b22`), tombol salin, tautan sertifikat, dan URL status (`#93c5fd`) ber-kontras tinggi dan 100% konsisten di semua tema (Light, Dark, OLED, Hacker).
     - Tombol pemicu `#lan-qr-open` di header disesuaikan otomatis agar harmonis di header tema gelap maupun terang.
  2. **Pertahanan Ganda di `nano_asset/assets/css/ai-renderers.css`:**
     - Menambahkan aturan pelindung spesifisitas tinggi (`html body.light-theme #lan-qr-modal ...`) agar tidak ada override tema yang dapat menembus kartu modal.
  3. **Uji Otomatis & Verifikasi (`tests/modal-consistency.test.js`):**
     - Memvalidasi kekebalan tema, penegasan `color-scheme: dark`, dan keberadaan selector pelindung (44 tes unit lulus 100%).

---

## 📅 [2026-10-28] — Optimalisasi Arsitektur Native Swift Shell (`gemma_webview.swift`)

### 🎯 Peningkatan Utama yang Diterapkan
1. **WebKit Memory Safety & Offline Speech Recognition:**
   - **`WeakScriptMessageHandler`**: Memutus *strong retain cycle* antara `WKUserContentController` dan `WindowDelegate` menggunakan kelas pembungkus referensi lemah (`weak var delegate`), mencegah kebocoran memori saat beralih antar halaman atau mereload tampilan.
   - **`isInspectable = true`**: Mengaktifkan Safari Web Inspector pada macOS 13.3+ untuk mempermudah debugging aplikasi lokal.
   - **Offline Apple Speech Recognition**: Mengaktifkan `requiresOnDeviceRecognition = true` pada `SFSpeechAudioBufferRecognitionRequest` saat didukung oleh Apple Silicon (`recognizer.supportsOnDeviceRecognition`), menjamin transkripsi suara 100% lokal tanpa ketergantungan jaringan internet.

2. **Instant Workspace Switching (Multi-WKWebView Caching):**
   - Menghadirkan arsitektur caching per workspace (`workspaceWebViews: [String: WKWebView]`) di dalam kontainer `webContentArea`.
   - Menggantikan mekanisme hancur-dan-muat-ulang lama: kini perpindahan antara *Chat Utama*, *Mode Perbandingan (VS)*, *Claude Code*, dan *EduVis* berlangsung seketika (*0 ms loading latency*) dengan menjaga riwayat percakapan, tab aktif, dan status DOM di latar belakang.
   - Penyesuaian `showLauncher()` agar tidak menghentikan loading (`stopLoading()`), menjaga sesi AI yang sedang berpikir tetap berjalan.

3. **Apple Silicon Unified Memory Guard:**
   - Membaca memori fisik terpadu perangkat Mac secara presisi melalui `ProcessInfo.processInfo.physicalMemory` (`getPhysicalMemoryGB()`).
   - Melakukan evaluasi otomatis kebutuhan RAM model lokal:
     - Model besar (26B, 27B, 31B): memberikan peringatan rekomendasi RAM ≥ 32 GB jika sistem memiliki RAM di bawah kapasitas tersebut.
     - Model menengah (12B, 14B): memberikan peringatan rekomendasi RAM ≥ 16 GB jika RAM sistem terbatas.
   - Memberikan notifikasi langsung pada status bar peluncuran dan jendela Pusat Model.

4. **macOS Native Menu Bar Status Item (`NSStatusItem`):**
   - Menghadirkan ikon status persisten `✦ Gemma` di menu bar sistem macOS.
   - Informasi real-time nama model yang sedang aktif dan kapasitas RAM Unified Memory.
   - Submenu navigasi cepat ke seluruh Workspace (*Chat Utama*, *Mode VS*, *Claude Style*, *EduVis*).
   - Akses instan ke Pusat Model & Pengaturan, tombol muat ulang halaman dengan pembersihan cache selektif, pembuka tautan ke browser eksternal, dan opsi keluar dari aplikasi.

5. **Uji Otomatis & Verifikasi Kompilasi (`tests/swift-optimizations.test.js`):**
   - Validasi sintaks dan typechecking via `xcrun swiftc -sdk macosx -target arm64-apple-macosx13.0 -typecheck gemma_webview.swift` (0 error, 0 warning).
   - Rangkaian pengujian terintegrasi lulus 100% (43 tes unit hijau).

---

## 📅 [2026-10-28] — Standarisasi UI Modal Pengaturan AI Independen Tema & Universal

### 🎯 Peningkatan Utama yang Diterapkan
1. **Pemisahan Desain Modal AI Mandiri & Kebal Tema (`nano_asset/assets/css/ai-renderers.css`):**
   - Menetapkan aturan CSS ber-spesifisitas tinggi dengan selector hierarkis (`html body.light-theme #ai-settings-modal`, `html body:not(.light-theme) #ai-settings-modal`) untuk mencegah efek samping CSS tema global.
   - Mengatasi masalah teks gelap di atas latar gelap pada mode terang (`light-theme`), di mana selector umum seperti `body.light-theme textarea` dan `body.light-theme .text-slate-100` sebelumnya menimpa warna teks di dalam modal.
   - Memastikan latar belakang `#121318`, border `rgba(255, 255, 255, 0.12)`, font typography, dan kontras input `rgba(0, 0, 0, 0.45)` tampil solid, jernih, dan elegan di semua mode tampilan (Dark, Light, OLED, Hacker).

2. **Konsistensi UI Lintas Seluruh Halaman HTML:**
   - Standarisasi tampilan kartu modal, form controls (Endpoint, Model LiteRT-LM, Model Terimpor, Impor Model Lokal, Max Tokens KV-Cache, System Prompt, Tema & Font).
   - Tombol aksi terpadu: tombol *Batal* (`border border-white/10 bg-white/5`) dan tombol *Simpan* (`bg-gradient-to-r from-gemini-blue to-gemini-purple text-white`).
   - Scrollbar internal modal seragam (`custom-scrollbar`) yang tidak terdistorsi warna saat berpindah tema.
   - Diterapkan secara identik pada 6 modul HTML utama: `claude.html`, `VS.html`, `utama.html`, `utamaV2.html`, `vision_ulti.html`, dan `eduVis.html`.

3. **Uji Otomatis & Regresi (`tests/modal-consistency.test.js`):**
   - Menambahkan 2 rangkaian uji otomatis baru untuk memvalidasi kelengkapan aturan CSS proteksi tema dan keberadaan elemen `#ai-settings-modal` di semua modul workspace.
   - Total 42 tes unit lulus 100%.

---

## 📅 [2026-10-28] — Fitur Interactive Artifacts & Live Web Sandbox Universal (Claude / ChatGPT Canvas Style)

### 🎯 Peningkatan Utama yang Diterapkan
1. **Modul Universal Artifact Sandbox (`nano_asset/assets/js/artifact-sandbox.js`):**
   - Menghadirkan panel interaktif mandiri yang berjalan 100% *offline* di browser tanpa CDN eksternal.
   - Mengintegrasikan tiga tab navigasi utama:
     - 👁️ **Preview (Live Canvas):** Menjalankan kode HTML, CSS, SVG, dan JavaScript di dalam iframe terisolasi (`sandbox="allow-scripts allow-forms allow-popups allow-modals"`). Otomatis menginjeksi TailwindCSS lokal (`nano_asset/assets/js/tailwindcss.js`) jika komponen web menggunakan utilitas Tailwind.
     - 💻 **Kode (Source Inspector & Live Editor):** Editor kode sumber dengan nomor baris, tombol *Salin ke Clipboard*, dan tombol *Terapkan & Jalankan Ulang* untuk live tweaking.
     - 📟 **Console (JS Runtime Output):** Menangkap log `console.log`, `console.warn`, `console.info`, dan `console.error` yang terjadi di dalam iframe secara *real-time* via postMessage bridge terisolasi.

2. **Feedback Loop Auto-Debug ("Perbaiki dengan AI"):**
   - Deteksi otomatis *runtime error* (`window.onerror` & `unhandledrejection`) di dalam sandbox dengan banner indikator visual.
   - Tombol **"🛠️ Perbaiki dengan AI"** yang langsung memformat laporan error (pesan, baris kode, dan cuplikan sumber) ke dalam kolom input obrolan (`#prompt`) untuk diperbaiki langsung oleh model Gemma 4.

3. **Kontrol Viewport Responsif & Dual-Mode Layout:**
   - **Tampilan Viewport Instan:** Tombol switcher untuk simulasi Desktop (100% fluid), Tablet (768px), dan Mobile (380px) dengan bingkai perangkat modern.
   - **Resizable Side-Dock & Fullscreen Modal:** Splitter interaktif di sisi kiri dock yang dapat di-drag untuk mengubah lebar panel (dengan penyimpanan preferensi di localStorage) dan tombol ekspansi ke mode layar penuh.
   - **Download Mandiri:** Tombol unduh file `.html` standalone yang siap dijalankan di browser manapun secara offline.

4. **Integrasi Lintas Workspace (Preservation First & Zero-Breaking Change):**
   - Diintegrasikan secara seragam di `claude.html`, `VS.html`, `utama.html`, `utamaV2.html`, `vision_ulti.html`, dan `eduVis.html`.
   - Mengaitkan adapter global (`openArtifactDock`, `openPreviewModal`, `openSplitEditor`, `downloadCurrentArtifact`) sehingga seluruh tombol preview kode yang sudah ada langsung menikmati fitur sandbox tanpa mengubah logika obrolan yang ada.

5. **Verifikasi Tes Regresi Otomatis (`tests/artifact-sandbox.test.js`):**
   - Menambahkan 5 uji otomatis baru untuk API inti, injeksi harness, deteksi Tailwind, adapter backward compatibility, dan keberadaan dependensi di seluruh workspace.
   - 100% uji unit lulus tanpa regresi.

---

## 📅 [2026-10-12] — Optimalisasi Load UI, Standarisasi UI & Ekspor WYSIWYG Universal (PDF & DOCX)

### 🎯 Peningkatan Utama yang Diterapkan
1. **Optimalisasi Load UI (Non-Blocking Startup):**
   - Mengalihkan script parser dokumen berukuran besar (`pdf.min.js`, `mammoth.browser.min.js`, `xlsx.full.min.js`) yang sebelumnya memblokir parsing HTML di `<head>` menjadi `defer`.
   - Mengamankan inisialisasi worker `pdfjsLib.GlobalWorkerOptions` agar aman dieksekusi secara asinkron tanpa *race condition*.
   - Waktu initial paint dan interaktivitas chat menjadi jauh lebih responsif.

2. **Standarisasi UI & Komponen Toast Mengambang Universal:**
   - Menghadirkan `showToast(msg, type)` universal dengan efek glassmorphism, rounded-pill, dan transisi halus di semua 4 workspace (`utama.html`, `utamaV2.html`, `VS.html`, `claude.html`).
   - Menggantikan dialog native `alert()` yang mengganggu dengan feedback visual modern dan elegan.
   - Menyelaraskan menu ekspor di `claude.html` dengan dropdown khusus PDF dan Word (DOCX).

3. **Fungsi Ekspor WYSIWYG Universal (`nano_asset/assets/js/chat-export.js`):**
   - **Ekspor Cetak / PDF Bersih (Clean Print Vector View):**
     - Menggantikan teknik raster screenshot gelap `html2canvas` dengan struktur HTML cetak bersih (`@page A4 portrait`, `page-break-inside: avoid`).
     - Mengonversi chart canvas (Chart.js) dan diagram alir (Mermaid) menjadi gambar 2x resolusi tajam.
     - Tipografi hemat tinta, ramah cetak, dan teks tetap dapat diblok/diseleksi.
   - **Ekspor Dokumen Word Asli (True OOXML DOCX):**
     - Membangun paket `.docx` valid via JSZip: `[Content_Types].xml`, `_rels/.rels`, `word/document.xml`, `word/_rels/document.xml.rels`.
     - Menyematkan diagram dan chart ke direktori `word/media/` dengan relasi OpenXML drawingml (`<w:drawing>`).
     - Memetakan tabel HTML menjadi tabel native Word (`<w:tbl>`, `<w:tc>`, `<w:shd>`), serta heading dan code styling.
     - Kompatibel penuh dengan Microsoft Word, LibreOffice, dan Apple Pages.

4. **Verifikasi Tes Regresi Otomatis (`npm run test:regressions`):**
   - Menambahkan berkas tes `tests/export.test.js` (5 uji otomatis baru).
   - Total 52 uji otomatis lulus 100% tanpa regresi.

---

## 📅 [2026-10-11] — Audit Dependensi Lokal, Stabilisasi Fitur & Modernisasi UI

### 🎯 Prinsip Pengembangan yang Diterapkan
1. **Fitur yang ada tidak dibuang (Preservation First):** Seluruh kapabilitas yang sudah ada (LiteRT-LM, WebGPU, multimodal, dokumen OCR/parser, Pyodide Python execution, Chart.js, Mermaid, KaTeX, ekspor dokumen & PNG/SVG, session management, dan Gemini Live) dipertahankan 100% utuh tanpa penghapusan fungsionalitas.
2. **Bebas Konflik (Conflict-Free Integration):** Peningkatan kode menyelaraskan loader lokal menggunakan pola yang sudah teruji di `VS.html` dan `claude.html`, sehingga tidak berbenturan dengan mekanisme rendering, bridge Swift/WebKit, maupun session storage.
3. **Standar Desain UI Modern:** Typography disempurnakan dengan rendering font lokal (Plus Jakarta Sans, Inter, Fira Code), subpixel font anti-aliasing (`-webkit-font-smoothing: antialiased`), transisi warna halus, scrollbar tipis modern, dan penataan layout responsif tanpa merusak rasio visualizer.
4. **100% Dependensi Dibuat Lokal (Full Offline Resilience):** Seluruh panggilan CDN pihak ketiga (`cdnjs.cloudflare.com`, `cdn.jsdelivr.net`, `unpkg.com`, `fonts.googleapis.com`, `cdn.tailwindcss.com`) diaudit dan dialihkan ke aset lokal yang tersimpan di `nano_asset/assets/` dan `nano_asset/models/`.
5. **Catatan Perubahan & Changelog Terstruktur:** Dokumentasi komprehensif atas setiap file yang diubah dan diverifikasi dengan tes regresi otomatis.

---

### 📦 Rincian Audit dan Penyelarasan Dependensi Lokal

| Berkas | Dependensi Sebelumnya (Eksternal/CDN) | Pengganti Lokal (Offline-Ready) | Status |
| :--- | :--- | :--- | :--- |
| **`utama.html`** | `cdnjs.cloudflare.com/.../html2pdf.bundle.min.js` | `nano_asset/assets/js/html2pdf.bundle.min.js` | ✅ Selesai |
| | `fonts.googleapis.com` (Plus Jakarta Sans, JetBrains Mono) | `@font-face` lokal (`jakarta-400.woff2`, `inter-400.woff2`, `fira-code-400.woff2`) | ✅ Selesai |
| | `cdn.jsdelivr.net/npm/@xenova/transformers@2.17.2` | `./nano_asset/assets/js/transformers.min.js` (`localModelPath: ./nano_asset/models/`) | ✅ Selesai |
| | `cdn.jsdelivr.net/pyodide/v0.25.0/full/pyodide.js` | `nano_asset/assets/js/pyodide.js` (`indexURL: nano_asset/assets/js/`) | ✅ Selesai |
| | `cdn.tailwindcss.com` (di injeksi preview iframe) | `nano_asset/assets/js/tailwindcss.js` | ✅ Selesai |
| **`utamaV2.html`** | `cdnjs.cloudflare.com/.../html2pdf.bundle.min.js` | `nano_asset/assets/js/html2pdf.bundle.min.js` | ✅ Selesai |
| | `unpkg.com/lucide@latest` | `nano_asset/assets/js/lucide.min.js` | ✅ Selesai |
| | `cdn.jsdelivr.net/npm/@xenova/transformers@2.17.2` | `./nano_asset/assets/js/transformers.min.js` (`localModelPath: ./nano_asset/models/`) | ✅ Selesai |
| | `cdn.jsdelivr.net/pyodide/v0.25.0/full/pyodide.js` | `nano_asset/assets/js/pyodide.js` (`indexURL: nano_asset/assets/js/`) | ✅ Selesai |
| | `cdn.tailwindcss.com` (di injeksi preview iframe) | `nano_asset/assets/js/tailwindcss.js` | ✅ Selesai |
| **`vision_ulti.html`** | `cdnjs.cloudflare.com/.../html2pdf.bundle.min.js` | `nano_asset/assets/js/html2pdf.bundle.min.js` | ✅ Selesai |
| | `cdnjs.cloudflare.com/.../highlight.min.js` & theme | `nano_asset/assets/js/highlight.min.js` & `github-dark.min.css` | ✅ Selesai |
| | `cdn.jsdelivr.net/npm/chart.js` | `nano_asset/assets/js/chart.min.js` | ✅ Selesai |
| | `cdn.jsdelivr.net/npm/markmap-autoloader@latest` | `nano_asset/assets/js/markmap-autoloader.js` (+ d3, lib, view lokal) | ✅ Selesai |
| | `cdnjs.cloudflare.com/.../raphael.min.js` & `flowchart.min.js` | `nano_asset/assets/js/raphael.min.js` & `flowchart.min.js` | ✅ Selesai |
| | `cdnjs.cloudflare.com/.../codemirror` (CSS & JS modes) | `nano_asset/assets/css/codemirror.min.css`, `material-darker.min.css`, `codemirror.min.js`, mode js, css, xml, htmlmixed | ✅ Selesai |
| | `fonts.googleapis.com` (Plus Jakarta Sans, JetBrains Mono) | `@font-face` lokal (`jakarta-400.woff2`, `inter-400.woff2`, `fira-code-400.woff2`) | ✅ Selesai |
| | `cdn.jsdelivr.net/npm/@xenova/transformers@2.17.2` | `./nano_asset/assets/js/transformers.min.js` (`localModelPath: ./nano_asset/models/`) | ✅ Selesai |
| | `cdn.jsdelivr.net/pyodide/v0.25.0/full/pyodide.js` | `nano_asset/assets/js/pyodide.js` (`indexURL: nano_asset/assets/js/`) | ✅ Selesai |
| | `cdn.tailwindcss.com` (di injeksi preview iframe) | `nano_asset/assets/js/tailwindcss.js` | ✅ Selesai |
| **`ai-liquid-glass.html`** | `cdn.tailwindcss.com` & `unpkg.com/lucide@latest` | `./nano_asset/assets/js/tailwindcss.js` & `./nano_asset/assets/js/lucide.min.js` | ✅ Selesai |
| | Fallback font bawaan | `@font-face` lokal (`inter-400.woff2`) | ✅ Selesai |
| **`index2.html`** | `fonts.googleapis.com` (Inter, JetBrains Mono) | `@font-face` lokal (`inter-400.woff2`, `fira-code-400.woff2`) | ✅ Selesai |
| **`index.html`** | Ketergantungan font OS bawaan | `@font-face` lokal (`inter-400.woff2`) eksplisit | ✅ Selesai |
| **`gemma_chat_gui.py`** | Hanya mengizinkan file statis di `nano_asset/assets` | Ditambahkan otorisasi untuk `nano_asset/models` dan `vision_ulti.html` | ✅ Selesai |

---

### 🛡️ Hasil Pengujian Regresi Otomatis (`npm run test:regressions`)

Semua 22 uji otomatis dijalankan dan berhasil 100% tanpa kegagalan:
```text
✔ mindmap labels with numbering and punctuation normalize into a valid tree shape
✔ mindmap without an explicit root promotes its first label without losing descendants
✔ flowchart normalization remains independent from mindmap handling
✔ Mermaid syntax is auto-detected and normalized across supported diagram types
✔ chat pages unwrap the nested Chart.js configuration before validation
✔ AI chart_type data rows are converted to Chart.js datasets for all chat pages
✔ Mermaid loader failures preserve the diagram source in VS and Claude pages
✔ Markdown table PNG export helper is loaded on rendered chat and document pages
✔ Mermaid export keeps SVG and PNG buttons in its shared toolbar
✔ Gemini Live loads PNG export controls for its Chart.js and Markdown table output
✔ PNG exports use the native save bridge when available and do not change chart sizing
✔ native WebView cache reload clears only HTTP caches and preserves site storage
✔ native app title matches the EduVis AI Gallery landing page
✔ native launcher follows landing-page structure while preserving native workspace controls
✔ native model center supports status, selection, deletion, and drag-and-drop imports
✔ Gemini Live uses native macOS speech recognition inside the launcher
✔ Gemini Live forwards native speech events through its existing recognition handlers
✔ landing page links all workspaces to their local preview images
✔ landing page developer modal uses the local portrait and has accessible open and close controls
✔ landing page shows usage and model setup splash with a reopen control
✔ Utama pages expand chart replies and keep Chart.js responsive to the container
✔ completed AI replies initialize and resize charts without requiring a UI switch

ℹ tests 22
ℹ suites 0
ℹ pass 22
ℹ fail 0
ℹ duration_ms 83ms
```

---

### ⚡ Optimasi Lazy-Loading Tier-1: Mempercepat Pemuatan Awal Halaman Utama (`utama.html` & `utamaV2.html`)

Untuk meningkatkan kecepatan respons dan performa *initial load*, pustaka visualisasi dan utilitas berat dialihkan ke sistem pemuatan modular *on-demand* (lazy loading dinamis berbasis Promise):

1. **Pustaka yang Dimuat Secara Dinamis (Deferred/On-Demand):**
   - **Mermaid.js** (~2.8 MB): Hanya dimuat jika pesan AI atau riwayat percakapan memuat blok diagram `mermaid` atau saat pengguna menekan tombol *retry render*.
   - **Chart.js** (~200 KB): Hanya dimuat jika percakapan memuat canvas grafik `ai-chart`.
   - **Markmap Suite** (D3 v7, markmap-lib, markmap-view, markmap-autoloader): Hanya dimuat jika diagram mindmap `markmap-svg` ditemukan.
   - **Flowchart.js & Raphael.js**: Hanya dimuat jika terdapat elemen diagram `flowchart-diagram`.
   - **CodeMirror Suite** (CSS tema, mode HTML/CSS/JS/XML, parser): Hanya dimuat saat panel *Split Code Editor* dibuka oleh pengguna.
   - **JSZip & FileSaver.js**: Hanya dimuat saat pengguna mengekspor riwayat percakapan ke format Word (`.docx`).
   - **html2pdf.js**: Hanya dimuat saat pengguna memicu ekspor percakapan ke dokumen PDF.

2. **Mekanisme Pemuatan Aman & Bebas Duplikasi:**
   - Dibuat fungsi helper global `window.loadScriptOnce(src)` dan `window.loadCssOnce(href)` yang menjamin berkas script tidak pernah dimuat lebih dari sekali.
   - Dibuat helper wrapper: `ensureMermaid()`, `ensureMarkmap()`, `ensureChart()`, `ensureZipSave()`, `ensureHtml2Pdf()`, `ensureFlowchart()`, dan `ensureCodeMirror()`.
   - Seluruh pemanggil di `utama.html` dan `utamaV2.html` (`finishLoadingBubble`, render riwayat, `retryMermaidRender`, `retryChartRender`, `exportChatToPDF`, `exportHistoryToPDF`, `exportHistoryToDocx`, dan `openSplitEditor`) telah diintegrasikan dengan *async/await* memastikan eksekusi mulus tanpa jeda blocking di thread utama awal.

---

### 🧠 Pemetaan Cerdas Intensi Visual Bahasa Alami (`intent-enricher.js`)

Ditambahkan sistem pemetaan otomatis tanpa perlu sintaks eksplisit dari pengguna:
1. **Deteksi Kata Kunci Alami (*Transparent Prompt Enrichment*):**
   - **Alur / Proses / Flowchart:** Kata kunci `alur`, `flowchart`, `diagram alur`, `diagram proses`, `tahapan`, `siklus`, `workflow`, `sop`, `skema proses` otomatis disuntikkan instruksi Mermaid flowchart (`flowchart TD` / `flowchart LR`) tanpa mengubah tampilan gelembung teks pengguna.
   - **Grafik / Statistik Data:** Kata kunci `grafik`, `chart`, `diagram batang`, `diagram lingkaran`, `pie chart`, `bar chart`, `tren data`, `statistik`, `perbandingan data` otomatis disuntikkan instruksi Chart.js JSON murni (` ```chart `).
   - **Peta Konsep / Mindmap:** Kata kunci `mindmap`, `peta konsep`, `kerangka materi`, `pohon topik` otomatis disuntikkan instruksi Mermaid mindmap (`root((Topik Utama))`).
   - **Rumus Matematika:** Kata kunci matematika dan LaTeX otomatis disuntikkan instruksi KaTeX (`$...$` dan `$$...$$`).
2. **Kompatibilitas Mundur Penuh:**
   - Seluruh pemanggil fungsi lama `applyKaTeXPrompt(text)` di `utama.html`, `utamaV2.html`, `VS.html`, `claude.html`, dan `vision_ulti.html` dialihkan ke `GemmaIntent.enrichPrompt(text)` secara mulus.
3. **Pill / Chip Aksi Cepat UI:**
   - Ditambahkan tombol pintas interaktif visual pada composer toolbar (`🔀 Alur`, `📊 Grafik`, `🧠 Peta Konsep`) di `utama.html` dan `utamaV2.html` untuk mempermudah pengguna sekali klik.
4. **Smart Fallback:**
   - Disediakan konverter otomatis `convertNumberedListToFlowchart` dan `convertTableToChartConfig` untuk menangani teks bernomor atau tabel angka menjadi visual interaktif.
5. **Verifikasi Uji Otomatis:**
   - Ditambahkan berkas uji baru `tests/intent-mapping.test.js`. Seluruh 29/29 uji regresi berhasil 100%.

---

### 💡 Rekomendasi Pemeliharaan ke Depan
1. **Pustaka Baru Selalu Disimpan di `nano_asset/assets/`:** Jika di kemudian hari menambahkan komponen JavaScript atau CSS baru, letakkan di folder lokal dan hindari menyisipkan URL CDN.
2. **Model Embeddings Tambahan:** Jika menambahkan model transformer lokal baru selain `all-MiniLM-L6-v2` dan `multilingual-e5-small`, letakkan di `nano_asset/models/<nama-model>/` agar otomatis terlayani oleh backend Python.
3. **Jalankan Uji Regresi Secara Berkala:** Selalu jalankan `npm run test:regressions` sebelum melakukan rilis untuk memastikan kontrak UI dan visualizer tetap stabil.

---

## 🚀 [2026-10-11] — Integrasi Model Embedding `multilingual-e5-small` & Modernisasi UI 4 Antarmuka Prioritas

### 1. 🤖 Pemasangan Model Transformer Embedding Baru (`multilingual-e5-small`)
- **Lokalisasi 100% Offline**: Mengunduh dan menempatkan paket model kuantisasi ONNX lengkap di `nano_asset/models/multilingual-e5-small/`:
  - `config.json` (384 dimensi, max 512 context tokens)
  - `tokenizer.json` (~16 MB)
  - `tokenizer_config.json`
  - `special_tokens_map.json`
  - `onnx/model_quantized.onnx` (~113 MB)
- **Symlink Kompatibilitas**: Membuat symlink `nano_asset/models/Xenova/multilingual-e5-small` agar path model dengan atau tanpa prefix `Xenova/` dapat diselesaikan secara instan oleh `transformers.js`.
- **Integrasi Asymmetric Retrieval**:
  - Pertanyaan pencarian kueri otomatis diberikan prefix `query: <pertanyaan>` (`extractEmbedding(query, true)`).
  - Paragraf dokumen/modul ajar otomatis diberikan prefix `passage: <chunk>` (`extractEmbedding(chunk, false)`).
  - Menghasilkan akurasi pencarian semantik bahasa Indonesia yang jauh lebih presisi dibandingkan model lama.
- **Graceful Fallback**: Menjaga stabilitas dengan fallback otomatis ke `all-MiniLM-L6-v2` jika pemuatan model utama mengalami kendala.
- **Penerapan Merata di 4 Halaman**: `utama.html`, `utamaV2.html`, `VS.html`, dan `claude.html`.

### 2. 🎨 Modernisasi UI Standar Modern pada 4 Antarmuka Prioritas (`utama`, `utamaV2`, `VS`, `claude`)
- **Visual Quick Action Chips**:
  - `utama.html`: Ditambahkan tombol pintas `🔀 Alur`, `📊 Grafik`, dan `🧠 Mindmap` pada toolbar composer.
  - `utamaV2.html`: Ditambahkan quick prompt `🔀 Alur`, `📊 Grafik`, dan `🧠 Mindmap` pada footer liquid glass.
  - `VS.html`: Ditambahkan chip `🔀 Alur`, `📊 Grafik`, dan `🧠 Mindmap` berdampingan dengan specialist chip `Ringkasan` dan `Perbaiki`.
  - `claude.html`: Ditambahkan deretan chip minimalis ala Anthropic (`🔀 Alur`, `📊 Grafik`, `🧠 Mindmap`, `📝 Ringkas`, `✨ Perbaiki`) di atas area drop-zone.
- **Fungsi Terpadu `insertVisualPromptPrefix(type)`**:
  - Diterapkan secara konsisten di semua 4 antarmuka (`utama.html`, `utamaV2.html`, `VS.html`, `claude.html`).
  - Menginjeksi template prompt yang memicu *Smart Intent Enricher* secara alami ke input box pengguna.
- **Micro-Interactions & Desain Interaktif**:
  - Menambahkan kelas dan styling `.quick-chip` serta `.quick-prompt`:
    - Transisi halus `cubic-bezier(0.16, 1, 0.3, 1)`
    - Hover lift elevation (`translateY(-1px)`) dengan bayangan halus
    - Umpan balik tekan (*active press*) `scale(0.96)`
- **Glassmorphism & Kontras**:
  - Area input *drop-zone* dipercantik dengan backdrop blur tinggi, border transparan dengan highlight kontras, serta glow saat *focus-within*.
  - Menjaga adaptasi warna tema Gelap (Dark), Terang (Light), OLED, dan Hacker tetap konsisten.
- **Badge Indikator Model Knowledge Base**:
  - Menyematkan badge status visual terverifikasi (`multilingual-e5-small (384-dim • 512-ctx)`) pada accordion/sidebar Knowledge Base di `utama.html`, `utamaV2.html`, `VS.html`, dan `claude.html`.
- **Kartu Saran Layar Pembuka (*Initial Placeholder Cards*)**:
  - Menyempurnakan kartu saran sambutan pada `utama.html`, `VS.html`, dan `claude.html` dengan opsi prompt Alur / Flowchart, Grafik Data, dan Peta Konsep terstruktur.

### 3. 🧪 Verifikasi Tes Regresi (`tests/embeddings.test.js`)
- Menambahkan test suite baru `tests/embeddings.test.js` untuk memvalidasi kelengkapan berkas model lokal `multilingual-e5-small`, validitas konfigurasi (384 dimensi, 512 sequence), serta kontrak kode pada seluruh 4 halaman chat.
- **Hasil Uji Regresi**: **31 dari 31 uji lolos 100% (Pass: 31, Fail: 0)** dalam waktu ~90ms.

---

## [UI & Streaming State Management] - 2026-10-11
### 🚀 Penyempurnaan Manajemen UI & Streaming State pada 4 Antarmuka Prioritas (`utama`, `utamaV2`, `VS`, `claude`)
- **Smart Intent-Aware Auto-Scroll (`scrollToBottom(force = false)`)**:
  - Menyelesaikan masalah *scroll fighting* / *jumping scroll* saat model AI memproduksi streaming respons panjang.
  - Memeriksa selisih jarak kontainer obrolan (`scrollHeight - clientHeight - scrollTop < 150px`):
    - Jika pengguna sedang berada di dasar: auto-scroll mengikuti aliran token masuk secara mulus.
    - Jika pengguna menggulir ke atas untuk membaca teks sebelumnya: auto-scroll ditahan (*freeze*), dan tombol melayang `#scroll-to-bottom-btn` otomatis ditampilkan.
  - Pengiriman pesan baru, penambahan bubble respons awal, dan klik tombol `#scroll-to-bottom-btn` memicu `scrollToBottom(true)` untuk melompat langsung ke bawah.
- **Smooth Blinking Streaming Cursor (`.streaming-cursor`)**:
  - Diterapkan di `utama.html`, `utamaV2.html`, `VS.html`, dan `claude.html`.
  - Fungsi penata `appendStreamingCursor(html)` meletakkan kursor inline tepat di ujung kata/paragraf terakhir (`</p>`, `</li>`, dsb.) selama token streaming mengalir.
  - Begitu proses streaming selesai (`finishLoadingBubble` / `skipMermaid === false`), kursor secara otomatis dibersihkan dan layout final komponen visual (Chart.js, Mermaid, KaTeX) dirender bersih.
- **Zero-Flicker Diagram Streaming**:
  - Komponen diagram berat (Mermaid.js, Chart.js) tetap ditunda (*deferred*) selama streaming teks aktif untuk mencegah *crash* atau kedipan sintaks parsial.
- **Uji Regresi Penuh**: Seluruh 31 pengujian (`npm run test:regressions`) terverifikasi lulus 100% (Pass: 31, Fail: 0).

---

## [Context Memory Management & Native Apple WKWebView Architecture] - 2026-10-11
### 🧠 Implementasi Manajemen Konteks Riwayat & Memori Vektor (Tahap 1 & Tahap 2)

#### 1. Arsitektur Kompatibilitas Apple WKWebView (`gemma_webview.swift`) & Klien Web
- **Multi-Tier Summarization Engine**:
  - **Tier 1 (Apple WKWebView / Native Desktop)**: Mengakses loopback HTTP server LiteRT-LM / Ollama lokal (`/v1/chat/completions`) dengan `AbortController` timeout (3.5 detik) tanpa blocking.
  - **Tier 2 (Chrome Built-in AI)**: Memanfaatkan `window.ai.summarizer` jika berjalan di peramban Chromium yang mendukung on-device AI.
  - **Tier 3 (Extractive Heuristic Fallback)**: Ekstraktor deterministik 0ms yang mengekstrak pokok pembahasan pengguna dan catatan asisten secara instan tanpa dependensi jaringan, menjamin zero-latency dan zero-failure bahkan saat offline penuh atau saat model lokal sedang sibuk.
- **Persistensi IndexedDB Asli macOS**:
  - Memanfaatkan store `GeminiChatDB` versi 4 (`history`, `settings`, `kb_files`, `kb_chunks`) yang dilindungi dari pembersihan cache oleh `gemma_webview.swift` (`WKWebsiteDataTypeDiskCache` & `MemoryCache` dibersihkan, sedangkan `IndexedDBDatabases` dipertahankan).
  - Variabel `window.__currentSessionSummary` otomatis direstorasi saat inisialisasi halaman dari store `settings` (`current_session_summary`).

#### 2. Tahap 1: Short-Term Memory (Summary Buffer Strategy)
- **Modul Pusat**: `nano_asset/assets/js/context-memory-manager.js` mengekspos API `GemmaMemory`.
- **Auto-Compact Trigger (`checkAndCompactHistory`)**:
  - Berjalan otomatis setelah pesan baru berhasil disimpan di IndexedDB (`saveMessageToHistory`).
  - Jika riwayat melampaui batas ambang (> 12 giliran pesan), sistem secara non-blocking memadatkan giliran pesan lama menjadi ringkasan konteks berjalan (*rolling context summary*) dan mempertahankan 6 giliran pesan terbaru.
- **Injeksi Konteks Cerdas (`getChatHistoryFromDB`)**:
  - Memasukkan `[Konteks Pembahasan Sebelumnya]: <ringkasan>` ke dalam array pesan sistem tanpa mengorbankan batasan token KV-cache (4.096 token).

#### 3. Tahap 2: Long-Term Memory (Knowledge Base Vector RAG)
- **1-Click Pengarsipan ke KB (`archiveSessionToKnowledgeBase`)**:
  - Tombol **"Arsipkan ke KB (Vektor RAG)"** terpasang rapi pada 4 antarmuka prioritas:
    - `utama.html`: Menu panel sesi kiri.
    - `utamaV2.html`: Menu panel sesi liquid glass.
    - `VS.html`: Sidebar sesi & riwayat obrolan.
    - `claude.html`: Accordion Knowledge Base & footer dialog modal sesi tersimpan.
  - Percakapan diekspor menjadi dokumen Markdown terstruktur rapi via `exportConversationAsMemoryDocument()`.
  - Teks dipecah menjadi potongan (*chunks*) dan divektorkan menggunakan model lokal `multilingual-e5-small` (384 dimensi), disimpan ke tabel IndexedDB `kb_files` dan `kb_chunks` dengan kategori `session_memory`.
  - Informasi tersimpan otomatis muncul dan siap diretrieve kembali secara semantik lintas sesi mingguan/bulanan.

#### 4. Optimalisasi Pelengkap yang Dituntaskan
- **Penyelarasan Ambang Batas Relevansi RAG (`searchKnowledgeBase`)**:
  - Menyelaraskan filter kesamaan kosinus (`scoredChunks.filter(c => c.score > 0.35)`) pada `utama.html` dan `utamaV2.html` konsisten dengan `VS.html` dan `claude.html`. Kueri umum/sapaan tidak lagi sembarangan memuat dokumen KB yang tidak berkaitan.
- **Ketahanan Line Buffer Streaming SSE/JSON (`sendToOllama`)**:
  - Menambahkan line buffering (`buffer += ...; const lines = buffer.split('\n'); buffer = lines.pop();`) agar pemotongan paket data jaringan di tengah baris JSON tidak menyebabkan error parsing dan token hilang.
- **Preservasi Ringkasan Sesi pada Token Trimming (`trimHistoryToFitTokens`)**:
  - Mengisolasi pesan ringkasan `[Konteks Pembahasan Sebelumnya]` agar tidak terbuang saat pesan-pesan lama dipangkas karena anggaran token mencapai batas KV-cache.
- **Penyimpanan dan Restorasi Penuh `sessionSummary` (`saveCurrentSession` & `loadSession`)**:
  - Menyimpan `sessionSummary` ke dalam data sesi di IndexedDB dan memulihkannya kembali saat sesi dibuka, memastikan memori jangka pendek tetap sinkron lintas muat sesi.

#### 5. 🧪 Hasil Pengujian Regresi (`tests/memory-manager.test.js`)
- Ditambahkan 9 pengujian otomatis mencakup memori konteks, WebKit fallback, penyimpanan sesi, dan buffer streaming.
- **Status Akhir Pengujian**: **40 dari 40 uji lulus 100% (Pass: 40, Fail: 0)** dalam waktu 185ms.

---

### 🎛️ [2026-10-11] — Indikator Beban Memori Real-Time (Context Window Gauge)

#### 1. Indikator Visual Kapasitas Token KV-Cache Real-Time
- **Memory Gauge Pill di Status Bar & Header**:
  - Diterapkan secara seragam di 4 antarmuka chat (`utama.html`, `utamaV2.html`, `VS.html`, dan `claude.html`).
  - Posisi di bilah atas/header (`#context-viewer-badge`), memberikan visibilitas langsung terhadap penggunaan memori KV-cache dari batas default 4.096 token.
- **Tiga Ambang Batas Visual Dinamis**:
  - 🟢 **Hijau (< 50%)**: Diskusi awal / ringan (misal: `🟢 Memori: 1.200 / 4.096 (29%)`) dengan style emerald soft border.
  - 🟡 **Kuning (50% - 75%)**: Diskusi mendalam (misal: `🟡 Memori: 2.300 / 4.096 (56%)`) dengan style amber warning.
  - 🟠 **Oranye (> 75%)**: Konteks mendekati batas KV-cache (misal: `🟠 Memori: 3.250 / 4.096 (79%)`) dengan style orange border (dan animasi denyut halus / *pulse* jika >= 85%) sebagai penanda visual bahwa Auto-Compact Summary Buffer aktif merampingkan riwayat.
- **Tooltip Informatif Multi-Line**:
  - Menghitung dan menampilkan perincian token transparan saat kursor diarahkan:
    - *System Prompt token count*
    - *Ringkasan Berjalan (Session Summary) token count*
    - *Riwayat Obrolan (Chat History) token count & jumlah pesan*
    - *Sisa Anggaran Output AI*
    - *Peringatan otomatis saat mode peringkasan aktif*

#### 2. Kalibrasi Token & Arsitektur API (`GemmaMemory`)
- **Fungsi Estimasi Token (`GemmaMemory.estimateTokens`)**:
  - Dikalibrasi khusus untuk Bahasa Indonesia & istilah teknis pada rasio ~3.5 karakter per token.
- **Perhitungan Rincian Beban (`GemmaMemory.getContextBreakdown`)**:
  - Menghitung akurat `maxTokens`, `totalUsed`, `remainingTokens`, `percentage`, `state`, dan sub-alokasi token.
- **Pembaruan DOM Universal (`GemmaMemory.renderContextGauge`)**:
  - Mengupdate kelas status, badge teks, dan tooltip secara reaktif dan aman tanpa flicker.
- **Sinkronisasi Siklus Hidup Obrolan (`updateContextViewer`)**:
  - Dipicu pada seluruh event percakapan: inisialisasi aplikasi, penyimpanan pesan baru (`saveMessageToHistory`), pemadatan riwayat (`checkAndCompactHistory`), pembersihan riwayat (`clearHistory`), reset chat (`resetChat`), dan pergantian sesi (`loadSession`).

#### 3. 🧪 Verifikasi & Pengujian Regresi Otomatis
- Penambahan 4 unit & integrasi tes di `tests/memory-manager.test.js`:
  - `GemmaMemory estimateTokens calculates token count properly`
  - `GemmaMemory getContextBreakdown correctly evaluates green, yellow, and orange thresholds`
  - `GemmaMemory renderContextGauge updates element styling and tooltip across states`
  - `all chat interfaces provide context gauge pill and wire up updateContextViewer`
- **Total Pengujian**: **44 dari 44 uji lulus 100% (Pass: 44, Fail: 0)** tanpa regresi pada native WKWebView dan browser klien.






---

### 🔍 [2026-10-11] — Context Inspector (Popover Detail Memori Interaktif)

- **Pil memori kini bisa diklik** (juga via `Enter`/`Spasi`, `role="button"`, `aria-expanded`) di `utama.html`, `utamaV2.html`, `VS.html`, `claude.html`.
- **Popover glass mandiri** di `context-memory-manager.js` (CSS sendiri, tanpa Tailwind/CDN; aman untuk WKWebView):
  - Stacked bar: 🟦 System Prompt · 🟪 Ringkasan Berjalan · 🟩 Riwayat Obrolan · ⬜ Sisa Output.
  - Legenda token + persentase, isi Ringkasan Berjalan (lipat, dirender via `textContent`).
  - Aksi **Ringkas Sekarang** (`checkAndCompactHistory(true)`, ambang = 6 pesan) dan **Hapus Ringkasan** (`GemmaMemory.clearStoredSummary(db)`, riwayat tetap utuh).
  - Tutup via `Esc`, klik di luar, atau tombol ×; mode bottom-sheet di layar ≤ 640px dengan `safe-area-inset-bottom`; mendukung tema terang.
- **Akurasi gauge**: `getContextBreakdown` menerima `historyWindow` sehingga hanya menghitung pesan yang benar-benar dikirim ke model (16 pesan di utama/utamaV2, 10 di VS/claude).
- `checkAndCompactHistory` kini mengembalikan Promise yang selesai setelah pemadatan.
- Tes: 47/47 lulus.
