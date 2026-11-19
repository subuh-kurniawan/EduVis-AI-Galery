/**
 * Visual OPFS Storage & Model Cache Manager
 * Mengelola ruang penyimpanan browser (Origin Private File System) untuk model LLM lokal
 * Memungkinkan pemantauan kuota dan penghapusan model 1-klik tanpa DevTools.
 */

(() => {
    'use strict';

    function formatBytes(bytes, decimals = 2) {
        if (!bytes || bytes === 0) return '0 B';
        const k = 1024;
        const dm = decimals < 0 ? 0 : decimals;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
    }

    async function getStorageQuota() {
        if (typeof navigator === 'undefined' || !navigator.storage || !navigator.storage.estimate) {
            return { usage: 0, quota: 0, percent: 0, formattedUsage: '0 B', formattedQuota: '0 B' };
        }
        try {
            const { usage, quota } = await navigator.storage.estimate();
            const percent = quota > 0 ? ((usage / quota) * 100).toFixed(1) : 0;
            return {
                usage,
                quota,
                percent,
                formattedUsage: formatBytes(usage),
                formattedQuota: formatBytes(quota)
            };
        } catch (e) {
            console.warn('[GemmaStorageManager] Gagal membaca kuota storage:', e);
            return { usage: 0, quota: 0, percent: 0, formattedUsage: 'Unknown', formattedQuota: 'Unknown' };
        }
    }

    function detectQuantization(name = '') {
        const m = String(name).match(/(int4|int8|q[2-8]_[a-z0-9_]+|q[2-8]|f16|fp16|bf16|f32)/i);
        return m ? m[1].toUpperCase() : '—';
    }

    const SORT_KEYS = ['name', 'quant', 'size', 'modified'];

    function sortModels(models, key = 'size', direction = 'desc') {
        const k = SORT_KEYS.includes(key) ? key : 'size';
        const dir = direction === 'asc' ? 1 : -1;
        return [...models].sort((a, b) => {
            const av = a[k], bv = b[k];
            if (typeof av === 'string' || typeof bv === 'string') {
                return String(av ?? '').localeCompare(String(bv ?? ''), 'id') * dir;
            }
            return ((av ?? 0) - (bv ?? 0)) * dir;
        });
    }

    function escapeHtml(str) {
        return String(str).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }

    async function listCachedModels() {
        if (typeof navigator === 'undefined' || !navigator.storage || !navigator.storage.getDirectory) {
            return [];
        }
        try {
            const root = await navigator.storage.getDirectory();
            const models = [];
            for await (const [name, handle] of root.entries()) {
                if (handle.kind === 'file' && !name.endsWith('_size')) {
                    const file = await handle.getFile();
                    models.push({
                        name,
                        quant: detectQuantization(name),
                        status: 'Tersimpan',
                        modified: file.lastModified,
                        size: file.size,
                        formattedSize: formatBytes(file.size),
                        lastModified: new Date(file.lastModified).toLocaleString('id-ID')
                    });
                }
            }
            models.sort((a, b) => b.size - a.size);
            return models;
        } catch (e) {
            console.warn('[GemmaStorageManager] Gagal membaca isi OPFS:', e);
            return [];
        }
    }

    async function deleteModel(fileName) {
        if (typeof navigator === 'undefined' || !navigator.storage || !navigator.storage.getDirectory) {
            return false;
        }
        try {
            const root = await navigator.storage.getDirectory();
            await root.removeEntry(fileName);
            try {
                await root.removeEntry(fileName + '_size');
            } catch (_) {}
            return true;
        } catch (e) {
            console.error(`[GemmaStorageManager] Gagal menghapus ${fileName}:`, e);
            return false;
        }
    }

    async function clearAllCache() {
        const models = await listCachedModels();
        for (const m of models) {
            await deleteModel(m.name);
        }
        return true;
    }

    function createStorageModalHTML(quota, models, sort = { key: 'size', direction: 'desc' }) {
        const sorted = sortModels(models, sort.key, sort.direction);
        const arrow = key => sort.key === key ? (sort.direction === 'asc' ? ' ▲' : ' ▼') : '';
        const th = (key, label, align = 'left') =>
            `<th class="opfs-sort-th" data-sort="${key}" role="columnheader" aria-sort="${sort.key === key ? (sort.direction === 'asc' ? 'ascending' : 'descending') : 'none'}" style="text-align:${align}; padding:8px 10px; font-size:11px; font-weight:600; color:#94a3b8; cursor:pointer; user-select:none; white-space:nowrap; position:sticky; top:0; background:rgba(18,24,38,0.95);">${label}${arrow(key)}</th>`;
        const rows = sorted.length > 0
            ? sorted.map(m => `
                <tr class="opfs-model-row" style="border-top:1px solid rgba(255,255,255,0.06);">
                    <td style="padding:9px 10px; font-family:ui-monospace, SFMono-Regular, Menlo, monospace; font-size:12px; color:#f8fafc; max-width:220px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;" title="${escapeHtml(m.name)}">${escapeHtml(m.name)}</td>
                    <td style="padding:9px 10px; font-size:11px; color:#818cf8; font-weight:600;">${escapeHtml(m.quant || '—')}</td>
                    <td style="padding:9px 10px; font-size:12px; color:#38bdf8; font-weight:600; text-align:right; font-variant-numeric:tabular-nums;">${escapeHtml(m.formattedSize)}</td>
                    <td style="padding:9px 10px; font-size:11px; color:#94a3b8; white-space:nowrap; font-variant-numeric:tabular-nums;">${escapeHtml(m.lastModified)}</td>
                    <td style="padding:9px 10px; font-size:11px; color:#34d399;">● ${escapeHtml(m.status || 'Tersimpan')}</td>
                    <td style="padding:9px 10px; text-align:right;">
                        <button class="btn-delete-model" data-name="${escapeHtml(m.name)}" style="background:rgba(239,68,68,0.15); border:1px solid rgba(239,68,68,0.3); color:#f87171; font-size:11px; font-weight:600; padding:4px 10px; border-radius:8px; cursor:pointer;">Hapus</button>
                    </td>
                </tr>`).join('')
            : '<tr><td colspan="6" style="text-align:center; padding:24px; color:#94a3b8; font-size:13px;">Belum ada model yang diunduh ke cache OPFS. Model akan disimpan di sini saat Anda memilihnya.</td></tr>';
        const table = `
            <table class="opfs-model-table" style="width:100%; border-collapse:collapse;">
                <thead><tr>${th('name', 'Nama Model')}${th('quant', 'Kuantisasi')}${th('size', 'Ukuran', 'right')}${th('modified', 'Dimodifikasi')}<th style="padding:8px 10px; font-size:11px; color:#94a3b8; text-align:left; position:sticky; top:0; background:rgba(18,24,38,0.95);">Status</th><th style="position:sticky; top:0; background:rgba(18,24,38,0.95);"></th></tr></thead>
                <tbody>${rows}</tbody>
            </table>`;

        return `
            <div id="opfs-storage-modal-backdrop" class="gemma-opfs-storage-modal" style="position:fixed; inset:0; background:rgba(0,0,0,0.78); backdrop-filter:blur(16px); -webkit-backdrop-filter:blur(16px); display:flex; align-items:center; justify-content:center; z-index:99999; padding:16px;">
                <div class="apple-liquid-glass" style="background:rgba(18,24,38,0.85); backdrop-filter:blur(28px) saturate(200%); -webkit-backdrop-filter:blur(28px) saturate(200%); border:1px solid rgba(255,255,255,0.16); border-radius:24px; width:100%; max-width:820px; box-shadow:inset 0 1.5px 1px 0 rgba(255,255,255,0.35), inset 0 -1.5px 2px 0 rgba(0,0,0,0.25), 0 30px 60px -15px rgba(0,0,0,0.7); overflow:hidden; font-family:system-ui, -apple-system, sans-serif;">
                    <div style="padding:18px 24px; border-bottom:1px solid rgba(255,255,255,0.1); display:flex; align-items:center; justify-content:space-between; background:rgba(255,255,255,0.02);">
                        <div style="display:flex; align-items:center; gap:10px;">
                            <span style="font-size:22px;">📦</span>
                            <div>
                                <h3 style="margin:0; font-size:16px; font-weight:700; color:#fff;">Pengelola Penyimpanan Model Browser (OPFS)</h3>
                                <p style="margin:2px 0 0; font-size:12px; color:#94a3b8;">Origin Private File System — Penyimpanan sandboxed lokal browser</p>
                            </div>
                        </div>
                        <button id="opfs-modal-close-btn" style="background:transparent; border:none; color:#94a3b8; font-size:20px; cursor:pointer; padding:4px 8px; border-radius:8px;">✕</button>
                    </div>

                    <div style="padding:20px 24px;">
                        <!-- Storage Progress -->
                        <div style="background:rgba(255,255,255,0.04); border:1px solid rgba(255,255,255,0.08); border-radius:14px; padding:14px 16px; margin-bottom:20px;">
                            <div style="display:flex; justify-content:space-between; font-size:12px; font-weight:600; color:#e2e8f0; margin-bottom:8px;">
                                <span>Kapasitas Digunakan: <span style="color:#38bdf8;">${quota.formattedUsage}</span> / ${quota.formattedQuota}</span>
                                <span>${quota.percent}%</span>
                            </div>
                            <div style="height:8px; width:100%; background:rgba(255,255,255,0.1); border-radius:99px; overflow:hidden;">
                                <div style="height:100%; width:${Math.min(100, quota.percent)}%; background:linear-gradient(90deg, #38bdf8, #818cf8); border-radius:99px; transition:width 0.4s ease;"></div>
                            </div>
                        </div>

                        <!-- Cached Models List -->
                        <div style="margin-bottom:12px; display:flex; justify-content:space-between; align-items:center;">
                            <h4 style="margin:0; font-size:13px; font-weight:700; text-transform:uppercase; letter-spacing:0.05em; color:#94a3b8;">Model Tersimpan (${sorted.length})</h4>
                            ${models.length > 0 ? '<button id="btn-clear-all-models" style="background:transparent; border:none; color:#f87171; font-size:11px; font-weight:600; cursor:pointer;">Bersihkan Semua</button>' : ''}
                        </div>
                        <div style="max-height:320px; overflow:auto; border:1px solid rgba(255,255,255,0.08); border-radius:12px;">
                            ${table}
                        </div>
                    </div>

                    <div style="padding:14px 24px; background:rgba(255,255,255,0.02); border-top:1px solid rgba(255,255,255,0.1); display:flex; justify-content:flex-end;">
                        <button id="opfs-modal-done-btn" style="background:linear-gradient(135deg, #38bdf8, #6366f1); border:none; color:#fff; font-weight:600; font-size:13px; padding:8px 18px; border-radius:10px; cursor:pointer;">
                            Tutup
                        </button>
                    </div>
                </div>
            </div>
        `;
    }

    async function openStorageModal(sort = { key: 'size', direction: 'desc' }) {
        const quota = await getStorageQuota();
        const models = await listCachedModels();

        const existing = document.getElementById('opfs-storage-modal-backdrop');
        if (existing) existing.remove();

        const html = createStorageModalHTML(quota, models, sort);
        const div = document.createElement('div');
        div.innerHTML = html;
        const modalEl = div.firstElementChild;
        document.body.appendChild(modalEl);

        const close = () => modalEl.remove();
        modalEl.querySelector('#opfs-modal-close-btn')?.addEventListener('click', close);
        modalEl.querySelector('#opfs-modal-done-btn')?.addEventListener('click', close);
        modalEl.addEventListener('click', (e) => {
            if (e.target === modalEl) close();
        });

        // Wire sortable column headers (klik = urutkan, klik ulang = balik arah)
        modalEl.querySelectorAll('.opfs-sort-th').forEach(th => {
            th.addEventListener('click', () => {
                const key = th.dataset.sort;
                const direction = sort.key === key && sort.direction === 'desc' ? 'asc' : 'desc';
                openStorageModal({ key, direction });
            });
        });

        // Wire delete buttons
        modalEl.querySelectorAll('.btn-delete-model').forEach(btn => {
            btn.addEventListener('click', async () => {
                const name = btn.dataset.name;
                btn.disabled = true;
                btn.textContent = 'Menghapus...';
                await deleteModel(name);
                openStorageModal(); // Refresh modal
            });
        });

        modalEl.querySelector('#btn-clear-all-models')?.addEventListener('click', async () => {
            if (confirm('Apakah Anda yakin ingin menghapus seluruh model yang tersimpan di OPFS browser?')) {
                await clearAllCache();
                openStorageModal();
            }
        });
    }

    const GemmaStorageManager = {
        formatBytes,
        getStorageQuota,
        listCachedModels,
        detectQuantization,
        sortModels,
        deleteModel,
        clearAllCache,
        openStorageModal,
        createStorageModalHTML
    };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = GemmaStorageManager;
    }
    if (typeof window !== 'undefined') {
        window.GemmaStorageManager = GemmaStorageManager;
    }
})();
