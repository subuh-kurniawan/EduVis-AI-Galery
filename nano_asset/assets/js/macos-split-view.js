/**
 * macOS 3-Pane Split View & Inspector System (Apple HIG Compliant)
 * Mengelola layout 3-Pane: Sidebar (Navigasi), Chat (Percakapan), dan Inspector/Canvas (Pratinjau & Parameter)
 * Dilengkapi pembagi seret (draggable divider), search field standar Apple, dan keyboard shortcuts.
 */

(() => {
    'use strict';

    const STORAGE_KEY_LEFT = 'gemma_split_left_width';
    const STORAGE_KEY_RIGHT = 'gemma_split_right_width';
    const DEFAULT_LEFT_WIDTH = 260;
    const DEFAULT_RIGHT_WIDTH = 460;

    const getStoredWidth = (key, defaultVal) => {
        if (typeof localStorage !== 'undefined' && localStorage && typeof localStorage.getItem === 'function') {
            try {
                const val = localStorage.getItem(key);
                return val ? parseInt(val, 10) : defaultVal;
            } catch (_) {}
        }
        return defaultVal;
    };

    let splitState = {
        leftWidth: getStoredWidth(STORAGE_KEY_LEFT, DEFAULT_LEFT_WIDTH),
        rightWidth: getStoredWidth(STORAGE_KEY_RIGHT, DEFAULT_RIGHT_WIDTH),
        isLeftCollapsed: false,
        isRightCollapsed: true,
        activeInspectorTab: 'parameters' // 'canvas' | 'parameters'
    };

    /**
     * Inisialisasi Search Field sesuai standar Apple HIG:
     * Ikon kaca pembesar leading, clear button '✕' trailing, dan callback pencarian instan.
     */
    function initSearchField(inputEl, onSearch) {
        if (!inputEl) return null;

        // Bungkus dalam kapsul macOS Search Field jika belum
        if (!inputEl.parentElement.classList.contains('macos-search-field-wrapper')) {
            const wrapper = document.createElement('div');
            wrapper.className = 'macos-search-field-wrapper';
            inputEl.parentNode.insertBefore(wrapper, inputEl);
            wrapper.appendChild(inputEl);

            const iconLeading = document.createElement('span');
            iconLeading.className = 'macos-search-icon';
            iconLeading.innerHTML = '🔍';
            wrapper.insertBefore(iconLeading, inputEl);

            const clearBtn = document.createElement('button');
            clearBtn.type = 'button';
            clearBtn.className = 'macos-search-clear-btn';
            clearBtn.innerHTML = '✕';
            clearBtn.title = 'Hapus pencarian';
            clearBtn.style.display = inputEl.value ? 'block' : 'none';
            wrapper.appendChild(clearBtn);

            let debounceTimer = null;
            inputEl.addEventListener('input', () => {
                clearBtn.style.display = inputEl.value ? 'block' : 'none';
                clearTimeout(debounceTimer);
                debounceTimer = setTimeout(() => {
                    if (typeof onSearch === 'function') onSearch(inputEl.value.trim());
                }, 180);
            });

            clearBtn.addEventListener('click', () => {
                inputEl.value = '';
                clearBtn.style.display = 'none';
                inputEl.focus();
                if (typeof onSearch === 'function') onSearch('');
            });
        }

        return inputEl;
    }

    /**
     * Membuka atau menutup panel inspektor samping kanan
     */
    function toggleInspector(mode = null) {
        if (mode && splitState.activeInspectorTab !== mode && !splitState.isRightCollapsed) {
            setInspectorTab(mode);
            return;
        }
        if (splitState.isRightCollapsed) {
            openInspector(mode || splitState.activeInspectorTab);
        } else {
            closeInspector();
        }
    }

    /**
     * Membuat panel inspector (tab Canvas + Parameter) sekali saja bila belum ada di halaman.
     * Mengambang di sisi kanan sehingga tidak mengubah layout halaman yang sudah ada.
     */
    function ensureInspectorPane() {
        if (typeof document === 'undefined') return null;
        let pane = document.getElementById('macos-inspector-pane');
        if (pane) return pane;

        pane = document.createElement('aside');
        pane.id = 'macos-inspector-pane';
        pane.className = 'macos-inspector-pane hidden';
        pane.setAttribute('aria-label', 'Inspector');
        pane.style.cssText = `position:fixed; top:0; right:0; bottom:0; width:${splitState.rightWidth}px; max-width:90vw; display:none;`;
        pane.innerHTML = `
            <div style="display:flex; align-items:center; gap:6px; padding:44px 12px 10px; border-bottom:1px solid rgba(255,255,255,0.08);">
                <button id="btn-inspector-tab-canvas" type="button" style="flex:1; padding:5px 8px; font-size:12px; border-radius:8px; border:1px solid rgba(255,255,255,0.12); background:rgba(255,255,255,0.06); color:#e2e8f0; cursor:pointer;">Canvas</button>
                <button id="btn-inspector-tab-params" type="button" style="flex:1; padding:5px 8px; font-size:12px; border-radius:8px; border:1px solid rgba(255,255,255,0.12); background:rgba(255,255,255,0.06); color:#e2e8f0; cursor:pointer;">Parameter</button>
                <button id="btn-inspector-close" type="button" aria-label="Tutup inspector" style="padding:4px 8px; border:none; background:transparent; color:#94a3b8; cursor:pointer; font-size:14px;">✕</button>
            </div>
            <div style="flex:1; overflow-y:auto;">
                <div id="inspector-tab-canvas" style="padding:16px; font-size:12px; color:#94a3b8;">Belum ada artifact. Diagram, grafik, atau kode yang dihasilkan model akan tampil di sini.</div>
                <div id="inspector-tab-parameters" style="display:none;"></div>
            </div>`;
        document.body.appendChild(pane);
        pane.querySelector('#btn-inspector-tab-canvas').addEventListener('click', () => setInspectorTab('canvas'));
        pane.querySelector('#btn-inspector-tab-params').addEventListener('click', () => setInspectorTab('parameters'));
        pane.querySelector('#btn-inspector-close').addEventListener('click', closeInspector);
        return pane;
    }

    function openInspector(mode = 'parameters') {
        splitState.isRightCollapsed = false;
        splitState.activeInspectorTab = mode;
        const inspector = ensureInspectorPane();
        if (inspector) {
            inspector.classList.remove('hidden');
            inspector.style.display = 'flex';
            if (typeof inspector.style.setProperty === 'function') {
                inspector.style.setProperty('display', 'flex', 'important');
            }
            inspector.style.width = `${splitState.rightWidth}px`;
        }
        setInspectorTab(mode);
    }

    function closeInspector() {
        splitState.isRightCollapsed = true;
        const inspector = typeof document !== 'undefined' ? document.getElementById('macos-inspector-pane') : null;
        if (inspector) {
            inspector.classList.add('hidden');
            inspector.style.display = 'none';
            if (typeof inspector.style.setProperty === 'function') {
                inspector.style.setProperty('display', 'none', 'important');
            }
        }
    }

    function toggleSidebar() {
        splitState.isLeftCollapsed = !splitState.isLeftCollapsed;
        const sidebar = document.querySelector('aside.sidebar, #sidebar, .macos-sidebar-pane');
        if (sidebar) {
            if (splitState.isLeftCollapsed) {
                sidebar.classList.add('hidden');
                sidebar.style.display = 'none';
            } else {
                sidebar.classList.remove('hidden');
                sidebar.style.display = 'flex';
                sidebar.style.width = `${splitState.leftWidth}px`;
            }
        }
    }

    function setInspectorTab(tabName) {
        splitState.activeInspectorTab = tabName;
        const canvasView = document.getElementById('inspector-tab-canvas');
        const paramsView = document.getElementById('inspector-tab-parameters');
        const btnCanvas = document.getElementById('btn-inspector-tab-canvas');
        const btnParams = document.getElementById('btn-inspector-tab-params');

        if (tabName === 'canvas') {
            if (canvasView) canvasView.style.display = 'block';
            if (paramsView) paramsView.style.display = 'none';
            btnCanvas?.classList.add('active');
            btnParams?.classList.remove('active');
        } else {
            if (canvasView) canvasView.style.display = 'none';
            if (paramsView) {
                paramsView.style.display = 'block';
                updateParametersView(paramsView);
            }
            btnCanvas?.classList.remove('active');
            btnParams?.classList.add('active');
        }
    }

    /**
     * Memperbarui panel parameter live (Temperature, Top-P, KV-Cache memory gauge)
     */
    function updateParametersView(container) {
        if (!container) return;
        const memoryMB = (typeof window !== 'undefined' && window.KVCacheGuard && typeof window.KVCacheGuard.estimateMemoryUsageMB === 'function')
            ? window.KVCacheGuard.estimateMemoryUsageMB(4096)
            : 512;

        container.innerHTML = `
            <div style="padding:16px; font-family:system-ui, -apple-system, sans-serif;">
                <div style="margin-bottom:18px;">
                    <h4 style="margin:0 0 4px; font-size:13px; font-weight:700; color:#fff; text-transform:uppercase; letter-spacing:0.05em;">Parameter Inferensi Model</h4>
                    <p style="margin:0; font-size:11px; color:#94a3b8;">Penyesuaian atribut dinamis on-device (Apple HIG Inspector)</p>
                </div>

                <!-- Temperature Slider -->
                <div style="background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.08); border-radius:12px; padding:12px; margin-bottom:12px;">
                    <div style="display:flex; justify-content:space-between; font-size:12px; color:#e2e8f0; margin-bottom:6px;">
                        <span>Temperature (Kreativitas)</span>
                        <span id="inspector-temp-val" style="color:#38bdf8; font-family:monospace; font-weight:700;">0.7</span>
                    </div>
                    <input type="range" min="0" max="1.5" step="0.05" value="0.7" style="width:100%; accent-color:#38bdf8;" oninput="document.getElementById('inspector-temp-val').textContent = this.value">
                </div>

                <!-- Top-P Slider -->
                <div style="background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.08); border-radius:12px; padding:12px; margin-bottom:12px;">
                    <div style="display:flex; justify-content:space-between; font-size:12px; color:#e2e8f0; margin-bottom:6px;">
                        <span>Top-P (Nucleus Sampling)</span>
                        <span id="inspector-topp-val" style="color:#818cf8; font-family:monospace; font-weight:700;">0.9</span>
                    </div>
                    <input type="range" min="0.1" max="1.0" step="0.05" value="0.9" style="width:100%; accent-color:#818cf8;" oninput="document.getElementById('inspector-topp-val').textContent = this.value">
                </div>

                <!-- KV-Cache & Memory Guard -->
                <div style="background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.08); border-radius:12px; padding:12px; margin-bottom:12px;">
                    <div style="display:flex; justify-content:space-between; font-size:12px; color:#e2e8f0; margin-bottom:6px;">
                        <span>Estimasi Memori KV-Cache (4k ctx)</span>
                        <span style="color:#34d399; font-weight:700;">~${memoryMB} MB</span>
                    </div>
                    <div style="height:6px; width:100%; background:rgba(255,255,255,0.1); border-radius:99px; overflow:hidden; margin-top:6px;">
                        <div style="height:100%; width:28%; background:#34d399; border-radius:99px;"></div>
                    </div>
                </div>

                <!-- Context Gauge Container -->
                <div id="inspector-context-gauge-container" style="background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.08); border-radius:12px; padding:12px; margin-bottom:12px;">
                    <div style="font-size:12px; font-weight:600; color:#e2e8f0; margin-bottom:6px;">Status Jendela Konteks</div>
                    <div id="inspector-context-gauge" style="font-size:11px; color:#94a3b8;">Menghitung alokasi memori konteks...</div>
                </div>

                <!-- LiteRT-LM Engine & Akselerator (v0.19) -->
                <div id="inspector-litert-engine-card" style="background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.08); border-radius:12px; padding:12px;">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                        <span style="font-size:12px; font-weight:700; color:#e2e8f0;">LiteRT-LM Engine & Akselerator</span>
                        <span id="inspector-litert-version" style="font-size:10px; font-family:monospace; color:#38bdf8; background:rgba(56,189,248,0.14); padding:2px 6px; border-radius:99px;">v0.19</span>
                    </div>

                    <div style="margin-bottom:8px;">
                        <label for="inspector-litert-backend" style="display:block; font-size:11px; color:#94a3b8; margin-bottom:4px;">Backend Akselerator</label>
                        <select id="inspector-litert-backend" style="width:100%; background:rgba(15,23,42,0.85); color:#e2e8f0; border:1px solid rgba(255,255,255,0.14); border-radius:8px; padding:5px 8px; font-size:11px;">
                            <option value="gpu">GPU Metal (Apple Silicon / WebGPU)</option>
                            <option value="cpu">CPU XNNPACK (Fallback Stabil)</option>
                            <option value="npu">NPU / Neural Engine (Eksperimental)</option>
                        </select>
                    </div>

                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px; gap:8px;">
                        <label for="inspector-litert-speculative" style="font-size:11px; color:#e2e8f0; cursor:pointer;">Speculative Decoding (MTP Drafter)</label>
                        <input id="inspector-litert-speculative" type="checkbox" checked style="accent-color:#38bdf8; cursor:pointer;" />
                    </div>

                    <div style="margin-bottom:10px;">
                        <label for="inspector-litert-reasoning" style="display:block; font-size:11px; color:#94a3b8; margin-bottom:4px;">Mode Penalaran (Thinking Effort)</label>
                        <select id="inspector-litert-reasoning" style="width:100%; background:rgba(15,23,42,0.85); color:#e2e8f0; border:1px solid rgba(255,255,255,0.14); border-radius:8px; padding:5px 8px; font-size:11px;">
                            <option value="none">Mati (Respon Cepat)</option>
                            <option value="minimal">Minimal</option>
                            <option value="low">Low</option>
                            <option value="medium">Medium</option>
                            <option value="high">High (Mendalam)</option>
                        </select>
                    </div>

                    <div style="border-top:1px solid rgba(255,255,255,0.08); padding-top:8px;">
                        <div style="font-size:11px; font-weight:600; color:#cbd5e1; margin-bottom:6px;">Inspeksi Kapabilitas Model (ModelInfo)</div>
                        <div id="inspector-litert-model-info" style="font-size:11px; color:#94a3b8; line-height:1.45;">Memeriksa metadata .litertlm...</div>
                    </div>
                </div>

                <!-- Liquid Glass Control Center (Optik & Haptik) -->
                <div id="inspector-liquid-glass-card" style="background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.08); border-radius:12px; padding:12px; margin-top:12px;">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                        <span style="font-size:12px; font-weight:700; color:#e2e8f0;">Liquid Glass Control Center (Optik & Haptik)</span>
                        <span style="font-size:10px; font-family:monospace; color:#a855f7; background:rgba(168,85,247,0.14); padding:2px 6px; border-radius:99px;">HIG</span>
                    </div>

                    <div style="margin-bottom:8px;">
                        <div style="display:flex; justify-content:space-between; font-size:11px; color:#cbd5e1; margin-bottom:4px;">
                            <label for="inspector-lg-blur">Backdrop Blur</label>
                            <span id="inspector-lg-blur-val" style="color:#38bdf8; font-family:monospace; font-weight:700;">30px</span>
                        </div>
                        <input id="inspector-lg-blur" type="range" min="8" max="48" step="1" value="30" style="width:100%; accent-color:#38bdf8;" />
                    </div>

                    <div style="margin-bottom:8px;">
                        <div style="display:flex; justify-content:space-between; font-size:11px; color:#cbd5e1; margin-bottom:4px;">
                            <label for="inspector-lg-specular">Specular Reflection</label>
                            <span id="inspector-lg-specular-val" style="color:#818cf8; font-family:monospace; font-weight:700;">100%</span>
                        </div>
                        <input id="inspector-lg-specular" type="range" min="0" max="150" step="5" value="100" style="width:100%; accent-color:#818cf8;" />
                    </div>

                    <div style="margin-bottom:10px;">
                        <div style="display:flex; justify-content:space-between; font-size:11px; color:#cbd5e1; margin-bottom:4px;">
                            <label for="inspector-lg-saturate">Saturasi Kaca</label>
                            <span id="inspector-lg-saturate-val" style="color:#34d399; font-family:monospace; font-weight:700;">200%</span>
                        </div>
                        <input id="inspector-lg-saturate" type="range" min="100" max="260" step="10" value="200" style="width:100%; accent-color:#34d399;" />
                    </div>

                    <div style="display:flex; justify-content:space-between; align-items:center; gap:8px;">
                        <label for="inspector-lg-sound" style="font-size:11px; color:#e2e8f0; cursor:pointer;">Suara Haptik macOS (Web Audio)</label>
                        <input id="inspector-lg-sound" type="checkbox" checked style="accent-color:#a855f7; cursor:pointer;" />
                    </div>
                </div>

                <!-- Ukuran Font & Tipografi Chat (Aa) -->
                <div id="inspector-chat-font-card" style="background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.08); border-radius:12px; padding:12px; margin-top:12px;">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                        <span style="font-size:12px; font-weight:700; color:#e2e8f0;">Ukuran Font &amp; Tipografi Chat (Aa)</span>
                        <span id="inspector-chat-font-val" style="font-size:11px; font-family:monospace; font-weight:700; color:#38bdf8; background:rgba(56,189,248,0.14); padding:2px 8px; border-radius:99px;">15px</span>
                    </div>

                    <div style="display:flex; align-items:center; gap:6px; margin-bottom:8px;">
                        <button id="inspector-chat-font-dec" type="button" style="flex:1; padding:5px 8px; border-radius:8px; border:1px solid rgba(255,255,255,0.14); background:rgba(255,255,255,0.06); color:#f1f5f9; font-size:13px; font-weight:700; cursor:pointer;">−</button>
                        <button id="inspector-chat-font-reset" type="button" style="flex:1; padding:5px 8px; border-radius:8px; border:1px solid rgba(255,255,255,0.14); background:rgba(255,255,255,0.06); color:#cbd5e1; font-size:11px; font-weight:600; cursor:pointer;">Reset (15px)</button>
                        <button id="inspector-chat-font-inc" type="button" style="flex:1; padding:5px 8px; border-radius:8px; border:1px solid rgba(255,255,255,0.14); background:rgba(255,255,255,0.06); color:#f1f5f9; font-size:13px; font-weight:700; cursor:pointer;">+</button>
                    </div>

                    <input id="inspector-chat-font-slider" type="range" min="11" max="32" step="0.5" value="15" style="width:100%; accent-color:#38bdf8;" />
                </div>
            </div>
        `;

        // Hubungkan kontrol ukuran font chat di Inspector
        if (typeof window !== 'undefined') {
            const fontValEl = container.querySelector('#inspector-chat-font-val');
            const fontDecBtn = container.querySelector('#inspector-chat-font-dec');
            const fontIncBtn = container.querySelector('#inspector-chat-font-inc');
            const fontResetBtn = container.querySelector('#inspector-chat-font-reset');
            const fontSlider = container.querySelector('#inspector-chat-font-slider');

            const syncInspectorFontUI = (sz) => {
                const resolved = Number(sz) || (typeof window.getChatFontSize === 'function' ? window.getChatFontSize() : 15);
                if (fontValEl) fontValEl.textContent = `${resolved}px`;
                if (fontSlider) fontSlider.value = String(resolved);
            };

            syncInspectorFontUI();

            if (fontDecBtn) {
                fontDecBtn.addEventListener('click', () => {
                    const next = typeof window.decreaseChatFontSize === 'function' ? window.decreaseChatFontSize() : 15;
                    syncInspectorFontUI(next);
                });
            }
            if (fontIncBtn) {
                fontIncBtn.addEventListener('click', () => {
                    const next = typeof window.increaseChatFontSize === 'function' ? window.increaseChatFontSize() : 15;
                    syncInspectorFontUI(next);
                });
            }
            if (fontResetBtn) {
                fontResetBtn.addEventListener('click', () => {
                    const next = typeof window.resetChatFontSize === 'function' ? window.resetChatFontSize() : 15;
                    syncInspectorFontUI(next);
                });
            }
            if (fontSlider) {
                fontSlider.addEventListener('input', () => {
                    const next = typeof window.setChatFontSize === 'function'
                        ? window.setChatFontSize(fontSlider.value)
                        : Number(fontSlider.value);
                    syncInspectorFontUI(next);
                });
            }
            if (typeof window.addEventListener === 'function') {
                window.addEventListener('chat-font-size-change', (evt) => {
                    if (evt && evt.detail && evt.detail.size !== undefined) {
                        syncInspectorFontUI(evt.detail.size);
                    }
                });
            }
        }

        // Hubungkan kontrol optik & haptik Liquid Glass
        if (typeof window !== 'undefined') {
            const blurSlider = container.querySelector('#inspector-lg-blur');
            const blurVal = container.querySelector('#inspector-lg-blur-val');
            const specSlider = container.querySelector('#inspector-lg-specular');
            const specVal = container.querySelector('#inspector-lg-specular-val');
            const satSlider = container.querySelector('#inspector-lg-saturate');
            const satVal = container.querySelector('#inspector-lg-saturate-val');
            const soundChk = container.querySelector('#inspector-lg-sound');

            try {
                if (typeof localStorage !== 'undefined') {
                    const savedBlur = localStorage.getItem('eduvis_lg_blur');
                    if (savedBlur && blurSlider && blurVal) {
                        blurSlider.value = savedBlur;
                        blurVal.textContent = `${savedBlur}px`;
                    }
                    const savedSpec = localStorage.getItem('eduvis_lg_specular');
                    if (savedSpec && specSlider && specVal) {
                        const pct = Math.round(parseFloat(savedSpec) * 100);
                        specSlider.value = String(pct);
                        specVal.textContent = `${pct}%`;
                    }
                    const savedSat = localStorage.getItem('eduvis_lg_saturate');
                    if (savedSat && satSlider && satVal) {
                        satSlider.value = savedSat;
                        satVal.textContent = `${savedSat}%`;
                    }
                    const savedSound = localStorage.getItem('eduvis_lg_sound');
                    if (savedSound !== null && soundChk) {
                        soundChk.checked = savedSound !== 'false';
                    }
                }
            } catch (_) {}

            if (blurSlider) {
                blurSlider.addEventListener('input', () => {
                    const val = blurSlider.value;
                    if (blurVal) blurVal.textContent = `${val}px`;
                    if (typeof window.setGlassBlur === 'function') {
                        window.setGlassBlur(val);
                    } else if (typeof document !== 'undefined') {
                        document.documentElement.style.setProperty('--glass-blur', `${val}px`);
                    }
                });
            }
            if (specSlider) {
                specSlider.addEventListener('input', () => {
                    const pct = Number(specSlider.value) || 0;
                    const factor = (pct / 100).toFixed(2);
                    if (specVal) specVal.textContent = `${pct}%`;
                    if (typeof window.setSpecularIntensity === 'function') {
                        window.setSpecularIntensity(factor);
                    } else if (typeof document !== 'undefined') {
                        document.documentElement.style.setProperty('--specular-intensity', factor);
                    }
                });
            }
            if (satSlider) {
                satSlider.addEventListener('input', () => {
                    const val = satSlider.value;
                    if (satVal) satVal.textContent = `${val}%`;
                    if (typeof window.setGlassSaturate === 'function') {
                        window.setGlassSaturate(val);
                    } else if (typeof document !== 'undefined') {
                        document.documentElement.style.setProperty('--glass-saturate', `${val}%`);
                    }
                });
            }
            if (soundChk) {
                soundChk.addEventListener('change', () => {
                    const enabled = Boolean(soundChk.checked);
                    if (window.liquidEngine && typeof window.liquidEngine.setSoundEnabled === 'function') {
                        window.liquidEngine.setSoundEnabled(enabled);
                        if (enabled) window.liquidEngine.playSound('glass');
                    } else if (typeof localStorage !== 'undefined') {
                        try { localStorage.setItem('eduvis_lg_sound', enabled ? 'true' : 'false'); } catch (_) {}
                    }
                });
            }
        }

        // Render context gauge jika GemmaMemory tersedia
        if (typeof window !== 'undefined' && window.GemmaMemory && typeof window.GemmaMemory.renderContextGauge === 'function') {
            const gaugeEl = container.querySelector('#inspector-context-gauge');
            if (gaugeEl) {
                window.GemmaMemory.renderContextGauge(gaugeEl, window.chatHistory || []);
            }
        }

        // Hubungkan kontrol LiteRT-LM Engine & ModelInfo secara asinkron bila di browser
        if (typeof window !== 'undefined' && typeof fetch === 'function') {
            const backendEl = container.querySelector('#inspector-litert-backend');
            const specEl = container.querySelector('#inspector-litert-speculative');
            const reasonEl = container.querySelector('#inspector-litert-reasoning');
            const versionEl = container.querySelector('#inspector-litert-version');
            const infoEl = container.querySelector('#inspector-litert-model-info');

            const persistRuntimeConfig = (patch) => {
                fetch('/api/litert-config', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(patch)
                }).catch(() => {});
            };

            if (backendEl) {
                backendEl.addEventListener('change', () => {
                    persistRuntimeConfig({ backend: backendEl.value });
                });
            }
            if (specEl) {
                specEl.addEventListener('change', () => {
                    persistRuntimeConfig({ speculative_decoding: Boolean(specEl.checked) });
                });
            }
            if (reasonEl && typeof localStorage !== 'undefined') {
                try {
                    const savedEffort = localStorage.getItem('gemma_reasoning_effort');
                    if (savedEffort) reasonEl.value = savedEffort;
                } catch (_) {}
                reasonEl.addEventListener('change', () => {
                    try { localStorage.setItem('gemma_reasoning_effort', reasonEl.value); } catch (_) {}
                    persistRuntimeConfig({ thinking: reasonEl.value !== 'none' });
                });
            }

            if (infoEl) {
                fetch('/api/models/inspect')
                    .then((res) => (res.ok ? res.json() : null))
                    .then((data) => {
                        if (!data) {
                            infoEl.textContent = 'Metadata model belum tersedia.';
                            return;
                        }
                        if (versionEl && data.litert_lm_version) {
                            versionEl.textContent = `v${data.litert_lm_version}`;
                        }
                        const rt = (data.runtime_config && data.runtime_config.default) || {};
                        if (backendEl && rt.backend) backendEl.value = rt.backend;
                        if (specEl && typeof rt.speculative_decoding === 'boolean') {
                            specEl.checked = rt.speculative_decoding;
                        }
                        const models = Array.isArray(data.models) ? data.models : [];
                        if (!models.length) {
                            infoEl.textContent = 'Belum ada berkas .litertlm yang terdeteksi.';
                            return;
                        }
                        infoEl.innerHTML = models.map((m) => {
                            const mods = Array.isArray(m.modalities) ? m.modalities : ['text'];
                            const badges = mods.map((mod) =>
                                `<span style="display:inline-block; font-size:10px; padding:1px 6px; border-radius:99px; background:rgba(56,189,248,0.16); color:#7dd3fc; margin-right:4px;">${mod}</span>`
                            ).join('');
                            const mtpBadge = m.supports_mtp
                                ? '<span style="display:inline-block; font-size:10px; padding:1px 6px; border-radius:99px; background:rgba(52,211,153,0.16); color:#6ee7b7; margin-right:4px;">MTP Drafter</span>'
                                : '';
                            const fmt = m.container_format === 'tflite_web' ? 'WebGPU/TFL3' : 'LiteRT-LM';
                            const name = String(m.id || m.filename || 'model').replace(/[<>&"']/g, '');
                            return `<div style="margin-bottom:6px; padding:6px 8px; border-radius:8px; background:rgba(255,255,255,0.03);">
                                <div style="font-weight:600; color:#f1f5f9; font-size:11px; margin-bottom:3px;">${name} <span style="font-weight:400; color:#94a3b8;">(${fmt})</span></div>
                                <div>${badges}${mtpBadge}</div>
                            </div>`;
                        }).join('');
                    })
                    .catch(() => {
                        infoEl.textContent = 'Jalankan melalui server lokal untuk membaca ModelInfo.';
                    });
            }
        }
    }

    /**
     * ===== RAYCAST / SPOTLIGHT STYLE COMMAND PALETTE (Cmd+K) =====
     */
    function initCommandPalette() {
        if (typeof document === 'undefined' || document.getElementById('eduvis-cmd-palette-backdrop')) return;

        const backdrop = document.createElement('div');
        backdrop.id = 'eduvis-cmd-palette-backdrop';
        backdrop.style.cssText = `
            position: fixed; inset: 0; z-index: 99999;
            background: rgba(0, 0, 0, 0.55);
            backdrop-filter: blur(14px) saturate(160%);
            -webkit-backdrop-filter: blur(14px) saturate(160%);
            display: none; align-items: flex-start; justify-content: center;
            padding-top: 15vh; opacity: 0; transition: opacity 0.18s ease-out;
        `;

        const modal = document.createElement('div');
        modal.id = 'eduvis-cmd-palette-modal';
        modal.style.cssText = `
            width: 90%; max-width: 620px;
            background: rgba(22, 27, 34, 0.88);
            border: 1px solid rgba(255, 255, 255, 0.14);
            border-radius: 16px;
            box-shadow: 0 24px 60px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.06);
            overflow: hidden; display: flex; flex-direction: column;
            color: #f0f6fc; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            transform: scale(0.97); transition: transform 0.18s cubic-bezier(0.16, 1, 0.3, 1);
        `;

        modal.innerHTML = `
            <div style="display:flex; align-items:center; gap:10px; padding:14px 18px; border-bottom:1px solid rgba(255,255,255,0.08); background:rgba(255,255,255,0.03);">
                <span style="font-size:16px; opacity:0.6;">⌘</span>
                <input id="eduvis-cmd-input" type="text" placeholder="Ketik perintah atau cari workspace... (Esc untuk batal)" style="
                    flex:1; background:transparent; border:none; outline:none; font-size:14px; color:#fff;
                    font-family:inherit;
                " autofocus />
                <span style="font-size:10px; padding:3px 7px; border-radius:6px; background:rgba(255,255,255,0.08); color:#8b949e; font-weight:600;">ESC</span>
            </div>
            <div id="eduvis-cmd-list" style="max-height:360px; overflow-y:auto; padding:8px 6px;"></div>
            <div style="display:flex; justify-content:space-between; align-items:center; padding:9px 16px; border-top:1px solid rgba(255,255,255,0.06); font-size:11px; color:#8b949e; background:rgba(0,0,0,0.2);">
                <div>Gunakan <kbd>↑</kbd> <kbd>↓</kbd> untuk memilih, <kbd>↵</kbd> untuk eksekusi</div>
                <div><b>EduVis Pro Suite</b></div>
            </div>
        `;

        backdrop.appendChild(modal);
        document.body.appendChild(backdrop);

        const actions = [
            { id: "new-chat", icon: "💬", title: "Percakapan Baru", cat: "Aksi", run: () => { if (typeof clearHistory === 'function') clearHistory(); else window.location.reload(); } },
            { id: "ws-eduvis", icon: "🎨", title: "Workspace EduVis AI Canvas", cat: "Navigasi", run: () => { window.location.href = "eduVis.html"; } },
            { id: "ws-pglite", icon: "🐘", title: "PGlite Vector SQL (On-Device RAG)", cat: "Navigasi", run: () => { window.location.href = "mesin-pglite-rag.html"; } },
            { id: "ws-vision", icon: "📄", title: "Vision Ulti (Analisis Dokumen & PDF)", cat: "Navigasi", run: () => { window.location.href = "vision_ulti.html"; } },
            { id: "ws-agent", icon: "🤖", title: "Agen AI Otonom", cat: "Navigasi", run: () => { window.location.href = "agen-ai-otonom.html"; } },
            { id: "ws-liquid", icon: "💧", title: "Liquid Chatbot", cat: "Navigasi", run: () => { window.location.href = "liquid_chatbot.html"; } },
            { id: "ws-live", icon: "🎙️", title: "EduVis Live (Duplex Voice Audio)", cat: "Navigasi", run: () => { window.location.href = "gemini_live.html"; } },
            { id: "settings-ai", icon: "⚙️", title: "Buka Pengaturan AI & Pusat Model", cat: "Pengaturan", run: () => { if (typeof openAISettingsModal === 'function') openAISettingsModal(); } },
            { id: "session-mgmt", icon: "💾", title: "Manajemen & Ekspor Sesi JSON", cat: "Sesi", run: () => { if (typeof openSessionManagementModal === 'function') openSessionManagementModal(); } },
            { id: "toggle-inspector", icon: "📐", title: "Toggle Inspector Kanan", cat: "Tampilan", run: () => { toggleInspector(); } },
            { id: "toggle-sidebar", icon: "📑", title: "Toggle Sidebar", cat: "Tampilan", run: () => { toggleSidebar(); } },
            { id: "clear-cache", icon: "🧹", title: "Segarkan Halaman & Bersihkan Cache", cat: "Sistem", run: () => { window.location.reload(); } }
        ];

        let selectedIdx = 0;
        let filteredActions = [...actions];

        function renderList() {
            const listEl = document.getElementById('eduvis-cmd-list');
            if (!listEl) return;
            if (filteredActions.length === 0) {
                listEl.innerHTML = `<div style="padding:16px; text-align:center; color:#8b949e; font-size:12px;">Tidak ada perintah yang cocok.</div>`;
                return;
            }
            listEl.innerHTML = filteredActions.map((act, idx) => `
                <div class="cmd-item" data-idx="${idx}" style="
                    display:flex; align-items:center; justify-content:space-between;
                    padding:9px 12px; border-radius:8px; cursor:pointer; margin-bottom:2px;
                    background: ${idx === selectedIdx ? 'rgba(56, 189, 248, 0.16)' : 'transparent'};
                    border: 1px solid ${idx === selectedIdx ? 'rgba(56, 189, 248, 0.35)' : 'transparent'};
                    transition: background 0.12s;
                ">
                    <div style="display:flex; align-items:center; gap:10px;">
                        <span style="font-size:16px;">${act.icon}</span>
                        <span style="font-size:13px; font-weight:${idx === selectedIdx ? '600' : '400'}; color:#fff;">${act.title}</span>
                    </div>
                    <span style="font-size:10px; padding:2px 8px; border-radius:6px; background:rgba(255,255,255,0.06); color:#8b949e;">${act.cat}</span>
                </div>
            `).join('');

            listEl.querySelectorAll('.cmd-item').forEach(el => {
                el.addEventListener('mouseenter', () => {
                    selectedIdx = parseInt(el.getAttribute('data-idx') || '0', 10);
                    renderList();
                });
                el.addEventListener('click', () => {
                    executeSelected();
                });
            });
        }

        function executeSelected() {
            const act = filteredActions[selectedIdx];
            closePalette();
            if (act && typeof act.run === 'function') {
                setTimeout(() => act.run(), 60);
            }
        }

        function openPalette() {
            backdrop.style.display = 'flex';
            requestAnimationFrame(() => {
                backdrop.style.opacity = '1';
                modal.style.transform = 'scale(1)';
            });
            const input = document.getElementById('eduvis-cmd-input');
            if (input) {
                input.value = '';
                filteredActions = [...actions];
                selectedIdx = 0;
                renderList();
                input.focus();
            }
        }

        function closePalette() {
            backdrop.style.opacity = '0';
            modal.style.transform = 'scale(0.97)';
            setTimeout(() => { backdrop.style.display = 'none'; }, 180);
        }

        const inputEl = document.getElementById('eduvis-cmd-input');
        inputEl?.addEventListener('input', (e) => {
            const q = (e.target.value || '').toLowerCase().trim();
            filteredActions = actions.filter(a => a.title.toLowerCase().includes(q) || a.cat.toLowerCase().includes(q));
            selectedIdx = 0;
            renderList();
        });

        inputEl?.addEventListener('keydown', (e) => {
            if (e.key === 'ArrowDown') {
                e.preventDefault();
                selectedIdx = (selectedIdx + 1) % Math.max(1, filteredActions.length);
                renderList();
            } else if (e.key === 'ArrowUp') {
                e.preventDefault();
                selectedIdx = (selectedIdx - 1 + filteredActions.length) % Math.max(1, filteredActions.length);
                renderList();
            } else if (e.key === 'Enter') {
                e.preventDefault();
                executeSelected();
            } else if (e.key === 'Escape') {
                e.preventDefault();
                closePalette();
            }
        });

        backdrop.addEventListener('click', (e) => {
            if (e.target === backdrop) closePalette();
        });

        window.EduVisCommandPalette = { open: openPalette, close: closePalette };
    }

    /**
     * Memasangkan event listener global untuk keyboard shortcut Apple:
     * - Cmd + K: Spotlight Command Palette
     * - Cmd + Option + S: Toggle Sidebar
     * - Cmd + Option + I: Toggle Inspector Panel
     * - Esc: Tutup Inspector jika sedang terbuka
     */
    function setupKeyboardShortcuts() {
        if (typeof window === 'undefined') return;

        window.addEventListener('keydown', (e) => {
            // Cmd + K (Spotlight Command Palette)
            if ((e.metaKey || e.ctrlKey) && (e.key === 'k' || e.key === 'K')) {
                e.preventDefault();
                if (window.EduVisCommandPalette) {
                    window.EduVisCommandPalette.open();
                }
                return;
            }
            // Cmd + Option + S (Toggle Sidebar)
            if (e.metaKey && e.altKey && (e.key === 's' || e.key === 'S')) {
                e.preventDefault();
                toggleSidebar();
            }
            // Cmd + Option + I (Toggle Inspector)
            if (e.metaKey && e.altKey && (e.key === 'i' || e.key === 'I')) {
                e.preventDefault();
                toggleInspector();
            }
            // Esc (Close Inspector jika terbuka)
            if (e.key === 'Escape' && !splitState.isRightCollapsed) {
                closeInspector();
            }
        });

        initCommandPalette();

        // Auto-load EduVis i18n Engine jika belum termuat
        if (typeof window !== 'undefined' && !window.EduVisi18n && typeof document !== 'undefined') {
            const i18nScript = document.createElement('script');
            i18nScript.src = 'nano_asset/assets/js/eduvis-i18n.js';
            i18nScript.async = true;
            (document.head || document.documentElement).appendChild(i18nScript);
        }
    }

    const MacSplitView = {
        splitState,
        initSearchField,
        toggleSidebar,
        ensureInspectorPane,
        openInspector,
        closeInspector,
        toggleInspector,
        setInspectorTab,
        updateParametersView,
        setupKeyboardShortcuts
    };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = MacSplitView;
    }
    if (typeof window !== 'undefined') {
        window.MacSplitView = MacSplitView;
        setupKeyboardShortcuts();
    }
})();
