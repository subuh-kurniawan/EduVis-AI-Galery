/**
 * artifact-sandbox.js - Gemma 4 Interactive Artifacts & Live Web Sandbox
 * Universal, on-device interactive sandbox ala Claude Artifacts & ChatGPT Canvas.
 * Supports:
 * - Live Preview in isolated iframe with automatic offline Tailwind CSS injection
 * - Interactive JS Console capture (log, info, warn, error) via postMessage bridge
 * - One-click "Fix with AI" error reporting loop directly to chat prompt
 * - Resizable side-dock + Fullscreen modal toggle + Viewport switcher (Desktop/Tablet/Mobile)
 * - Source code viewer and real-time live editor with "Apply & Run"
 * - Standalone HTML download
 * - 100% Offline, Zero external CDN dependencies
 */
(function (global) {
    'use strict';

    const STORAGE_KEY_WIDTH = 'gemma_artifact_dock_width';
    const DEFAULT_WIDTH = 680;
    const MIN_WIDTH = 380;

    let state = {
        isOpen: false,
        isMaximized: false,
        activeTab: 'preview', // 'preview' | 'code' | 'console'
        activeViewport: 'desktop', // 'desktop' | 'tablet' | 'mobile'
        currentCode: '',
        originalCode: '',
        title: 'Interactive Artifact',
        language: 'html',
        consoleLogs: [],
        lastError: null,
        dockWidth: DEFAULT_WIDTH,
        isDragging: false,
        dragStartX: 0,
        dragStartWidth: 0
    };

    // Load saved width
    try {
        if (typeof window !== 'undefined' && window.localStorage) {
            const savedWidth = parseInt(window.localStorage.getItem(STORAGE_KEY_WIDTH), 10);
            if (!isNaN(savedWidth) && savedWidth >= MIN_WIDTH) {
                state.dockWidth = Math.min(savedWidth, Math.floor(window.innerWidth * 0.9));
            }
        }
    } catch (e) {}

    /**
     * Escape HTML helper
     */
    function escapeHtml(str) {
        if (!str) return '';
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    /**
     * Inject CSS styles for Artifact Sandbox
     */
    function injectStyles() {
        if (document.getElementById('gemma-artifact-sandbox-styles')) return;
        const style = document.createElement('style');
        style.id = 'gemma-artifact-sandbox-styles';
        style.textContent = `
            #artifact-sandbox-root {
                --art-bg: #14161f;
                --art-surface: #1b1e2b;
                --art-surface-hover: #24283b;
                --art-border: rgba(255, 255, 255, 0.1);
                --art-text: #e2e8f0;
                --art-text-muted: #94a3b8;
                --art-accent: #6366f1;
                --art-accent-hover: #4f46e5;
                --art-danger: #ef4444;
                --art-danger-bg: rgba(239, 68, 68, 0.12);
                --art-warning: #f59e0b;
                --art-success: #10b981;
                font-family: inherit;
            }

            body.light-theme #artifact-sandbox-root {
                --art-bg: #f8fafc;
                --art-surface: #ffffff;
                --art-surface-hover: #f1f5f9;
                --art-border: rgba(0, 0, 0, 0.12);
                --art-text: #1e293b;
                --art-text-muted: #64748b;
                --art-accent: #4f46e5;
                --art-accent-hover: #4338ca;
                --art-danger: #dc2626;
                --art-danger-bg: rgba(220, 38, 38, 0.08);
                --art-warning: #d97706;
                --art-success: #059669;
            }

            #artifact-sandbox-root.sandbox-dock {
                position: fixed;
                top: 0;
                right: 0;
                bottom: 0;
                z-index: 70;
                display: flex;
                flex-direction: column;
                background: var(--art-bg);
                border-left: 1px solid var(--art-border);
                box-shadow: -8px 0 32px rgba(0, 0, 0, 0.35);
                transition: transform 0.25s cubic-bezier(0.16, 1, 0.3, 1);
            }

            #artifact-sandbox-root.sandbox-fullscreen {
                position: fixed;
                inset: 0;
                width: 100vw !important;
                height: 100vh !important;
                z-index: 100;
                display: flex;
                flex-direction: column;
                background: var(--art-bg);
                box-shadow: none;
                border-left: none;
            }

            #artifact-sandbox-root.sandbox-hidden {
                display: none !important;
            }

            .sandbox-resizer {
                position: absolute;
                top: 0;
                left: -4px;
                width: 8px;
                height: 100%;
                cursor: col-resize;
                z-index: 75;
                transition: background 0.15s ease;
            }
            .sandbox-resizer:hover, .sandbox-resizer.dragging {
                background: rgba(99, 102, 241, 0.5);
            }

            /* Viewport simulations */
            .viewport-desktop {
                width: 100%;
                height: 100%;
                border: none;
            }
            .viewport-tablet {
                width: 768px;
                max-width: 95%;
                height: 94%;
                margin: auto;
                border: 8px solid #2d3748;
                border-radius: 20px;
                box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
                background: #fff;
            }
            .viewport-mobile {
                width: 380px;
                max-width: 95%;
                height: 720px;
                max-height: 94%;
                margin: auto;
                border: 10px solid #2d3748;
                border-radius: 36px;
                box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
                background: #fff;
            }

            .sandbox-pill-btn {
                display: inline-flex;
                align-items: center;
                gap: 0.35rem;
                padding: 0.35rem 0.75rem;
                border-radius: 9999px;
                font-size: 0.78rem;
                font-weight: 500;
                color: var(--art-text-muted);
                background: transparent;
                border: 1px solid transparent;
                cursor: pointer;
                transition: all 0.15s ease;
            }
            .sandbox-pill-btn:hover {
                color: var(--art-text);
                background: var(--art-surface-hover);
            }
            .sandbox-pill-btn.active {
                color: #ffffff;
                background: var(--art-accent);
                box-shadow: 0 2px 8px rgba(99, 102, 241, 0.35);
            }

            .sandbox-icon-btn {
                display: inline-flex;
                align-items: center;
                justify-content: center;
                width: 2rem;
                height: 2rem;
                border-radius: 0.5rem;
                color: var(--art-text-muted);
                background: transparent;
                border: none;
                cursor: pointer;
                transition: all 0.15s ease;
                font-size: 1.1rem;
            }
            .sandbox-icon-btn:hover {
                color: var(--art-text);
                background: var(--art-surface-hover);
            }
            .sandbox-icon-btn.active {
                color: var(--art-accent);
                background: var(--art-surface-hover);
            }

            /* Log line formatting */
            .console-log-row {
                display: flex;
                align-items: flex-start;
                gap: 0.5rem;
                padding: 0.35rem 0.6rem;
                font-family: 'Fira Code', 'Courier New', monospace;
                font-size: 0.75rem;
                border-bottom: 1px solid var(--art-border);
            }
            .console-log-row.log-error {
                background: rgba(239, 68, 68, 0.08);
                color: #f87171;
            }
            .console-log-row.log-warn {
                background: rgba(245, 158, 11, 0.08);
                color: #fbbf24;
            }
            .console-log-row.log-info {
                color: #60a5fa;
            }
            .console-log-row.log-log {
                color: var(--art-text);
            }
        `;
        document.head.appendChild(style);
    }

    /**
     * Build the Sandbox Shell in the DOM
     */
    function buildSandboxDOM() {
        if (document.getElementById('artifact-sandbox-root')) return;

        injectStyles();

        const container = document.createElement('aside');
        container.id = 'artifact-sandbox-root';
        container.className = 'sandbox-dock sandbox-hidden';
        container.style.width = `${state.dockWidth}px`;

        container.innerHTML = `
            <!-- Left Resizer Handle -->
            <div id="sandbox-resizer" class="sandbox-resizer" title="Tarik untuk mengubah lebar panel (Klik ganda untuk reset)"></div>

            <!-- Header Toolbar -->
            <header class="h-14 px-4 flex items-center justify-between border-b shrink-0" style="background: var(--art-surface); border-color: var(--art-border);">
                <!-- Left: Title & Badge -->
                <div class="flex items-center gap-2.5 min-w-0 pr-2">
                    <div class="w-8 h-8 rounded-lg flex items-center justify-center shrink-0" style="background: rgba(99, 102, 241, 0.15); color: var(--art-accent);">
                        <i class='bx bx-window-alt text-lg'></i>
                    </div>
                    <div class="truncate">
                        <div class="flex items-center gap-1.5">
                            <span id="sandbox-title" class="text-xs font-bold truncate" style="color: var(--art-text);">Interactive Artifact</span>
                            <span id="sandbox-lang-badge" class="px-1.5 py-0.5 text-[10px] font-mono uppercase font-bold rounded" style="background: rgba(255,255,255,0.06); color: var(--art-text-muted);">HTML</span>
                        </div>
                    </div>
                </div>

                <!-- Center: Navigation Tabs -->
                <div class="flex items-center gap-1 p-1 rounded-full shrink-0" style="background: rgba(0,0,0,0.15); border: 1px solid var(--art-border);">
                    <button id="sandbox-tab-preview" onclick="window.GemmaArtifactSandbox.setTab('preview')" class="sandbox-pill-btn active">
                        <i class='bx bx-play-circle'></i> Preview
                    </button>
                    <button id="sandbox-tab-code" onclick="window.GemmaArtifactSandbox.setTab('code')" class="sandbox-pill-btn">
                        <i class='bx bx-code'></i> Kode
                    </button>
                    <button id="sandbox-tab-console" onclick="window.GemmaArtifactSandbox.setTab('console')" class="sandbox-pill-btn">
                        <i class='bx bx-terminal'></i> Console
                        <span id="sandbox-console-badge" class="hidden px-1.5 py-0.2 text-[9px] font-bold rounded-full bg-red-500 text-white ml-0.5">0</span>
                    </button>
                </div>

                <!-- Right: Action Icons -->
                <div class="flex items-center gap-1 shrink-0">
                    <!-- Viewport switcher (visible on preview tab) -->
                    <div id="sandbox-viewport-controls" class="flex items-center mr-1">
                        <button onclick="window.GemmaArtifactSandbox.setViewport('desktop')" id="vp-btn-desktop" title="Tampilan Desktop (100%)" class="sandbox-icon-btn active"><i class='bx bx-desktop text-sm'></i></button>
                        <button onclick="window.GemmaArtifactSandbox.setViewport('tablet')" id="vp-btn-tablet" title="Tampilan Tablet (768px)" class="sandbox-icon-btn"><i class='bx bx-tab text-sm'></i></button>
                        <button onclick="window.GemmaArtifactSandbox.setViewport('mobile')" id="vp-btn-mobile" title="Tampilan Ponsel (380px)" class="sandbox-icon-btn"><i class='bx bx-mobile text-sm'></i></button>
                    </div>

                    <button onclick="window.GemmaArtifactSandbox.reload()" title="Muat Ulang Sandbox" class="sandbox-icon-btn"><i class='bx bx-refresh'></i></button>
                    <button onclick="window.GemmaArtifactSandbox.download()" title="Unduh File HTML" class="sandbox-icon-btn"><i class='bx bx-download'></i></button>
                    <button onclick="window.GemmaArtifactSandbox.toggleMaximize()" id="sandbox-btn-maximize" title="Mode Layar Penuh" class="sandbox-icon-btn"><i class='bx bx-expand'></i></button>
                    <button onclick="window.GemmaArtifactSandbox.close()" title="Tutup Artifact" class="sandbox-icon-btn hover:text-red-400"><i class='bx bx-x text-xl'></i></button>
                </div>
            </header>

            <!-- Error Banner (Auto-Debug Feedback Loop) -->
            <div id="sandbox-error-banner" class="hidden px-4 py-2.5 items-center justify-between gap-3 shrink-0 transition-all border-b" style="background: var(--art-danger-bg); border-color: rgba(239, 68, 68, 0.25);">
                <div class="flex items-center gap-2 text-xs truncate" style="color: var(--art-danger);">
                    <i class='bx bx-error-circle text-base shrink-0'></i>
                    <span id="sandbox-error-msg" class="truncate font-mono">Error terdeteksi di JavaScript sandbox.</span>
                </div>
                <button onclick="window.GemmaArtifactSandbox.fixWithAI()" class="px-2.5 py-1 text-xs font-semibold rounded-lg bg-red-600 hover:bg-red-700 text-white flex items-center gap-1 shrink-0 transition-all shadow-sm">
                    <i class='bx bx-wrench'></i> Perbaiki dengan AI
                </button>
            </div>

            <!-- Main Content Canvas Area -->
            <div class="flex-1 relative overflow-hidden flex flex-col" style="background: var(--art-bg);">
                <!-- TAB 1: PREVIEW (IFRAME) -->
                <div id="sandbox-pane-preview" class="w-full h-full flex items-center justify-center overflow-auto p-0 relative">
                    <iframe id="sandbox-iframe" class="viewport-desktop" sandbox="allow-scripts allow-forms allow-popups allow-modals"></iframe>
                </div>

                <!-- TAB 2: CODE EDITOR / VIEWER -->
                <div id="sandbox-pane-code" class="w-full h-full hidden flex-col overflow-hidden">
                    <div class="h-9 px-4 flex items-center justify-between border-b shrink-0 text-xs" style="background: var(--art-surface); border-color: var(--art-border); color: var(--art-text-muted);">
                        <span>Editor Kode Sumber (Live)</span>
                        <div class="flex items-center gap-2">
                            <button onclick="window.GemmaArtifactSandbox.copyCode()" class="hover:text-white transition-colors flex items-center gap-1 font-medium">
                                <i class='bx bx-copy'></i> <span id="sandbox-copy-label">Salin</span>
                            </button>
                            <span class="opacity-30">|</span>
                            <button onclick="window.GemmaArtifactSandbox.applyCodeChanges()" class="hover:text-green-400 text-green-500 transition-colors flex items-center gap-1 font-bold">
                                <i class='bx bx-play'></i> Terapkan & Jalankan
                            </button>
                        </div>
                    </div>
                    <textarea id="sandbox-code-editor" class="flex-1 w-full p-4 font-mono text-xs leading-relaxed outline-none resize-none border-0"
                        style="background: #0f111a; color: #a6accd; tab-size: 2;" spellcheck="false"></textarea>
                </div>

                <!-- TAB 3: CONSOLE LOGS -->
                <div id="sandbox-pane-console" class="w-full h-full hidden flex-col overflow-hidden">
                    <div class="h-9 px-4 flex items-center justify-between border-b shrink-0 text-xs" style="background: var(--art-surface); border-color: var(--art-border); color: var(--art-text-muted);">
                        <div class="flex items-center gap-2">
                            <i class='bx bx-terminal text-sm'></i>
                            <span>Output Konsol JavaScript</span>
                        </div>
                        <div class="flex items-center gap-2">
                            <button onclick="window.GemmaArtifactSandbox.clearConsole()" class="hover:text-white transition-colors flex items-center gap-1 font-medium">
                                <i class='bx bx-trash'></i> Bersihkan
                            </button>
                        </div>
                    </div>
                    <div id="sandbox-console-output" class="flex-1 overflow-y-auto p-2 space-y-1 font-mono text-xs select-text">
                        <div class="text-slate-500 p-3 italic">Konsol kosong. Panggilan console.log atau error akan tampil di sini secara real-time.</div>
                    </div>
                </div>
            </div>
        `;

        document.body.appendChild(container);
        setupResizer(container);
    }

    /**
     * Resizer handler for smooth dragging
     */
    function setupResizer(container) {
        const resizer = document.getElementById('sandbox-resizer');
        if (!resizer) return;

        resizer.addEventListener('mousedown', function (e) {
            e.preventDefault();
            state.isDragging = true;
            state.dragStartX = e.clientX;
            state.dragStartWidth = container.offsetWidth;
            resizer.classList.add('dragging');
            document.body.style.cursor = 'col-resize';
            document.body.style.userSelect = 'none';

            function onMouseMove(ev) {
                if (!state.isDragging) return;
                const delta = state.dragStartX - ev.clientX;
                const newWidth = Math.max(MIN_WIDTH, Math.min(Math.floor(window.innerWidth * 0.92), state.dragStartWidth + delta));
                container.style.width = `${newWidth}px`;
                state.dockWidth = newWidth;
            }

            function onMouseUp() {
                if (!state.isDragging) return;
                state.isDragging = false;
                resizer.classList.remove('dragging');
                document.body.style.cursor = '';
                document.body.style.userSelect = '';
                try {
                    if (typeof window !== 'undefined' && window.localStorage) {
                        window.localStorage.setItem(STORAGE_KEY_WIDTH, state.dockWidth);
                    }
                } catch (e) {}
                window.removeEventListener('mousemove', onMouseMove);
                window.removeEventListener('mouseup', onMouseUp);
            }

            window.addEventListener('mousemove', onMouseMove);
            window.addEventListener('mouseup', onMouseUp);
        });

        // Double click resizer to toggle reset width (680px)
        resizer.addEventListener('dblclick', function () {
            state.dockWidth = DEFAULT_WIDTH;
            container.style.width = `${DEFAULT_WIDTH}px`;
            try {
                if (typeof window !== 'undefined' && window.localStorage) {
                    window.localStorage.setItem(STORAGE_KEY_WIDTH, DEFAULT_WIDTH);
                }
            } catch (e) {}
        });
    }

    /**
     * Prepare complete HTML source with offline assets & console interceptor harness
     */
    function prepareHarness(rawCode) {
        let code = String(rawCode || '').trim();

        // Check if code has Tailwind classes and needs local tailwind script
        const hasTailwindClasses = /class=["'][^"']*\b(flex|grid|p-\d|m-\d|text-\w+|bg-\w+|rounded-\w+|shadow|border)\b[^"']*["']/i.test(code);
        const hasTailwindScript = code.includes('tailwindcss.js') || code.includes('tailwindcss.com');
        let tailwindScriptTag = '';
        if (hasTailwindClasses && !hasTailwindScript) {
            tailwindScriptTag = `<script src="nano_asset/assets/js/tailwindcss.js"></` + `script>`;
        }

        // Harness script to intercept console and errors from inside the iframe
        const harnessScript = `
<script>
(function() {
    function serialize(arg) {
        try {
            if (arg instanceof Error) return (arg.stack || arg.message);
            if (typeof arg === 'object' && arg !== null) return JSON.stringify(arg);
            return String(arg);
        } catch(e) { return String(arg); }
    }
    function sendLog(level, args) {
        try {
            const text = Array.from(args).map(serialize).join(' ');
            window.parent.postMessage({
                type: 'GEMMA_ARTIFACT_LOG',
                level: level,
                text: text,
                time: new Date().toLocaleTimeString()
            }, '*');
        } catch(e) {}
    }
    const _log = console.log, _warn = console.warn, _error = console.error, _info = console.info;
    console.log = function(...args) { _log.apply(console, args); sendLog('log', args); };
    console.warn = function(...args) { _warn.apply(console, args); sendLog('warn', args); };
    console.error = function(...args) { _error.apply(console, args); sendLog('error', args); };
    console.info = function(...args) { _info.apply(console, args); sendLog('info', args); };

    window.onerror = function(message, source, lineno, colno, error) {
        window.parent.postMessage({
            type: 'GEMMA_ARTIFACT_ERROR',
            message: String(message),
            source: source,
            lineno: lineno,
            colno: colno,
            stack: error ? error.stack : ''
        }, '*');
        return false;
    };

    window.addEventListener('unhandledrejection', function(event) {
        window.parent.postMessage({
            type: 'GEMMA_ARTIFACT_ERROR',
            message: event.reason ? (event.reason.message || String(event.reason)) : 'Unhandled Promise Rejection',
            stack: event.reason && event.reason.stack ? event.reason.stack : ''
        }, '*');
    });
})();
</` + `script>`;

        // Construct HTML structure
        if (code.includes('<html') || code.includes('<!DOCTYPE') || code.includes('<head>')) {
            if (code.includes('<head>')) {
                return code.replace('<head>', `<head>\n${harnessScript}\n${tailwindScriptTag}`);
            } else if (code.includes('<html>')) {
                return code.replace('<html>', `<html><head>\n${harnessScript}\n${tailwindScriptTag}</head>`);
            }
            return `${harnessScript}\n${tailwindScriptTag}\n${code}`;
        }

        // Snippet wrapping
        return `<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    ${harnessScript}
    ${tailwindScriptTag}
    <style>
        body { margin: 0; padding: 1.5rem; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #ffffff; color: #1e293b; }
    </style>
</head>
<body>
    ${code}
</body>
</html>`;
    }

    /**
     * Render code into iframe
     */
    function renderIframe(rawCode) {
        const iframe = document.getElementById('sandbox-iframe');
        if (!iframe) return;

        // Clear previous runtime error banner
        hideErrorBanner();

        const srcDoc = prepareHarness(rawCode);
        iframe.srcdoc = srcDoc;
    }

    /**
     * Handle incoming postMessage from iframe
     */
    function handleWindowMessage(event) {
        const data = event.data;
        if (!data || typeof data !== 'object') return;

        if (data.type === 'GEMMA_ARTIFACT_LOG') {
            appendConsoleLog(data.level, data.text, data.time);
        } else if (data.type === 'GEMMA_ARTIFACT_ERROR') {
            handleRuntimeError(data);
        }
    }

    /**
     * Append to interactive console log tab
     */
    function appendConsoleLog(level, text, time) {
        const logEntry = {
            id: Date.now() + Math.random(),
            level: level || 'log',
            text: text || '',
            time: time || new Date().toLocaleTimeString()
        };
        state.consoleLogs.push(logEntry);

        const out = document.getElementById('sandbox-console-output');
        if (!out) return;

        // Remove placeholder if present
        if (state.consoleLogs.length === 1) {
            out.innerHTML = '';
        }

        const row = document.createElement('div');
        row.className = `console-log-row log-${escapeHtml(level)}`;

        let badgeColor = 'bg-slate-700 text-slate-300';
        if (level === 'error') badgeColor = 'bg-red-500 text-white';
        else if (level === 'warn') badgeColor = 'bg-yellow-500 text-slate-900';
        else if (level === 'info') badgeColor = 'bg-blue-500 text-white';

        row.innerHTML = `
            <span class="text-slate-500 shrink-0 text-[10px]">[${escapeHtml(logEntry.time)}]</span>
            <span class="px-1.5 py-0.2 rounded text-[9px] font-bold shrink-0 ${badgeColor}">${escapeHtml(level.toUpperCase())}</span>
            <span class="flex-1 whitespace-pre-wrap break-all">${escapeHtml(text)}</span>
        `;
        out.appendChild(row);
        out.scrollTop = out.scrollHeight;

        updateConsoleBadge();
    }

    /**
     * Update error & count badge in console tab
     */
    function updateConsoleBadge() {
        const badge = document.getElementById('sandbox-console-badge');
        if (!badge) return;
        const errCount = state.consoleLogs.filter(l => l.level === 'error').length;
        if (errCount > 0) {
            badge.textContent = String(errCount);
            badge.classList.remove('hidden');
        } else {
            badge.classList.add('hidden');
        }
    }

    /**
     * Handle runtime error event
     */
    function handleRuntimeError(err) {
        state.lastError = err;
        appendConsoleLog('error', `${err.message}${err.lineno ? ` (Baris ${err.lineno})` : ''}`, new Date().toLocaleTimeString());

        const banner = document.getElementById('sandbox-error-banner');
        const msgSpan = document.getElementById('sandbox-error-msg');
        if (banner && msgSpan) {
            msgSpan.textContent = `Error: ${err.message}${err.lineno ? ` (Baris ${err.lineno})` : ''}`;
            banner.classList.remove('hidden');
            banner.classList.add('flex');
        }
    }

    function hideErrorBanner() {
        state.lastError = null;
        const banner = document.getElementById('sandbox-error-banner');
        if (banner) {
            banner.classList.add('hidden');
            banner.classList.remove('flex');
        }
    }

    /**
     * Public API
     */
    const Sandbox = {
        /**
         * Open the Sandbox with given code and options
         */
        open: function (codeOrOptions) {
            buildSandboxDOM();

            let code = '';
            let title = 'Interactive Artifact';
            let lang = 'html';
            let mode = 'dock';
            let tab = 'preview';

            if (typeof codeOrOptions === 'string') {
                code = decodeURIComponent(codeOrOptions);
            } else if (codeOrOptions && typeof codeOrOptions === 'object') {
                code = decodeURIComponent(codeOrOptions.code || '');
                if (codeOrOptions.title) title = codeOrOptions.title;
                if (codeOrOptions.language) lang = codeOrOptions.language;
                if (codeOrOptions.mode) mode = codeOrOptions.mode;
                if (codeOrOptions.tab) tab = codeOrOptions.tab;
            }

            state.currentCode = code;
            state.originalCode = code;
            state.title = title;
            state.language = lang;
            state.consoleLogs = [];

            // Update UI elements
            const root = document.getElementById('artifact-sandbox-root');
            const titleEl = document.getElementById('sandbox-title');
            const langBadge = document.getElementById('sandbox-lang-badge');
            const editor = document.getElementById('sandbox-code-editor');
            const consoleOut = document.getElementById('sandbox-console-output');

            if (titleEl) titleEl.textContent = title;
            if (langBadge) langBadge.textContent = lang.toUpperCase();
            if (editor) editor.value = code;
            if (consoleOut) consoleOut.innerHTML = '<div class="text-slate-500 p-3 italic">Konsol kosong. Panggilan console.log atau error akan tampil di sini secara real-time.</div>';
            updateConsoleBadge();

            // Setup mode
            if (mode === 'modal' || mode === 'fullscreen') {
                root.classList.remove('sandbox-dock');
                root.classList.add('sandbox-fullscreen');
                state.isMaximized = true;
                const maxBtn = document.getElementById('sandbox-btn-maximize');
                if (maxBtn) maxBtn.innerHTML = "<i class='bx bx-collapse'></i>";
            } else {
                root.classList.remove('sandbox-fullscreen');
                root.classList.add('sandbox-dock');
                root.style.width = `${state.dockWidth}px`;
                state.isMaximized = false;
                const maxBtn = document.getElementById('sandbox-btn-maximize');
                if (maxBtn) maxBtn.innerHTML = "<i class='bx bx-expand'></i>";
            }

            root.classList.remove('sandbox-hidden');
            state.isOpen = true;

            this.setTab(tab);
            renderIframe(code);
        },

        /**
         * Close the Sandbox
         */
        close: function () {
            const root = document.getElementById('artifact-sandbox-root');
            const iframe = document.getElementById('sandbox-iframe');
            if (iframe) iframe.srcdoc = '';
            if (root) {
                root.classList.add('sandbox-hidden');
            }
            state.isOpen = false;
        },

        /**
         * Switch active tab ('preview' | 'code' | 'console')
         */
        setTab: function (tabName) {
            state.activeTab = tabName;

            const tabs = ['preview', 'code', 'console'];
            tabs.forEach(t => {
                const btn = document.getElementById(`sandbox-tab-${t}`);
                const pane = document.getElementById(`sandbox-pane-${t}`);
                if (t === tabName) {
                    btn?.classList.add('active');
                    pane?.classList.remove('hidden');
                    pane?.classList.add('flex');
                } else {
                    btn?.classList.remove('active');
                    pane?.classList.add('hidden');
                    pane?.classList.remove('flex');
                }
            });

            // Viewport controls only visible on preview tab
            const vpControls = document.getElementById('sandbox-viewport-controls');
            if (vpControls) {
                vpControls.style.display = (tabName === 'preview') ? 'flex' : 'none';
            }
        },

        /**
         * Switch viewport simulation ('desktop' | 'tablet' | 'mobile')
         */
        setViewport: function (mode) {
            state.activeViewport = mode;
            const iframe = document.getElementById('sandbox-iframe');
            if (!iframe) return;

            ['desktop', 'tablet', 'mobile'].forEach(m => {
                const btn = document.getElementById(`vp-btn-${m}`);
                if (m === mode) btn?.classList.add('active');
                else btn?.classList.remove('active');
            });

            iframe.className = `viewport-${mode}`;
        },

        /**
         * Reload / Reset the iframe
         */
        reload: function () {
            renderIframe(state.currentCode);
        },

        /**
         * Toggle Maximize / Fullscreen
         */
        toggleMaximize: function () {
            const root = document.getElementById('artifact-sandbox-root');
            const maxBtn = document.getElementById('sandbox-btn-maximize');
            if (!root) return;

            if (state.isMaximized) {
                root.classList.remove('sandbox-fullscreen');
                root.classList.add('sandbox-dock');
                root.style.width = `${state.dockWidth}px`;
                state.isMaximized = false;
                if (maxBtn) maxBtn.innerHTML = "<i class='bx bx-expand'></i>";
            } else {
                root.classList.remove('sandbox-dock');
                root.classList.add('sandbox-fullscreen');
                state.isMaximized = true;
                if (maxBtn) maxBtn.innerHTML = "<i class='bx bx-collapse'></i>";
            }
        },

        /**
         * Apply changes made in the code editor tab
         */
        applyCodeChanges: function () {
            const editor = document.getElementById('sandbox-code-editor');
            if (!editor) return;
            state.currentCode = editor.value;
            renderIframe(state.currentCode);
            this.setTab('preview');
            if (typeof window.showToast === 'function') {
                window.showToast('Perubahan kode berhasil diterapkan ke live preview.', 'success');
            }
        },

        /**
         * Copy current code to clipboard
         */
        copyCode: function () {
            const editor = document.getElementById('sandbox-code-editor');
            const label = document.getElementById('sandbox-copy-label');
            const codeToCopy = editor ? editor.value : state.currentCode;

            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(codeToCopy).then(() => {
                    if (label) {
                        label.textContent = 'Tersalin!';
                        setTimeout(() => { label.textContent = 'Salin'; }, 2000);
                    }
                });
            }
        },

        /**
         * Download current artifact as standalone HTML
         */
        download: function () {
            if (!state.currentCode) return;
            const fullHtml = prepareHarness(state.currentCode);
            const blob = new Blob([fullHtml], { type: 'text/html;charset=utf-8' });
            const url = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.download = `artifact-${Date.now()}.html`;
            link.click();
            URL.revokeObjectURL(url);
        },

        /**
         * Clear Console logs
         */
        clearConsole: function () {
            state.consoleLogs = [];
            const out = document.getElementById('sandbox-console-output');
            if (out) {
                out.innerHTML = '<div class="text-slate-500 p-3 italic">Konsol telah dibersihkan.</div>';
            }
            updateConsoleBadge();
        },

        /**
         * One-Click "Fix with AI" Feedback Loop
         */
        fixWithAI: function () {
            const err = state.lastError || { message: 'Terjadi error yang tidak diketahui.' };
            const promptEl = document.getElementById('prompt');

            const repairPrompt = [
                'Tolong perbaiki error JavaScript berikut pada artifact sebelumnya:',
                `❌ Pesan Error: ${err.message}`,
                err.lineno ? `📍 Baris: ${err.lineno}${err.colno ? `:${err.colno}` : ''}` : '',
                err.stack ? `\nDetail Stack Trace:\n\`\`\`\n${err.stack.trim()}\n\`\`\`` : '',
                '\nBerikut adalah kode yang sedang dijalankan saat error terjadi:',
                '```html',
                state.currentCode,
                '```',
                '\nMohon analisis penyebab error tersebut dan berikan solusi kode HTML/JS lengkap yang sudah diperbaiki.'
            ].filter(Boolean).join('\n');

            if (promptEl) {
                promptEl.value = repairPrompt;
                promptEl.dispatchEvent(new Event('input', { bubbles: true }));
                promptEl.focus();

                // If on mobile or small screen, minimize or switch to chat
                if (window.innerWidth < 768 && state.isMaximized) {
                    this.toggleMaximize();
                }

                if (typeof window.showToast === 'function') {
                    window.showToast('Pesan perbaikan error disiapkan di input obrolan. Tekan Enter untuk mengirim.', 'info');
                }
            } else {
                navigator.clipboard?.writeText(repairPrompt);
                alert('Pesan perbaikan error telah disalin ke clipboard.');
            }
        },

        /**
         * Wire global hooks for backward compatibility
         */
        wireGlobalHooks: function () {
            // Override or create openArtifactDock
            global.openArtifactDock = function (codeRaw) {
                Sandbox.open({ code: codeRaw, mode: 'dock', tab: 'preview' });
            };

            // Override or create openPreviewModal
            global.openPreviewModal = function (codeRaw) {
                Sandbox.open({ code: codeRaw, mode: 'modal', tab: 'preview' });
            };

            // Override or create openSplitEditor
            global.openSplitEditor = function (codeRaw) {
                Sandbox.open({ code: codeRaw, mode: 'dock', tab: 'code' });
            };

            // Override close hooks
            global.closeArtifactDock = function () {
                Sandbox.close();
            };
            global.closePreviewModal = function () {
                Sandbox.close();
            };
            global.closeSplitEditor = function () {
                Sandbox.close();
            };
            global.downloadCurrentArtifact = function () {
                Sandbox.download();
            };
        }
    };

    // Expose helpers for tests & inspection
    Sandbox.prepareHarness = prepareHarness;
    Sandbox.getState = function () { return Object.assign({}, state); };
    Sandbox.handleWindowMessage = handleWindowMessage;

    // Listen to iframe postMessages
    if (typeof window !== 'undefined' && typeof window.addEventListener === 'function') {
        window.addEventListener('message', handleWindowMessage);
    }

    // Auto-initialize when DOM is ready
    if (typeof document !== 'undefined') {
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function () {
                Sandbox.wireGlobalHooks();
            });
        } else {
            Sandbox.wireGlobalHooks();
        }
    }

    // Export to global scope
    global.GemmaArtifactSandbox = Sandbox;
    global.ArtifactSandbox = Sandbox;

    // Node.js module export
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = Sandbox;
    }

})(typeof window !== 'undefined' ? window : globalThis);

