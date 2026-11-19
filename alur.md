# Flow Project Gemma4 (Teknis)

Sumber utama: [README.md](README.md)

Project ini pada dasarnya adalah aplikasi UI AI berbasis browser yang menjalankan model Gemma 4 secara lokal di perangkat pengguna. Arsitekturnya bisa dipahami sebagai kombinasi dari:

- browser frontend untuk chat/UI
- backend lokal Python untuk service model dan HTTPS
- runtime LiteRT-LM / MediaPipe untuk inferensi LLM
- cache browser OPFS agar model tidak diunduh ulang
- parser/renderer untuk Markdown, KaTeX, Mermaid, Chart.js, dll.

## 1. Entry point: UI dan launcher

Saat aplikasi dibuka, user masuk ke portal web seperti [index.html](index.html) atau workspace-specific page seperti [utama.html](utama.html), [VS.html](VS.html), [claude.html](claude.html), atau [eduVis.html](eduVis.html).

Pada macOS, launcher native dibuat melalui [gemma_chat_gui.py](gemma_chat_gui.py). File ini berfungsi seperti pengelola aplikasi:
- menginstal / menjalankan service lokal
- menyiapkan app bundle native di `~/Applications/`
- menjalankan server lokal dan backend model
- menghubungkan WebView ke portal UI
- menangani lifecycle aplikasi (start/stop)

Jadi ada dua mode:
- Mode browser biasa: user membuka halaman web via localhost/HTTPS lokal
- Mode native launcher: aplikasi macOS memanggil browser/WebView dan menyalakan backend di background

---

## 2. Model lifecycle: impor, pilih, dan aktifkan

Model yang dipakai adalah file `.litertlm` atau model dari Hugging Face komunitas. Dalam README, user bisa:
- memilih model dari dropdown
- mengunduh model otomatis dari repo Hugging Face
- atau mengimpor file `.litertlm` lokal ke LiteRT-LM

Flownya kira-kira seperti ini:

1. User membuka pengaturan UI
2. User memilih model aktif
3. Aplikasi mengecek apakah model sudah ada di cache lokal
4. Jika belum ada, model diunduh dan disimpan di OPFS / cache browser
5. Model diaktifkan di LiteRT-LM
6. Model siap dipanggil untuk inference

Ini penting karena project memusatkan penyimpanan model pada browser cache lokal, bukan di server terpusat.

---

## 3. Backend lokal dan servis API

Project tidak bergantung pada API cloud. Model dijalankan lewat runtime lokal seperti LiteRT-LM dan MediaPipe.

Dalam README disebut:
- server UI/API berjalan di HTTPS pada port `1234`
- API internal LiteRT-LM hanya mendengarkan pada loopback `127.0.0.1:1235`
- portal bisa diakses dari jaringan lokal melalui IP MAC: `https://IP-MAC:1234/`
- API klien dapat dipanggil pada `https://IP-MAC:1234/v1`

Jadi alur teknisnya:

- frontend memanggil endpoint seperti `/v1/chat/completions`
- backend lokal memproses request
- backend meneruskan ke model yang sedang aktif
- hasil token dikirim balik ke browser
- UI menampilkan output secara real time

File backend utama yang relevan:
- [server.py](server.py)
- [gemma_chat_gui.py](gemma_chat_gui.py)

---

## 4. Inferensi client-side: browser + MediaPipe + WebAssembly

Ini inti dari project.

Flow inferensi browser:

1. User mengetik prompt di UI
2. Browser memanggil API inference lokal
3. MediaPipe Web LLM Inference API memuat model dari cache OPFS
4. Model dieksekusi di runtime WebAssembly
5. Komputasi didelegasikan ke WebGPU/WebGL jika tersedia
6. Token hasil inference muncul bertahap

Dalam README, flow ini dijelaskan sebagai:
- `UI -> MediaPipe -> OPFS -> WASM -> GPU`
- Token raw tampil di Shadow DOM
- lalu dideteksi oleh `MutationObserver`

Jadi output model tidak langsung tampil sebagai plain text. Ia diproses melalui pipeline interseptor:

- token baru masuk dari model
- dideteksi oleh MutationObserver
- teks disusun ulang
- lalu dirender ke format rich output seperti:
  - Markdown
  - KaTeX (rumus)
  - Mermaid (diagram)
  - PrismJS (highlight kode)
  - Chart.js (grafik)
  - tabel hasil render

Ini menjelaskan kenapa project ini terasa seperti aplikasi chat AI yang sangat “visual” dibanding chat biasa.

---

## 5. Rendering output: dari token ke UI kaya

Setelah model mengeluarkan output, browser melakukan parsing dan rendering:

- Markdown parser: format teks seperti heading, list, quote, table
- KaTeX: render formula matematika
- PrismJS: syntax highlighting untuk blok kode
- MermaidJS: diagram flowchart / mindmap
- Chart.js: grafik interaktif
- table Markdown: ekspor ke PNG

Flownya kira-kira:

`raw token -> MutationObserver -> markdown pipeline -> HTML + CSS + JS -> rendered UI`

Jadi front-end bukan sekadar menampilkan teks, tapi membangun UI “rich output” sesuai informasi model.

---

## 6. Data dan sesi

Project juga memiliki sistem sesi yang disimpan di browser:
- nama sesi
- isi percakapan
- pencarian sesi
- ekspor/import JSON
- validasi format sesi
- penghapusan ID database sumber saat import

Artinya semua data chat bisa dibackup dan dipindahkan antar browser/perangkat tanpa mengandalkan backend cloud.

---

## 7. Dokumen/vision assistant

Ada fitur tambahan seperti [vision_ulti.html](vision_ulti.html) yang berfungsi sebagai asisten dokumen cerdas:
- upload PDF, Word, Excel, PPT
- ekstraksi isi dokumen
- Q&A atas dokumen
- berjalan secara offline

Secara teknis, ini adalah fitur AI lokal pada dokumen yang diproses di browser dan model lokal.

---

## 8. Arus kerja lengkap end-to-end

Secara singkat, flow project adalah:

1. User membuka portal web atau app launcher
2. Launcher/startup menyiapkan backend lokal dan model runtime
3. User memilih atau mengimpor model
4. Browser memuat model dari cache lokal / download otomatis
5. Model dieksekusi via MediaPipe + WASM + WebGPU/WebGL
6. Hasil token dipantau melalui MutationObserver
7. Output diparse menjadi markdown, diagram, formula, grafik
8. Hasil ditampilkan ke UI
9. User bisa simpan/export sesi, model, atau hasil visualisasi

---

## 9. Kesimpulan teknis

Project ini bukan “server AI biasa” yang menjalankan model di cloud. Ia lebih mirip:
- local-first AI app
- browser-native inference
- offline/private model runtime
- rich frontend renderer for LLM output

Jadi inti teknisnya adalah gabungan dari:
- frontend modern HTML/CSS/JS
- runtime model lokal LiteRT-LM
- browser GPU acceleration
- OPFS cache
- real-time parsing output menjadi UI kaya
