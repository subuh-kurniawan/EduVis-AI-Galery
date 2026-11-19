/**
 * EduVis AI Multi-Language & Internationalization (i18n) Engine
 * Menangani lokalisasi antarmuka otomatis (Auto-Detect Locale) & pemilihan manual (EN / ID)
 * Kompatibel dengan Apple HIG, WebKit macOS native, dan peramban multi-client LAN.
 */

(() => {
    'use strict';

    if (window.EduVisi18n) return;

    const STORAGE_KEY = 'eduvis_user_lang'; // 'auto' | 'en' | 'id'
    
    const DICTIONARY = {
        en: {
            langName: 'English',
            code: 'en',
            locale: 'en-US',
            // Actions & Navigation
            send: 'Send',
            sendShortcut: 'Send ↵',
            ask: 'Ask',
            newChat: 'New Chat',
            newSession: 'New Session',
            clearHistory: 'Clear History',
            clearChat: 'Clear Conversation',
            delete: 'Delete',
            cancel: 'Cancel',
            save: 'Save',
            copy: 'Copy',
            copied: 'Copied!',
            export: 'Export',
            download: 'Download',
            share: 'Share',
            search: 'Search',
            settings: 'Settings',
            help: 'Help',
            close: 'Close',
            backToMain: 'Main Gallery',
            theme: 'Theme',
            voiceDictation: 'Voice Dictation',
            runCode: 'Run Code',
            saveSkill: 'Save as Skill',

            // Placeholders
            typeMessage: 'Type a message or ask Gemma… (Enter to send)',
            askAnything: 'Ask anything to Gemma… (⌘Enter to send)',
            searchPlaceholder: 'Search or type > command… (⌘K)',
            sessionNamePrompt: 'Enter a name for this session:',

            // Badges & Status
            statusReady: 'Gemma Ready',
            statusThinking: 'Thinking…',
            statusProcessing: 'Processing…',
            statusConnecting: 'Connecting…',
            inProcessMetal: '⚡ In-Process Native Metal (Zero Python)',
            localGemma: '⚡ Local Gemma 4',
            copiedClipboard: '✓ Copied to clipboard',

            // Features & Sections
            knowledgeBase: 'Knowledge Base',
            hybridRag: 'Hybrid Search (BM25 + Dense RRF)',
            parameters: 'Parameters',
            canvas: 'Canvas / Artifact',
            inspector: 'Inspector',
            history: 'History',
            modelHub: 'Model Hub',
            quickAsk: 'Quick Ask',
            commandPalette: 'Command Palette',

            // Labels
            fontSize: 'Font Size',
            temperature: 'Temperature',
            topP: 'Top P',
            maxTokens: 'Max Tokens',
            speed: 'Speed',
            tokensPerSec: 'tok/s',
            firstToken: 'First Token',
            memoryUsage: 'Memory',
            lanAccess: 'LAN Access',
            scanQr: 'Scan QR Code to connect from smartphone or laptop'
        },
        id: {
            langName: 'Bahasa Indonesia',
            code: 'id',
            locale: 'id-ID',
            // Actions & Navigation
            send: 'Kirim',
            sendShortcut: 'Kirim ↵',
            ask: 'Tanya',
            newChat: 'Obrolan Baru',
            newSession: 'Sesi Baru',
            clearHistory: 'Hapus Riwayat',
            clearChat: 'Hapus Percakapan',
            delete: 'Hapus',
            cancel: 'Batal',
            save: 'Simpan',
            copy: 'Salin',
            copied: 'Tersalin!',
            export: 'Ekspor',
            download: 'Unduh',
            share: 'Bagikan',
            search: 'Cari',
            settings: 'Pengaturan',
            help: 'Bantuan',
            close: 'Tutup',
            backToMain: 'Galeri Utama',
            theme: 'Tema',
            voiceDictation: 'Dikte Suara',
            runCode: 'Jalankan Kode',
            saveSkill: 'Jadikan Skill',

            // Placeholders
            typeMessage: 'Ketik pesan atau tanyakan ke Gemma… (Enter)',
            askAnything: 'Tanyakan apa saja ke Gemma… (⌘Enter)',
            searchPlaceholder: 'Cari atau ketik > perintah… (⌘K)',
            sessionNamePrompt: 'Masukkan nama untuk sesi ini:',

            // Badges & Status
            statusReady: 'Gemma Siap',
            statusThinking: 'Sedang berpikir…',
            statusProcessing: 'Memproses…',
            statusConnecting: 'Menghubungkan…',
            inProcessMetal: '⚡ In-Process Native Metal (Zero Python)',
            localGemma: '⚡ Gemma 4 Lokal',
            copiedClipboard: '✓ Disalin ke papan klip',

            // Features & Sections
            knowledgeBase: 'Basis Pengetahuan',
            hybridRag: 'Pencarian Hibrida (BM25 + Dense RRF)',
            parameters: 'Parameter',
            canvas: 'Kanvas / Artefak',
            inspector: 'Inspektur',
            history: 'Riwayat',
            modelHub: 'Pusat Model',
            quickAsk: 'Tanya Cepat',
            commandPalette: 'Palet Perintah',

            // Labels
            fontSize: 'Ukuran Teks',
            temperature: 'Suhu (Temperature)',
            topP: 'Top P',
            maxTokens: 'Maks Token',
            speed: 'Kecepatan',
            tokensPerSec: 'tok/dtk',
            firstToken: 'Token Pertama',
            memoryUsage: 'Memori',
            lanAccess: 'Akses Jaringan LAN',
            scanQr: 'Pindai QR Code untuk terhubung dari ponsel atau laptop'
        }
    };

    // Peta sinonim untuk penerjemahan teks elemen statis yang sudah ada di HTML
    const TEXT_TRANSLATION_MAP = [
        { id: 'Kirim', en: 'Send' },
        { id: 'Kirim ↵', en: 'Send ↵' },
        { id: 'Kirim Pesan', en: 'Send Message' },
        { id: 'Tanya', en: 'Ask' },
        { id: 'Obrolan Baru', en: 'New Chat' },
        { id: 'Sesi Baru', en: 'New Session' },
        { id: 'Hapus Riwayat', en: 'Clear History' },
        { id: 'Hapus Percakapan', en: 'Clear Chat' },
        { id: 'Hapus Sesi', en: 'Delete Session' },
        { id: 'Salin', en: 'Copy' },
        { id: 'Salin Kode', en: 'Copy Code' },
        { id: 'Tersalin!', en: 'Copied!' },
        { id: 'Ekspor', en: 'Export' },
        { id: 'Unduh', en: 'Download' },
        { id: 'Pengaturan', en: 'Settings' },
        { id: 'Basis Pengetahuan', en: 'Knowledge Base' },
        { id: 'Parameter', en: 'Parameters' },
        { id: 'Riwayat Sesi', en: 'Session History' },
        { id: 'Galeri Utama', en: 'Main Gallery' },
        { id: 'Kembali ke Galeri', en: 'Back to Gallery' },
        { id: 'Jalankan Kode', en: 'Run Code' },
        { id: 'Sedang berpikir...', en: 'Thinking...' },
        { id: 'Sedang berpikir…', en: 'Thinking…' },
        { id: 'Gemma Siap', en: 'Gemma Ready' },
        { id: 'Gunakan Teks Clipboard', en: 'Use Clipboard Text' },
        { id: 'Jadikan Skill', en: 'Save as Skill' },
        { id: 'Buka di Ruang Kerja →', en: 'Open in Workspace →' },
        { id: 'Tanya Cepat AI', en: 'Quick Ask AI' },
        { id: 'Dikte Suara', en: 'Voice Dictation' }
    ];

    const PLACEHOLDER_MAP = [
        { id: 'Ketik pesan atau tanyakan sesuatu...', en: 'Type a message or ask anything...' },
        { id: 'Ketik pesan atau tanyakan ke Gemma...', en: 'Type a message or ask Gemma...' },
        { id: 'Tanyakan apa saja ke Gemma...', en: 'Ask anything to Gemma...' },
        { id: 'Tanyakan sesuatu...', en: 'Ask anything...' },
        { id: 'Ketik pertanyaan atau `> perintah`… (Tekan Enter)', en: 'Type a question or `> command`… (Press Enter)' },
        { id: 'Cari riwayat percakapan...', en: 'Search conversation history...' },
        { id: 'Cari di seluruh percakapan...', en: 'Search across conversations...' },
        { id: 'Cari sesi...', en: 'Search sessions...' }
    ];

    class EduVisI18nEngine {
        constructor() {
            this.currentLang = this.detectLanguage();
            this.init();
        }

        detectLanguage() {
            try {
                const stored = localStorage.getItem(STORAGE_KEY);
                if (stored === 'en' || stored === 'id') {
                    return stored;
                }
            } catch (_) {}

            // Deteksi dari sistem operasi / browser
            const sysLang = (navigator.languages && navigator.languages[0]) || navigator.language || 'en';
            return sysLang.toLowerCase().startsWith('id') ? 'id' : 'en';
        }

        getLanguage() {
            return this.currentLang;
        }

        getLocale() {
            return DICTIONARY[this.currentLang]?.locale || 'en-US';
        }

        t(key) {
            return DICTIONARY[this.currentLang]?.[key] || DICTIONARY['en']?.[key] || key;
        }

        setLanguage(lang) {
            if (lang !== 'en' && lang !== 'id') return;
            this.currentLang = lang;
            try {
                localStorage.setItem(STORAGE_KEY, lang);
            } catch (_) {}

            document.documentElement.lang = lang;
            window.eduvisActiveLocale = this.getLocale();

            this.translatePage();
            this.updateSwitcherPill();

            window.dispatchEvent(new CustomEvent('eduvis:language-changed', {
                detail: { language: lang, locale: this.getLocale() }
            }));
        }

        toggleLanguage() {
            const nextLang = this.currentLang === 'id' ? 'en' : 'id';
            this.setLanguage(nextLang);
        }

        translatePage() {
            const isEn = this.currentLang === 'en';

            // 1. Ganti teks elemen langsung
            TEXT_TRANSLATION_MAP.forEach(item => {
                const targetText = isEn ? item.id : item.en;
                const replacementText = isEn ? item.en : item.id;

                // Cari tombol atau span dengan teks persis
                const walker = document.createTreeWalker(
                    document.body || document.documentElement,
                    NodeFilter.SHOW_TEXT,
                    null,
                    false
                );

                let node;
                while (node = walker.nextNode()) {
                    const text = node.nodeValue.trim();
                    if (text === targetText) {
                        node.nodeValue = node.nodeValue.replace(targetText, replacementText);
                    }
                }
            });

            // 2. Ganti placeholder input & textarea
            PLACEHOLDER_MAP.forEach(item => {
                const targetPlaceholder = isEn ? item.id : item.en;
                const replacementPlaceholder = isEn ? item.en : item.id;

                const inputs = document.querySelectorAll(`input[placeholder="${targetPlaceholder}"], textarea[placeholder="${targetPlaceholder}"]`);
                inputs.forEach(el => {
                    el.placeholder = replacementPlaceholder;
                });
            });

            // 3. Elemen dengan atribut data-i18n
            document.querySelectorAll('[data-i18n]').forEach(el => {
                const key = el.getAttribute('data-i18n');
                if (key && DICTIONARY[this.currentLang]?.[key]) {
                    el.textContent = DICTIONARY[this.currentLang][key];
                }
            });

            // 4. Update data-i18n-placeholder
            document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
                const key = el.getAttribute('data-i18n-placeholder');
                if (key && DICTIONARY[this.currentLang]?.[key]) {
                    el.placeholder = DICTIONARY[this.currentLang][key];
                }
            });
        }

        initSwitcherPill() {
            if (document.getElementById('eduvis-lang-switcher-pill')) return;

            const pill = document.createElement('button');
            pill.id = 'eduvis-lang-switcher-pill';
            pill.type = 'button';
            pill.title = 'Switch Language / Ganti Bahasa (EN / ID)';
            pill.setAttribute('aria-label', 'Switch Language');

            pill.style.cssText = `
                position: fixed;
                top: 14px;
                right: 92px;
                z-index: 99999;
                display: inline-flex;
                align-items: center;
                gap: 5px;
                padding: 4px 10px;
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
                font-size: 11.5px;
                font-weight: 600;
                color: var(--pill-color, rgba(255, 255, 255, 0.92));
                background: rgba(30, 30, 36, 0.65);
                backdrop-filter: blur(20px) saturate(180%);
                -webkit-backdrop-filter: blur(20px) saturate(180%);
                border: 1px solid rgba(255, 255, 255, 0.16);
                border-radius: 9999px;
                box-shadow: 0 4px 16px rgba(0, 0, 0, 0.25), inset 0 1px 0 rgba(255, 255, 255, 0.15);
                cursor: pointer;
                user-select: none;
                transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
            `;

            pill.onmouseenter = () => {
                pill.style.transform = 'translateY(-1px) scale(1.03)';
                pill.style.background = 'rgba(45, 45, 55, 0.85)';
                pill.style.borderColor = 'rgba(255, 255, 255, 0.3)';
            };
            pill.onmouseleave = () => {
                pill.style.transform = 'none';
                pill.style.background = 'rgba(30, 30, 36, 0.65)';
                pill.style.borderColor = 'rgba(255, 255, 255, 0.16)';
            };

            pill.onclick = (e) => {
                e.preventDefault();
                e.stopPropagation();
                this.toggleLanguage();
            };

            const container = document.body || document.documentElement;
            container.appendChild(pill);
            this.updateSwitcherPill();
        }

        updateSwitcherPill() {
            const pill = document.getElementById('eduvis-lang-switcher-pill');
            if (!pill) return;

            const isEn = this.currentLang === 'en';
            pill.innerHTML = `
                <span style="font-size: 12px;">🌐</span>
                <span style="letter-spacing: 0.5px;">${isEn ? 'EN' : 'ID'}</span>
                <span style="opacity: 0.45; font-size: 10px; margin-left: -1px;">▾</span>
            `;
        }

        setupObserver() {
            // Pantau elemen dinamis (seperti modal dan pesan chat baru)
            const observer = new MutationObserver((mutations) => {
                let shouldTranslate = false;
                for (const m of mutations) {
                    if (m.addedNodes.length > 0) {
                        shouldTranslate = true;
                        break;
                    }
                }
                if (shouldTranslate && this.currentLang === 'en') {
                    this.translatePage();
                }
            });

            if (document.body) {
                observer.observe(document.body, { childList: true, subtree: true });
            }
        }

        init() {
            window.eduvisActiveLocale = this.getLocale();
            document.documentElement.lang = this.currentLang;

            const onReady = () => {
                this.initSwitcherPill();
                this.translatePage();
                this.setupObserver();
            };

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', onReady);
            } else {
                onReady();
            }
        }
    }

    const engine = new EduVisI18nEngine();
    window.EduVisi18n = engine;

    // Helper global untuk modul lain
    window.__t = (key) => engine.t(key);
})();
