/**
 * Knowledge Base Column View (Apple HIG: Column Views)
 * Navigasi bertingkat ala Finder: Koleksi → Dokumen → Chunk, dengan kolom pratinjau/metadata
 * pada level terdalam. Kolom pertama selalu menampilkan root hierarki.
 */

(() => {
    'use strict';

    function escapeHtml(str) {
        return String(str ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }

    /**
     * Membangun pohon dari daftar dokumen datar.
     * Dokumen: { id, title, collection, chunks: [string], size, createdAt }
     */
    function buildTree(documents = []) {
        const collections = new Map();
        for (const doc of documents) {
            const name = doc.collection || 'Tanpa Koleksi';
            if (!collections.has(name)) collections.set(name, []);
            collections.get(name).push(doc);
        }
        return [...collections.entries()]
            .sort((a, b) => a[0].localeCompare(b[0], 'id'))
            .map(([name, docs]) => ({
                id: `col:${name}`,
                type: 'collection',
                label: name,
                meta: { jumlahDokumen: docs.length },
                children: docs
                    .slice()
                    .sort((a, b) => String(a.title).localeCompare(String(b.title), 'id'))
                    .map(doc => ({
                        id: `doc:${doc.id}`,
                        type: 'document',
                        label: doc.title || 'Tanpa Judul',
                        meta: { ukuran: doc.size || 0, dibuat: doc.createdAt || null, jumlahChunk: (doc.chunks || []).length },
                        children: (doc.chunks || []).map((text, i) => ({
                            id: `chunk:${doc.id}:${i}`,
                            type: 'chunk',
                            label: `Chunk ${i + 1}`,
                            preview: String(text),
                            meta: { karakter: String(text).length }
                        }))
                    }))
            }));
    }

    /**
     * Menghitung kolom yang tampil berdasarkan jalur seleksi (array id dari root).
     * Mengembalikan { columns: [items[]], preview: node|null }.
     * Node tanpa anak (chunk) menjadi pratinjau, bukan kolom baru.
     */
    function resolveColumns(tree, selectionPath = []) {
        const columns = [tree];
        let level = tree;
        let preview = null;
        for (const id of selectionPath) {
            const node = (level || []).find(n => n.id === id);
            if (!node) break;
            if (node.children && node.children.length > 0 && node.type !== 'chunk') {
                columns.push(node.children);
                level = node.children;
            } else {
                preview = node;
                break;
            }
        }
        return { columns, preview };
    }

    function iconFor(type) {
        return type === 'collection' ? '📁' : type === 'document' ? '📄' : '🧩';
    }

    function renderColumnViewHTML(tree, selectionPath = []) {
        const { columns, preview } = resolveColumns(tree, selectionPath);
        const cols = columns.map((items, depth) => {
            const rows = items.map(n => {
                const selected = selectionPath[depth] === n.id;
                const hasKids = n.children && n.children.length > 0 && n.type !== 'chunk';
                return `<div class="kcv-row${selected ? ' selected' : ''}" role="option" aria-selected="${selected}" data-depth="${depth}" data-id="${escapeHtml(n.id)}" style="display:flex; align-items:center; gap:8px; padding:6px 10px; font-size:12px; color:${selected ? '#fff' : '#e2e8f0'}; background:${selected ? 'rgba(56,189,248,0.35)' : 'transparent'}; border-radius:8px; margin:1px 4px; cursor:pointer;">
                    <span>${iconFor(n.type)}</span>
                    <span style="flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${escapeHtml(n.label)}</span>
                    ${hasKids ? '<span style="opacity:.5;">›</span>' : ''}
                </div>`;
            }).join('') || '<div style="padding:12px; font-size:11px; color:#94a3b8;">Kosong</div>';
            return `<div class="kcv-column" role="listbox" data-depth="${depth}" style="min-width:200px; width:220px; flex-shrink:0; overflow-y:auto; border-right:1px solid rgba(255,255,255,0.08); padding:6px 0; resize:horizontal;">${rows}</div>`;
        }).join('');

        const previewPane = preview ? `
            <div class="kcv-preview" style="flex:1; min-width:240px; padding:14px; overflow-y:auto;">
                <div style="font-size:13px; font-weight:700; color:#fff; margin-bottom:6px;">${iconFor(preview.type)} ${escapeHtml(preview.label)}</div>
                <div style="font-size:11px; color:#94a3b8; margin-bottom:10px;">${Object.entries(preview.meta || {}).map(([k, v]) => `${escapeHtml(k)}: ${escapeHtml(v)}`).join(' • ')}</div>
                <div style="font-size:12px; color:#e2e8f0; line-height:1.55; white-space:pre-wrap;">${escapeHtml(preview.preview || '')}</div>
            </div>` : '';

        return `<div class="kcv-root apple-liquid-glass" style="display:flex; height:320px; border-radius:16px; overflow-x:auto; overflow-y:hidden; font-family:system-ui, -apple-system, sans-serif;">${cols}${previewPane}</div>`;
    }

    function mount(container, documents) {
        if (!container) return null;
        const tree = buildTree(documents);
        let path = [];
        const render = () => {
            container.innerHTML = renderColumnViewHTML(tree, path);
            container.querySelectorAll('.kcv-row').forEach(row => {
                row.addEventListener('click', () => {
                    const depth = parseInt(row.dataset.depth, 10);
                    path = [...path.slice(0, depth), row.dataset.id];
                    render();
                });
            });
        };
        render();
        return { render, getPath: () => path.slice() };
    }

    const KnowledgeColumnView = { buildTree, resolveColumns, renderColumnViewHTML, mount };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = KnowledgeColumnView;
    }
    if (typeof window !== 'undefined') {
        window.KnowledgeColumnView = KnowledgeColumnView;
    }
})();
