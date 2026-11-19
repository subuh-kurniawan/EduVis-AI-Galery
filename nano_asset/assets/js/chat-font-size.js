/**
 * Global Real-Time Chat Font Size Manager
 * Memungkinkan pengubahan ukuran font/teks percakapan AI secara realtime
 * di seluruh workspace UI (Utama, Claude, VS, Aurora, Liquid Chatbot, Tanya AI, dll)
 * dengan sinkronisasi instan antar-tab/jendela via BroadcastChannel & localStorage.
 */
(() => {
    "use strict";

    if (window.__ChatFontSizeInitialized) return;
    window.__ChatFontSizeInitialized = true;

    const STORAGE_KEY = 'gemma_chat_font_size';
    const WIDGET_MINIMIZED_KEY = 'gemma_chat_font_size_minimized';
    const CHANNEL_NAME = 'gemma_chat_font_size_channel';
    const DEFAULT_SIZE = 15;
    const MIN_SIZE = 11;
    const MAX_SIZE = 32;

    const PRESETS = [
        { id: 'xs', label: 'Ekstra Kecil (12px)', size: 12 },
        { id: 'sm', label: 'Kecil (13.5px)', size: 13.5 },
        { id: 'md', label: 'Standar (15px)', size: 15 },
        { id: 'lg', label: 'Besar (17px)', size: 17 },
        { id: 'xl', label: 'Ekstra Besar (19.5px)', size: 19.5 },
        { id: '2xl', label: 'Maksimal (22.5px)', size: 22.5 }
    ];

    let currentSize = DEFAULT_SIZE;
    let broadcastChannel = null;

    try {
        if ('BroadcastChannel' in window) {
            broadcastChannel = new BroadcastChannel(CHANNEL_NAME);
        }
    } catch (e) {
        // BroadcastChannel unavailable (restricted iframe/sandbox)
    }

    /**
     * Membaca ukuran font tersimpan dari localStorage
     */
    function loadSavedSize() {
        try {
            const saved = localStorage.getItem(STORAGE_KEY);
            if (saved) {
                const parsed = parseFloat(saved);
                if (!isNaN(parsed) && parsed >= MIN_SIZE && parsed <= MAX_SIZE) {
                    return parsed;
                }
            }
        } catch (e) {}
        return DEFAULT_SIZE;
    }

    /**
     * Parsing nilai fleksibel: angka (16), string ('16px', '1.1rem', '+1', '-1', 'lg', 'larger')
     */
    function parseSizeInput(val, baseSize) {
        if (typeof val === 'number') {
            return val;
        }

        if (typeof val !== 'string') {
            return baseSize;
        }

        const trimmed = val.trim().toLowerCase();

        // Relative steps
        if (trimmed === '+' || trimmed === '+1' || trimmed === 'larger' || trimmed === 'perbesar') {
            return baseSize + 1;
        }
        if (trimmed === '-' || trimmed === '-1' || trimmed === 'smaller' || trimmed === 'perkecil') {
            return baseSize - 1;
        }
        if (trimmed.startsWith('+')) {
            const delta = parseFloat(trimmed.slice(1));
            return isNaN(delta) ? baseSize + 1 : baseSize + delta;
        }
        if (trimmed.startsWith('-')) {
            const delta = parseFloat(trimmed.slice(1));
            return isNaN(delta) ? baseSize - 1 : baseSize - delta;
        }

        // Check presets
        const preset = PRESETS.find(p => p.id === trimmed);
        if (preset) {
            return preset.size;
        }

        // Rem/em conversion (relative to 16px standard)
        if (trimmed.endsWith('rem') || trimmed.endsWith('em')) {
            const num = parseFloat(trimmed);
            return isNaN(num) ? baseSize : num * 16;
        }

        // Percentage conversion
        if (trimmed.endsWith('%')) {
            const pct = parseFloat(trimmed);
            return isNaN(pct) ? baseSize : (pct / 100) * DEFAULT_SIZE;
        }

        // Standard px or plain number string
        const parsed = parseFloat(trimmed);
        return isNaN(parsed) ? baseSize : parsed;
    }

    /**
     * Memperbarui / menginjeksikan aturan CSS spesifik dengan !important
     */
    function updateDynamicStyles(size) {
        const styleId = 'chat-font-size-dynamic-override';
        let styleEl = document.getElementById(styleId);
        if (!styleEl) {
            styleEl = document.createElement('style');
            styleEl.id = styleId;
            document.head.appendChild(styleEl);
        }

        const codeSize = (size * 0.9).toFixed(1);
        const h1Size = (size * 1.5).toFixed(1);
        const h2Size = (size * 1.3).toFixed(1);
        const h3Size = (size * 1.15).toFixed(1);
        const h4Size = (size * 1.05).toFixed(1);
        const tableSize = (size * 0.93).toFixed(1);

        styleEl.textContent = `
            :root {
                --chat-font-size: ${size}px !important;
                --chat-font-size-code: ${codeSize}px !important;
                --chat-font-size-h1: ${h1Size}px !important;
                --chat-font-size-h2: ${h2Size}px !important;
                --chat-font-size-h3: ${h3Size}px !important;
                --chat-font-size-h4: ${h4Size}px !important;
                --chat-line-height: 1.62 !important;
            }

            /* Override selector chat bubbles secara universal (termasuk mode macOS Native) */
            html.macos-native #messages .prose,
            html.macos-native .chat-bubble-ai,
            html.macos-native .chat-bubble-ai .prose,
            html.macos-native .chat-bubble-user,
            html.macos-native .claude-user-bubble,
            html.macos-native #messages .v2-chat-reply,
            html.macos-native #messages .v2-chat-user,
            .chat-bubble-user,
            .chat-bubble-ai,
            .message-bubble,
            .v2-chat-reply,
            .bubble,
            .bubble-ai,
            .bubble-user,
            .timeline-item,
            .msg .bubble,
            .msg .prose,
            #messages .chat-bubble-user,
            #messages .chat-bubble-ai,
            #messages .prose,
            #messages .chat-bubble-user > div,
            #messages .chat-bubble-ai > div,
            #chatArea .message-bubble,
            #chatArea .prose,
            #conversation .bubble,
            #ragChatTimeline .bubble,
            .timeline-item .prose,
            .chat-row .prose,
            .ai-response-stream-container,
            [data-chat-bubble],
            [data-chat-message] {
                font-size: ${size}px !important;
                line-height: 1.62 !important;
            }

            html.macos-native #messages .prose p,
            html.macos-native #messages .prose li,
            html.macos-native .chat-bubble-ai p,
            html.macos-native .chat-bubble-ai li,
            html.macos-native .chat-bubble-user p,
            html.macos-native .chat-bubble-user li,
            html.macos-native .claude-user-bubble p,
            html.macos-native .claude-user-bubble li,
            .chat-bubble-user p,
            .chat-bubble-ai p,
            .message-bubble p,
            .v2-chat-reply p,
            .bubble p,
            .timeline-item p,
            .msg p,
            #messages .prose p,
            #chatArea .prose p,
            #conversation .bubble p,
            #ragChatTimeline .bubble p,
            .chat-bubble-user li,
            .chat-bubble-ai li,
            .message-bubble li,
            .v2-chat-reply li,
            .bubble li,
            .timeline-item li,
            .msg li,
            #messages .prose li,
            #chatArea .prose li,
            #conversation .bubble li,
            .chat-bubble-user span:not(.bx):not([class*="icon"]),
            .chat-bubble-ai span:not(.bx):not([class*="icon"]),
            .bubble span:not(.bx):not([class*="icon"]) {
                font-size: ${size}px !important;
                line-height: 1.62 !important;
            }

            html.macos-native #messages pre,
            html.macos-native #messages code,
            .chat-bubble-user pre,
            .chat-bubble-ai pre,
            .message-bubble pre,
            .v2-chat-reply pre,
            .bubble pre,
            .timeline-item pre,
            .msg pre,
            #messages pre,
            #chatArea pre,
            #conversation .bubble pre,
            .chat-bubble-user code,
            .chat-bubble-ai code,
            .message-bubble code,
            .v2-chat-reply code,
            .bubble code,
            .timeline-item code,
            .msg code,
            #messages code,
            #chatArea code,
            #conversation .bubble code {
                font-size: ${codeSize}px !important;
            }

            html.macos-native #messages .prose h1, .chat-bubble-ai h1, .message-bubble h1, .bubble h1, #messages .prose h1, #chatArea .prose h1 { font-size: ${h1Size}px !important; }
            html.macos-native #messages .prose h2, .chat-bubble-ai h2, .message-bubble h2, .bubble h2, #messages .prose h2, #chatArea .prose h2 { font-size: ${h2Size}px !important; }
            html.macos-native #messages .prose h3, .chat-bubble-ai h3, .message-bubble h3, .bubble h3, #messages .prose h3, #chatArea .prose h3 { font-size: ${h3Size}px !important; }
            html.macos-native #messages .prose h4, .chat-bubble-ai h4, .message-bubble h4, .bubble h4, #messages .prose h4, #chatArea .prose h4 { font-size: ${h4Size}px !important; }

            html.macos-native #messages table,
            .chat-bubble-ai table,
            .message-bubble table,
            .bubble table,
            .timeline-item table,
            #messages table,
            #chatArea table {
                font-size: ${tableSize}px !important;
            }

            html.macos-native #messages .katex,
            html.macos-native #messages .katex-display,
            .chat-bubble-ai .katex,
            .chat-bubble-ai .katex-display,
            .message-bubble .katex,
            .bubble .katex,
            #messages .katex,
            #messages .katex-display {
                font-size: ${(size * 1.05).toFixed(1)}px !important;
            }
        `;
    }

    /**
     * Terapkan ukuran font baru ke dokumen, storage, dan UI
     */
    function applyFontSize(newSize, broadcast = true) {
        const rawSize = parseSizeInput(newSize, currentSize);
        const clampedSize = Math.max(MIN_SIZE, Math.min(MAX_SIZE, Math.round(rawSize * 10) / 10));

        const previousSize = currentSize;
        currentSize = clampedSize;

        // 1. Terapkan CSS Variable ke root
        document.documentElement.style.setProperty('--chat-font-size', `${currentSize}px`);
        document.documentElement.style.setProperty('--chat-code-font-size', `${(currentSize * 0.9).toFixed(1)}px`);
        document.documentElement.setAttribute('data-chat-font-size', `${currentSize}px`);

        // 2. Terapkan dynamic style override
        updateDynamicStyles(currentSize);

        // 3. Simpan ke LocalStorage
        try {
            localStorage.setItem(STORAGE_KEY, String(currentSize));
        } catch (e) {}

        // 4. Siarkan perubahan ke tab/jendela lain
        if (broadcast) {
            if (broadcastChannel) {
                try {
                    broadcastChannel.postMessage({ type: 'CHANGE_FONT_SIZE', size: currentSize });
                } catch (e) {}
            }
        }

        // 5. Emit custom event pada window & document
        const evtDetail = {
            size: currentSize,
            sizePx: `${currentSize}px`,
            previousSize: previousSize
        };
        window.dispatchEvent(new CustomEvent('chat-font-size-change', { detail: evtDetail }));
        document.dispatchEvent(new CustomEvent('chat-font-size-change', { detail: evtDetail }));

        // 6. Sinkronkan tampilan Floating Widget jika aktif
        updateWidgetUI(currentSize);

        return currentSize;
    }

    // ==========================================
    // FLOATING QUICK CONTROL WIDGET (UI)
    // ==========================================
    let widgetContainer = null;

    function createFloatingWidget() {
        if (document.getElementById('gemma-chat-font-widget')) return;

        widgetContainer = document.createElement('div');
        widgetContainer.id = 'gemma-chat-font-widget';
        widgetContainer.className = 'gemma-font-widget';

        let isMinimized = false;
        try {
            localStorage.removeItem(WIDGET_MINIMIZED_KEY);
        } catch (e) {}

        widgetContainer.innerHTML = `
            <div class="gfc-pill" id="gfc-pill">
                <button class="gfc-btn gfc-toggle" id="gfc-toggle" type="button" title="Pengatur Ukuran Teks Chat (Klik untuk ciutkan/lebarkan)" aria-label="Toggle ukuran teks">
                    <span class="gfc-icon">Aa</span>
                </button>
                <div class="gfc-controls" id="gfc-controls">
                    <button class="gfc-btn gfc-dec" id="gfc-dec" type="button" title="Perkecil Teks (Cmd/Ctrl + Shift + -)" aria-label="Perkecil teks">
                        <svg viewBox="0 0 24 24" width="14" height="14" stroke="currentColor" stroke-width="2.5" fill="none"><line x1="5" y1="12" x2="19" y2="12"></line></svg>
                    </button>
                    <button class="gfc-value" id="gfc-value" type="button" title="Pilih Preset Ukuran (Klik untuk daftar preset)">
                        <span id="gfc-text">${currentSize}px</span>
                    </button>
                    <button class="gfc-btn gfc-inc" id="gfc-inc" type="button" title="Perbesar Teks (Cmd/Ctrl + Shift + +)" aria-label="Perbesar teks">
                        <svg viewBox="0 0 24 24" width="14" height="14" stroke="currentColor" stroke-width="2.5" fill="none"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>
                    </button>
                    <button class="gfc-btn gfc-reset" id="gfc-reset" type="button" title="Reset ke Standar (15px)" aria-label="Reset ukuran font">
                        <svg viewBox="0 0 24 24" width="12" height="12" stroke="currentColor" stroke-width="2.5" fill="none"><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"></path><path d="M3 3v5h5"></path></svg>
                    </button>
                </div>
                <div class="gfc-presets-menu" id="gfc-presets-menu">
                    <div class="gfc-preset-title">Ukuran Teks Chat</div>
                    ${PRESETS.map(p => `
                        <button class="gfc-preset-item ${Math.abs(p.size - currentSize) < 0.2 ? 'active' : ''}" data-size="${p.size}" type="button">
                            <span>${p.label}</span>
                            <span class="gfc-preset-badge">${p.size}px</span>
                        </button>
                    `).join('')}
                </div>
            </div>
            <style>
                .gemma-font-widget {
                    position: fixed;
                    left: var(--chat-font-widget-left, 18px);
                    bottom: var(--chat-font-widget-bottom, calc(18px + env(safe-area-inset-bottom, 0px)));
                    z-index: 9999;
                    pointer-events: auto;
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif;
                    user-select: none;
                    -webkit-user-select: none;
                }
                html.macos-native .gemma-font-widget {
                    left: var(--chat-font-widget-left, 18px);
                    bottom: var(--chat-font-widget-bottom, 18px);
                    z-index: 9999;
                    pointer-events: auto;
                }
                .gfc-pill {
                    position: relative;
                    display: inline-flex;
                    align-items: center;
                    gap: 3px;
                    padding: 3px 6px;
                    border-radius: 9999px;
                    background: rgba(15, 23, 42, 0.84);
                    border: 1px solid rgba(255, 255, 255, 0.22);
                    backdrop-filter: blur(24px) saturate(200%);
                    -webkit-backdrop-filter: blur(24px) saturate(200%);
                    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.28), 0 10px 30px rgba(0, 0, 0, 0.42);
                    transition: all 0.22s cubic-bezier(0.16, 1, 0.3, 1);
                }
                body.light-theme .gfc-pill,
                html.light .gfc-pill {
                    background: rgba(255, 255, 255, 0.88);
                    border-color: rgba(0, 0, 0, 0.12);
                    box-shadow: 0 8px 24px rgba(15, 23, 42, 0.15);
                }
                .gfc-controls {
                    display: flex;
                    align-items: center;
                    gap: 2px;
                    transition: opacity 0.2s ease, transform 0.2s ease;
                }
                .gfc-pill.gfc-minimized .gfc-controls {
                    display: none;
                }
                .gfc-btn {
                    display: grid;
                    place-items: center;
                    width: 26px;
                    height: 26px;
                    padding: 0;
                    border: none;
                    background: transparent;
                    color: #cbd5e1;
                    border-radius: 9999px;
                    cursor: pointer;
                    transition: background 0.15s ease, color 0.15s ease, transform 0.1s ease;
                }
                body.light-theme .gfc-btn,
                html.light .gfc-btn {
                    color: #475569;
                }
                .gfc-btn:hover {
                    background: rgba(255, 255, 255, 0.12);
                    color: #38bdf8;
                }
                body.light-theme .gfc-btn:hover,
                html.light .gfc-btn:hover {
                    background: rgba(0, 0, 0, 0.08);
                    color: #0284c7;
                }
                .gfc-btn:active {
                    transform: scale(0.92);
                }
                .gfc-toggle {
                    width: 28px;
                    height: 28px;
                    font-size: 11px;
                    font-weight: 700;
                    letter-spacing: -0.5px;
                    color: #38bdf8;
                    background: rgba(56, 189, 248, 0.12);
                }
                .gfc-value {
                    display: inline-flex;
                    align-items: center;
                    justify-content: center;
                    min-width: 44px;
                    height: 24px;
                    padding: 0 7px;
                    border: 1px solid rgba(255, 255, 255, 0.08);
                    border-radius: 9999px;
                    background: rgba(0, 0, 0, 0.25);
                    color: #f1f5f9;
                    font-size: 11.5px;
                    font-weight: 600;
                    font-variant-numeric: tabular-nums;
                    cursor: pointer;
                    transition: background 0.15s ease;
                }
                body.light-theme .gfc-value,
                html.light .gfc-value {
                    background: rgba(0, 0, 0, 0.05);
                    border-color: rgba(0, 0, 0, 0.08);
                    color: #0f172a;
                }
                .gfc-value:hover {
                    background: rgba(56, 189, 248, 0.2);
                    color: #38bdf8;
                }
                /* Menu Preset */
                .gfc-presets-menu {
                    position: absolute;
                    bottom: calc(100% + 8px);
                    left: 0;
                    width: 210px;
                    padding: 6px;
                    border-radius: 14px;
                    background: rgba(15, 23, 42, 0.94);
                    border: 1px solid rgba(255, 255, 255, 0.14);
                    backdrop-filter: blur(24px);
                    -webkit-backdrop-filter: blur(24px);
                    box-shadow: 0 16px 36px rgba(0, 0, 0, 0.45);
                    display: none;
                    flex-direction: column;
                    gap: 3px;
                    z-index: 50;
                }
                body.light-theme .gfc-presets-menu,
                html.light .gfc-presets-menu {
                    background: rgba(255, 255, 255, 0.96);
                    border-color: rgba(0, 0, 0, 0.12);
                    box-shadow: 0 12px 30px rgba(15, 23, 42, 0.18);
                }
                .gfc-presets-menu.open {
                    display: flex;
                    animation: gfcFadeIn 0.16s ease-out;
                }
                @keyframes gfcFadeIn {
                    from { opacity: 0; transform: translateY(6px); }
                    to { opacity: 1; transform: translateY(0); }
                }
                .gfc-preset-title {
                    padding: 4px 8px 6px;
                    font-size: 10.5px;
                    font-weight: 700;
                    text-transform: uppercase;
                    letter-spacing: 0.06em;
                    color: #94a3b8;
                    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
                    margin-bottom: 2px;
                }
                body.light-theme .gfc-preset-title,
                html.light .gfc-preset-title {
                    color: #64748b;
                    border-bottom-color: rgba(0, 0, 0, 0.08);
                }
                .gfc-preset-item {
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    padding: 6px 8px;
                    border: none;
                    background: transparent;
                    color: #e2e8f0;
                    font-size: 12px;
                    border-radius: 8px;
                    cursor: pointer;
                    text-align: left;
                    transition: background 0.12s ease;
                }
                body.light-theme .gfc-preset-item,
                html.light .gfc-preset-item {
                    color: #1e293b;
                }
                .gfc-preset-item:hover {
                    background: rgba(255, 255, 255, 0.1);
                    color: #38bdf8;
                }
                body.light-theme .gfc-preset-item:hover,
                html.light .gfc-preset-item:hover {
                    background: rgba(0, 0, 0, 0.06);
                    color: #0284c7;
                }
                .gfc-preset-item.active {
                    background: rgba(56, 189, 248, 0.18);
                    color: #38bdf8;
                    font-weight: 600;
                }
                .gfc-preset-badge {
                    font-size: 10.5px;
                    font-weight: 600;
                    padding: 1px 5px;
                    border-radius: 4px;
                    background: rgba(255, 255, 255, 0.08);
                    color: #94a3b8;
                }
                body.light-theme .gfc-preset-badge,
                html.light .gfc-preset-badge {
                    background: rgba(0, 0, 0, 0.06);
                    color: #64748b;
                }
                @media (max-width: 640px) {
                    .gemma-font-widget {
                        left: 0.5rem;
                        bottom: calc(0.6rem + env(safe-area-inset-bottom, 0px));
                    }
                }
            </style>
        `;

        document.body.appendChild(widgetContainer);

        const pill = document.getElementById('gfc-pill');
        const toggleBtn = document.getElementById('gfc-toggle');
        const decBtn = document.getElementById('gfc-dec');
        const incBtn = document.getElementById('gfc-inc');
        const resetBtn = document.getElementById('gfc-reset');
        const valueBtn = document.getElementById('gfc-value');
        const presetsMenu = document.getElementById('gfc-presets-menu');

        if (!pill || !toggleBtn) return;

        toggleBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            const minimized = pill.classList.toggle('gfc-minimized');
            if (minimized) presetsMenu.classList.remove('open');
            try {
                localStorage.setItem(WIDGET_MINIMIZED_KEY, minimized ? '1' : '0');
            } catch (err) {}
        });

        decBtn.addEventListener('click', () => {
            applyFontSize(currentSize - 1);
        });

        incBtn.addEventListener('click', () => {
            applyFontSize(currentSize + 1);
        });

        resetBtn.addEventListener('click', () => {
            applyFontSize(DEFAULT_SIZE);
        });

        valueBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            presetsMenu.classList.toggle('open');
        });

        presetsMenu.querySelectorAll('.gfc-preset-item').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const sz = parseFloat(btn.dataset.size);
                if (!isNaN(sz)) applyFontSize(sz);
                presetsMenu.classList.remove('open');
            });
        });

        document.addEventListener('click', (e) => {
            if (!widgetContainer.contains(e.target)) {
                presetsMenu.classList.remove('open');
            }
        });
    }

    /**
     * Update tampilan nilai pada widget
     */
    function updateWidgetUI(size) {
        const textEl = document.getElementById('gfc-text');
        if (textEl) textEl.textContent = `${size}px`;

        const menu = document.getElementById('gfc-presets-menu');
        if (menu) {
            menu.querySelectorAll('.gfc-preset-item').forEach(item => {
                const sz = parseFloat(item.dataset.size);
                if (Math.abs(sz - size) < 0.2) {
                    item.classList.add('active');
                } else {
                    item.classList.remove('active');
                }
            });
        }
    }

    // ==========================================
    // KEYBOARD SHORTCUTS
    // ==========================================
    function setupKeyboardShortcuts() {
        window.addEventListener('keydown', (e) => {
            // Hindari trigger saat fokus pada text input biasa kecuali ditekan kombinasi Cmd/Ctrl + Shift
            const isEditing = e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.isContentEditable);

            const hasModifier = (e.metaKey || e.ctrlKey) && e.shiftKey;

            if (hasModifier) {
                if (e.key === '=' || e.key === '+') {
                    e.preventDefault();
                    applyFontSize(currentSize + 1);
                } else if (e.key === '-' || e.key === '_') {
                    e.preventDefault();
                    applyFontSize(currentSize - 1);
                } else if (e.key === '0' || e.key === ')') {
                    e.preventDefault();
                    applyFontSize(DEFAULT_SIZE);
                }
            } else if (e.altKey && !isEditing) {
                if (e.key === ']' || e.key === '}') {
                    e.preventDefault();
                    applyFontSize(currentSize + 1);
                } else if (e.key === '[' || e.key === '{') {
                    e.preventDefault();
                    applyFontSize(currentSize - 1);
                }
            }
        });
    }

    // ==========================================
    // SINKRONISASI REAL-TIME (STORAGE & CHANNEL)
    // ==========================================
    function setupSynchronization() {
        // 1. Dengarkan BroadcastChannel dari tab/window lain
        if (broadcastChannel) {
            broadcastChannel.onmessage = (event) => {
                if (event.data && event.data.type === 'CHANGE_FONT_SIZE') {
                    const newSize = parseFloat(event.data.size);
                    if (!isNaN(newSize) && newSize !== currentSize) {
                        applyFontSize(newSize, false); // false = jangan loop broadcast balik
                    }
                }
            };
        }

        // 2. Dengarkan storage event untuk tab yang berbeda
        window.addEventListener('storage', (event) => {
            if (event.key === STORAGE_KEY && event.newValue) {
                const newSize = parseFloat(event.newValue);
                if (!isNaN(newSize) && newSize !== currentSize) {
                    applyFontSize(newSize, false);
                }
            }
        });
    }

    // ==========================================
    // GLOBAL API (WINDOW / EXPORTS)
    // ==========================================
    /**
     * Fungsi Global Utama
     * @param {number|string} size Nilai ukuran font (contoh: 16, '18px', '+1', '-1', 'lg', 'md')
     * @returns {number} Ukuran font saat ini dalam satuan px
     */
    function setChatFontSize(size) {
        return applyFontSize(size, true);
    }

    function getChatFontSize() {
        return currentSize;
    }

    function increaseChatFontSize(step = 1) {
        return applyFontSize(currentSize + (typeof step === 'number' ? step : 1), true);
    }

    function decreaseChatFontSize(step = 1) {
        return applyFontSize(currentSize - (typeof step === 'number' ? step : 1), true);
    }

    function resetChatFontSize() {
        return applyFontSize(DEFAULT_SIZE, true);
    }

    function expandChatFontSizeWidget() {
        createFloatingWidget();
        if (widgetContainer) widgetContainer.style.display = 'block';
        const pill = document.getElementById('gfc-pill');
        if (pill) pill.classList.remove('gfc-minimized');
        try {
            localStorage.removeItem(WIDGET_MINIMIZED_KEY);
        } catch (e) {}
        return true;
    }

    function toggleChatFontSizeWidget(visible) {
        if (!widgetContainer) {
            if (visible !== false) createFloatingWidget();
            return;
        }
        if (typeof visible === 'boolean') {
            widgetContainer.style.display = visible ? 'block' : 'none';
            if (visible) expandChatFontSizeWidget();
        } else {
            widgetContainer.style.display = widgetContainer.style.display === 'none' ? 'block' : 'none';
        }
    }

    // Expose ke globalThis / window
    window.setChatFontSize = setChatFontSize;
    window.getChatFontSize = getChatFontSize;
    window.increaseChatFontSize = increaseChatFontSize;
    window.decreaseChatFontSize = decreaseChatFontSize;
    window.resetChatFontSize = resetChatFontSize;
    window.toggleChatFontSizeWidget = toggleChatFontSizeWidget;
    window.expandChatFontSizeWidget = expandChatFontSizeWidget;

    // Aliases dalam bahasa Indonesia & variasi nama umum
    window.ubahUkuranTextChat = setChatFontSize;
    window.setChatTextSize = setChatFontSize;
    window.getChatTextSize = getChatFontSize;
    window.resetChatTextSize = resetChatFontSize;

    // Namespace Objek Terstruktur
    window.ChatFontSize = {
        set: setChatFontSize,
        get: getChatFontSize,
        increase: increaseChatFontSize,
        decrease: decreaseChatFontSize,
        reset: resetChatFontSize,
        toggleWidget: toggleChatFontSizeWidget,
        expand: expandChatFontSizeWidget,
        presets: PRESETS,
        DEFAULT: DEFAULT_SIZE,
        MIN: MIN_SIZE,
        MAX: MAX_SIZE
    };

    // ==========================================
    // INITIALIZATION
    // ==========================================
    const initialSize = loadSavedSize();
    applyFontSize(initialSize, false);
    setupSynchronization();
    setupKeyboardShortcuts();

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            createFloatingWidget();
        });
    } else {
        createFloatingWidget();
    }

})();
