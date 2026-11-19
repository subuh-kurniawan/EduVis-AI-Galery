(function () {
    'use strict';

    const ALLOWED_PAGES = new Set([
        '',
        'index.html',
        'utama.html',
        'utamaV2.html',
        'VS.html',
        'claude.html',
        'gemini_live.html',
        'liquid_chatbot.html',
        'eduVis.html',
        'aurora.html',
        'analisis-kode.html',
        'tanya-ai-standalone.html',
        'vision_ulti.html',
        'agen-ai-otonom.html',
        'mesin-pglite-rag.html',
        'ai-liquid-glass.html',
        'gemini_live_futuristik.html',
        'tts_studio_lokal.html',
        'tts-ultimate.html',
        'tts-ultimate3.html'
    ]);

    function renderQr(container, value) {
        if (typeof window.qrcode !== 'function') {
            throw new Error('Generator QR lokal belum tersedia. Muat ulang aplikasi.');
        }
        const code = window.qrcode(0, 'M');
        code.addData(value);
        code.make();
        const size = code.getModuleCount();
        const namespace = 'http://www.w3.org/2000/svg';
        const svg = document.createElementNS(namespace, 'svg');
        const quietZone = 4;
        const extent = size + quietZone * 2;
        svg.setAttribute('viewBox', `0 0 ${extent} ${extent}`);
        svg.setAttribute('role', 'img');
        svg.setAttribute('aria-label', `QR code untuk ${value}`);
        svg.setAttribute('class', 'block w-full h-full');
        const background = document.createElementNS(namespace, 'rect');
        background.setAttribute('width', String(extent));
        background.setAttribute('height', String(extent));
        background.setAttribute('fill', '#fff');
        svg.append(background);

        let pathData = '';
        for (let row = 0; row < size; row += 1) {
            for (let column = 0; column < size; column += 1) {
                if (code.isDark(row, column)) pathData += `M${column + quietZone},${row + quietZone}h1v1h-1z`;
            }
        }
        const path = document.createElementNS(namespace, 'path');
        path.setAttribute('d', pathData);
        path.setAttribute('fill', '#111827');
        svg.append(path);
        container.replaceChildren(svg);
    }

    function injectStyles() {
        if (document.getElementById('lan-qr-styles')) return;
        const style = document.createElement('style');
        style.id = 'lan-qr-styles';
        style.textContent = `
            #lan-qr-modal {
                position: fixed !important;
                inset: 0 !important;
                z-index: 99999 !important;
                display: flex !important;
                align-items: center !important;
                justify-content: center !important;
                padding: 1rem !important;
                background-color: rgba(5, 7, 12, 0.78) !important;
                backdrop-filter: blur(12px) !important;
                -webkit-backdrop-filter: blur(12px) !important;
                font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif !important;
                box-sizing: border-box !important;
                color-scheme: dark !important;
            }
            #lan-qr-modal.hidden {
                display: none !important;
            }
            #lan-qr-modal * {
                box-sizing: border-box !important;
            }
            #lan-qr-modal .lan-qr-card {
                position: relative !important;
                width: 100% !important;
                max-width: 440px !important;
                max-height: 90vh !important;
                overflow-y: auto !important;
                background-color: #131418 !important;
                background-image: linear-gradient(180deg, rgba(255, 255, 255, 0.03) 0%, rgba(255, 255, 255, 0) 100%) !important;
                border: 1px solid rgba(255, 255, 255, 0.12) !important;
                border-radius: 1.5rem !important;
                padding: 1.5rem !important;
                box-shadow: 0 25px 60px -15px rgba(0, 0, 0, 0.85), 0 0 35px rgba(99, 102, 241, 0.12) !important;
                color: #f1f5f9 !important;
                color-scheme: dark !important;
            }
            #lan-qr-modal .lan-qr-header {
                display: flex !important;
                align-items: flex-start !important;
                justify-content: space-between !important;
                gap: 1rem !important;
                margin-bottom: 1.25rem !important;
            }
            #lan-qr-modal #lan-qr-title {
                margin: 0 !important;
                padding: 0 !important;
                font-size: 1.05rem !important;
                font-weight: 700 !important;
                color: #ffffff !important;
                line-height: 1.3 !important;
                letter-spacing: -0.01em !important;
            }
            #lan-qr-modal .lan-qr-subtitle {
                margin: 0.35rem 0 0 0 !important;
                padding: 0 !important;
                font-size: 0.775rem !important;
                color: #94a3b8 !important;
                line-height: 1.4 !important;
            }
            #lan-qr-modal #lan-qr-close {
                display: inline-flex !important;
                align-items: center !important;
                justify-content: center !important;
                width: 2.25rem !important;
                height: 2.25rem !important;
                min-width: 2.25rem !important;
                min-height: 2.25rem !important;
                padding: 0 !important;
                margin: -0.25rem -0.25rem 0 0 !important;
                background: transparent !important;
                border: 1px solid transparent !important;
                border-radius: 0.75rem !important;
                color: #94a3b8 !important;
                font-size: 1.25rem !important;
                cursor: pointer !important;
                transition: all 0.15s ease !important;
            }
            #lan-qr-modal #lan-qr-close:hover {
                background: rgba(255, 255, 255, 0.08) !important;
                color: #ffffff !important;
                border-color: rgba(255, 255, 255, 0.1) !important;
            }
            #lan-qr-modal .lan-qr-body-box {
                display: flex !important;
                flex-direction: column !important;
                align-items: center !important;
                gap: 1rem !important;
                padding: 1.25rem !important;
                background: rgba(0, 0, 0, 0.3) !important;
                border: 1px solid rgba(255, 255, 255, 0.08) !important;
                border-radius: 1.25rem !important;
            }
            #lan-qr-modal #lan-qr-image {
                width: 14rem !important;
                height: 14rem !important;
                max-width: 100% !important;
                background: #ffffff !important;
                border-radius: 0.75rem !important;
                padding: 0.65rem !important;
                box-shadow: 0 8px 24px rgba(0, 0, 0, 0.35) !important;
                display: flex !important;
                align-items: center !important;
                justify-content: center !important;
            }
            #lan-qr-modal .lan-qr-field {
                width: 100% !important;
                display: flex !important;
                flex-direction: column !important;
                gap: 0.4rem !important;
                font-size: 0.75rem !important;
                font-weight: 600 !important;
                color: #cbd5e1 !important;
                text-align: left !important;
            }
            #lan-qr-modal #lan-qr-address-select {
                width: 100% !important;
                min-height: 42px !important;
                height: 42px !important;
                padding: 0 0.85rem !important;
                background-color: #1a1b22 !important;
                color: #f8fafc !important;
                border: 1px solid rgba(255, 255, 255, 0.14) !important;
                border-radius: 0.75rem !important;
                font-size: 0.8rem !important;
                font-family: ui-monospace, SFMono-Regular, Menlo, monospace !important;
                outline: none !important;
                cursor: pointer !important;
                color-scheme: dark !important;
                transition: border-color 0.15s ease, box-shadow 0.15s ease !important;
            }
            #lan-qr-modal #lan-qr-address-select:focus {
                border-color: #38bdf8 !important;
                box-shadow: 0 0 0 2px rgba(56, 189, 248, 0.25) !important;
            }
            #lan-qr-modal #lan-qr-address-select option {
                background-color: #181920 !important;
                color: #ffffff !important;
                padding: 0.5rem !important;
            }
            #lan-qr-modal .lan-qr-btn-group {
                display: flex !important;
                width: 100% !important;
                gap: 0.5rem !important;
            }
            #lan-qr-modal #lan-qr-copy {
                flex: 1 !important;
                min-height: 42px !important;
                height: 42px !important;
                display: inline-flex !important;
                align-items: center !important;
                justify-content: center !important;
                padding: 0 0.75rem !important;
                background: rgba(255, 255, 255, 0.08) !important;
                color: #f8fafc !important;
                border: 1px solid rgba(255, 255, 255, 0.14) !important;
                border-radius: 0.75rem !important;
                font-size: 0.775rem !important;
                font-weight: 600 !important;
                cursor: pointer !important;
                transition: all 0.15s ease !important;
                text-decoration: none !important;
            }
            #lan-qr-modal #lan-qr-copy:hover {
                background: rgba(255, 255, 255, 0.15) !important;
                color: #ffffff !important;
                border-color: rgba(255, 255, 255, 0.22) !important;
            }
            #lan-qr-modal #lan-qr-ca {
                flex: 1 !important;
                min-height: 42px !important;
                height: 42px !important;
                display: inline-flex !important;
                align-items: center !important;
                justify-content: center !important;
                padding: 0 0.75rem !important;
                background: rgba(14, 165, 233, 0.12) !important;
                color: #38bdf8 !important;
                border: 1px solid rgba(56, 189, 248, 0.35) !important;
                border-radius: 0.75rem !important;
                font-size: 0.775rem !important;
                font-weight: 600 !important;
                cursor: pointer !important;
                transition: all 0.15s ease !important;
                text-decoration: none !important;
                text-align: center !important;
            }
            #lan-qr-modal #lan-qr-ca:hover {
                background: rgba(14, 165, 233, 0.22) !important;
                color: #bae6fd !important;
                border-color: rgba(56, 189, 248, 0.5) !important;
            }
            #lan-qr-modal #lan-qr-status {
                margin: 0.85rem 0 0 0 !important;
                padding: 0 !important;
                text-align: center !important;
                font-size: 0.75rem !important;
                line-height: 1.4 !important;
                word-break: break-all !important;
                color: #94a3b8 !important;
                font-family: ui-monospace, SFMono-Regular, Menlo, monospace !important;
            }
            #lan-qr-modal #lan-qr-status.status-url {
                color: #93c5fd !important;
            }
            #lan-qr-modal #lan-qr-status.status-success {
                color: #34d399 !important;
            }
            #lan-qr-modal #lan-qr-status.status-error {
                color: #f87171 !important;
            }
            #lan-qr-modal .lan-qr-notice {
                margin: 0.85rem 0 0 0 !important;
                padding: 0.65rem 0.85rem !important;
                background: rgba(245, 158, 11, 0.08) !important;
                border: 1px solid rgba(245, 158, 11, 0.2) !important;
                border-radius: 0.75rem !important;
                font-size: 0.72rem !important;
                line-height: 1.45 !important;
                color: #fde68a !important;
                text-align: left !important;
            }
            #lan-qr-open {
                min-height: 38px !important;
                min-width: 38px !important;
                display: inline-flex !important;
                align-items: center !important;
                justify-content: center !important;
                gap: 0.45rem !important;
                border-radius: 0.75rem !important;
                border: 1px solid rgba(255, 255, 255, 0.12) !important;
                background: rgba(255, 255, 255, 0.05) !important;
                padding: 0 0.65rem !important;
                color: #cbd5e1 !important;
                font-size: 0.75rem !important;
                cursor: pointer !important;
                transition: all 0.15s ease !important;
                font-family: inherit !important;
            }
            #lan-qr-open:hover {
                background: rgba(255, 255, 255, 0.1) !important;
                color: #ffffff !important;
            }
            body.light-theme #lan-qr-open {
                background: rgba(0, 0, 0, 0.04) !important;
                border-color: rgba(0, 0, 0, 0.1) !important;
                color: #1e293b !important;
            }
            body.light-theme #lan-qr-open:hover {
                background: rgba(0, 0, 0, 0.08) !important;
                border-color: rgba(0, 0, 0, 0.18) !important;
                color: #0f172a !important;
            }
        `;
        document.head.append(style);
    }

    function createButton() {
        const header = document.querySelector('header');
        if (!header || document.getElementById('lan-qr-open')) return;
        injectStyles();
        const buttonGroup = [...header.children].reverse().find(element => element.classList.contains('flex')) || header;

        const button = document.createElement('button');
        button.id = 'lan-qr-open';
        button.type = 'button';
        button.setAttribute('aria-label', 'Tampilkan QR code untuk perangkat lain');
        button.title = 'Buka di perangkat lain';
        button.innerHTML = '<svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h3v3h-3zM20 14v3M14 20h3M20 20h1"/></svg><span class="hidden sm:inline">Perangkat lain</span>';
        button.addEventListener('click', openModal);
        buttonGroup.append(button);
    }

    function createModal() {
        if (document.getElementById('lan-qr-modal')) return;
        injectStyles();
        const overlay = document.createElement('div');
        overlay.id = 'lan-qr-modal';
        overlay.className = 'hidden';
        overlay.setAttribute('role', 'dialog');
        overlay.setAttribute('aria-modal', 'true');
        overlay.setAttribute('aria-labelledby', 'lan-qr-title');
        overlay.innerHTML = `
            <section class="lan-qr-card">
                <div class="lan-qr-header">
                    <div>
                        <h2 id="lan-qr-title">Buka di perangkat lain</h2>
                        <p class="lan-qr-subtitle">Pindai QR code dari perangkat yang terhubung ke Wi-Fi yang sama.</p>
                    </div>
                    <button id="lan-qr-close" type="button" aria-label="Tutup modal">✕</button>
                </div>
                <div class="lan-qr-body-box">
                    <div id="lan-qr-image"></div>
                    <label class="lan-qr-field" for="lan-qr-address-select">
                        <span>Alamat jaringan</span>
                        <select id="lan-qr-address-select"></select>
                    </label>
                    <div class="lan-qr-btn-group">
                        <button id="lan-qr-copy" type="button">Salin tautan</button>
                        <a id="lan-qr-ca" target="_blank" rel="noopener">Sertifikat perangkat</a>
                    </div>
                </div>
                <p id="lan-qr-status" role="status" aria-live="polite">Mendeteksi alamat jaringan...</p>
                <div class="lan-qr-notice">
                    Perangkat lain mungkin perlu mempercayai sertifikat lokal sebelum membuka halaman. Gunakan hanya di jaringan tepercaya.
                </div>
            </section>`;
        overlay.addEventListener('click', event => {
            if (event.target === overlay) closeModal();
        });
        overlay.querySelector('#lan-qr-close').addEventListener('click', closeModal);
        overlay.querySelector('#lan-qr-address-select').addEventListener('change', updateQr);
        overlay.querySelector('#lan-qr-copy').addEventListener('click', copyAddress);
        document.body.append(overlay);
    }

    let networkUrls = [];

    function selectedAddress() {
        const select = document.getElementById('lan-qr-address-select');
        const entry = networkUrls[Number(select.value)];
        return entry || null;
    }

    function updateQr() {
        const entry = selectedAddress();
        const image = document.getElementById('lan-qr-image');
        const status = document.getElementById('lan-qr-status');
        if (!entry) return;
        document.getElementById('lan-qr-ca').href = `https://${entry.address}:1234/api/lan-ca`;
        try {
            renderQr(image, entry.url);
            status.textContent = entry.url;
            status.className = 'status-url';
        } catch (error) {
            image.replaceChildren();
            status.textContent = error.message;
            status.className = 'status-error';
        }
    }

    async function ensureQrCodeLib() {
        if (typeof window.qrcode === 'function') return true;
        return new Promise(resolve => {
            const script = document.createElement('script');
            script.src = 'nano_asset/assets/js/qrcode-generator.js';
            script.onload = () => resolve(typeof window.qrcode === 'function');
            script.onerror = () => resolve(false);
            document.head.appendChild(script);
        });
    }

    async function loadNetworkAddresses() {
        const select = document.getElementById('lan-qr-address-select');
        const status = document.getElementById('lan-qr-status');
        const image = document.getElementById('lan-qr-image');
        select.replaceChildren();
        image.replaceChildren();
        status.textContent = 'Mendeteksi alamat jaringan...';
        status.className = '';

        try {
            await ensureQrCodeLib();
            const response = await fetch('/api/network-info', { cache: 'no-store' });
            if (!response.ok) throw new Error(`Server jaringan merespons HTTP ${response.status}.`);
            const networkInfo = await response.json();
            const currentPage = location.pathname.split('/').pop();
            if (!ALLOWED_PAGES.has(currentPage)) throw new Error('Halaman ini tidak tersedia untuk akses jaringan.');
            if (!Array.isArray(networkInfo.addresses)) throw new Error('Server tidak memberikan daftar alamat jaringan.');

            const model = new URLSearchParams(location.search).get('model');
            const targetPage = (currentPage && currentPage !== '') ? currentPage : 'index.html';
            networkUrls = networkInfo.addresses
                .filter(address => /^(?:\d{1,3}\.){3}\d{1,3}$/.test(address))
                .map(address => {
                    const url = new URL(`https://${address}:1234/${targetPage}`);
                    if (model) url.searchParams.set('model', model);
                    return { address, url: url.href };
                });
            if (networkUrls.length === 0) throw new Error('Alamat Wi-Fi tidak terdeteksi. Pastikan perangkat ini terhubung ke jaringan lokal.');

            for (const [index, entry] of networkUrls.entries()) {
                const option = document.createElement('option');
                option.value = String(index);
                option.textContent = `https://${entry.address}:1234`;
                select.append(option);
            }
            updateQr();
        } catch (error) {
            networkUrls = [];
            status.textContent = error instanceof TypeError
                ? 'Tidak dapat mengambil alamat jaringan. Buka aplikasi melalui launcher lokal dan coba lagi.'
                : error.message;
            status.className = 'status-error';
            select.disabled = true;
            image.replaceChildren();
        }
    }

    async function copyAddress() {
        const entry = selectedAddress();
        const status = document.getElementById('lan-qr-status');
        if (!entry) return;
        try {
            await navigator.clipboard.writeText(entry.url);
            status.textContent = 'Tautan berhasil disalin.';
            status.className = 'status-success';
        } catch (error) {
            status.textContent = `Gagal menyalin tautan: ${error.message}`;
            status.className = 'status-error';
        }
    }

    function closeModal() {
        const modal = document.getElementById('lan-qr-modal');
        if (modal) {
            modal.classList.add('hidden');
        }
        document.removeEventListener('keydown', handleKeydown);
    }

    function handleKeydown(event) {
        if (event.key === 'Escape') closeModal();
    }

    function openModal() {
        createModal();
        const modal = document.getElementById('lan-qr-modal');
        const select = document.getElementById('lan-qr-address-select');
        select.disabled = false;
        modal.classList.remove('hidden');
        document.addEventListener('keydown', handleKeydown);
        document.getElementById('lan-qr-close').focus();
        loadNetworkAddresses();
    }

    window.GemmaLanQR = {
        openModal,
        closeModal
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            createModal();
            createButton();
        }, { once: true });
    } else {
        createModal();
        createButton();
    }
})();
