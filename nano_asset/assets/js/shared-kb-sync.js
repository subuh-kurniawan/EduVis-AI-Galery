/**
 * Shared Knowledge Base Sync & Vector Bridge (SQLite Host <-> Browser IndexedDB)
 * Menyinkronkan dokumen & vector embeddings antara server host (/api/kb/*) dan
 * IndexedDB lokal (kb_files, kb_chunks) agar 1 Knowledge Base dapat diakses
 * lintas ruang kerja dan oleh seluruh klien jaringan LAN.
 */

(function (root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory();
    } else {
        root.GemmaSharedKB = factory();
    }
})(typeof self !== 'undefined' ? self : this, function () {
    'use strict';

    async function fetchSnapshot(fetchImpl) {
        const fn = fetchImpl || (typeof fetch === 'function' ? fetch : null);
        if (!fn) return { files: [], chunks: [] };
        try {
            const res = await fn('/api/kb/snapshot', { method: 'GET', headers: { Accept: 'application/json' } });
            if (!res.ok) return { files: [], chunks: [] };
            const data = await res.json();
            return {
                files: Array.isArray(data.files) ? data.files : [],
                chunks: Array.isArray(data.chunks) ? data.chunks : []
            };
        } catch (_) {
            return { files: [], chunks: [] };
        }
    }

    async function ingestToServer(docPayload, fetchImpl) {
        const fn = fetchImpl || (typeof fetch === 'function' ? fetch : null);
        if (!fn || !docPayload || !docPayload.id) return null;
        try {
            const res = await fn('/api/kb/ingest', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(docPayload)
            });
            if (!res.ok) return null;
            return await res.json();
        } catch (_) {
            return null;
        }
    }

    async function deleteFromServer(fileId, fetchImpl) {
        const fn = fetchImpl || (typeof fetch === 'function' ? fetch : null);
        if (!fn || !fileId) return null;
        try {
            const res = await fn('/api/kb/delete', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ id: fileId })
            });
            if (!res.ok) return null;
            return await res.json();
        } catch (_) {
            return null;
        }
    }

    async function searchServer(query, embedding = null, topK = 4, minScore = 0.35, fetchImpl = null) {
        const fn = fetchImpl || (typeof fetch === 'function' ? fetch : null);
        if (!fn) return [];
        try {
            const res = await fn('/api/kb/search', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    query: String(query || ''),
                    embedding: Array.isArray(embedding) ? embedding : null,
                    top_k: topK,
                    min_score: minScore
                })
            });
            if (!res.ok) return [];
            const data = await res.json();
            return Array.isArray(data.results) ? data.results : [];
        } catch (_) {
            return [];
        }
    }

    async function embedViaServer(input, model = 'auto', fetchImpl = null) {
        const fn = fetchImpl || (typeof fetch === 'function' ? fetch : null);
        if (!fn) return null;
        const text = Array.isArray(input) ? input.join('\n') : String(input || '');
        if (!text.trim()) return null;
        try {
            const res = await fn('/v1/embeddings', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    model: model || 'auto',
                    input: text
                })
            });
            if (!res.ok) return null;
            const data = await res.json();
            if (data && Array.isArray(data.data) && data.data[0] && Array.isArray(data.data[0].embedding)) {
                return data.data[0].embedding;
            }
            return null;
        } catch (_) {
            return null;
        }
    }

    function readStoreAll(db, storeName) {
        return new Promise((resolve) => {
            try {
                const tx = db.transaction(storeName, 'readonly');
                const req = tx.objectStore(storeName).getAll();
                req.onsuccess = (e) => resolve(Array.isArray(e.target.result) ? e.target.result : []);
                req.onerror = () => resolve([]);
            } catch (_) {
                resolve([]);
            }
        });
    }

    function putRecords(db, storeName, records) {
        return new Promise((resolve) => {
            if (!records || !records.length) {
                resolve();
                return;
            }
            try {
                const tx = db.transaction(storeName, 'readwrite');
                const store = tx.objectStore(storeName);
                for (const rec of records) {
                    store.put(rec);
                }
                tx.oncomplete = () => resolve();
                tx.onerror = () => resolve();
            } catch (_) {
                resolve();
            }
        });
    }

    async function syncIndexedDB(db, fetchImpl) {
        if (!db || !db.objectStoreNames) return { pulled: 0, pushed: 0 };
        if (!db.objectStoreNames.contains('kb_files') || !db.objectStoreNames.contains('kb_chunks')) {
            return { pulled: 0, pushed: 0 };
        }

        const [localFiles, localChunks, serverSnapshot] = await Promise.all([
            readStoreAll(db, 'kb_files'),
            readStoreAll(db, 'kb_chunks'),
            fetchSnapshot(fetchImpl)
        ]);

        const localFileIds = new Set(localFiles.map(f => f.id));
        const serverFileIds = new Set(serverSnapshot.files.map(f => f.id));

        // 1. Tarik dokumen dari server SQLite yang belum ada di IndexedDB lokal
        const missingLocalFiles = serverSnapshot.files.filter(f => !localFileIds.has(f.id));
        const missingLocalFileIds = new Set(missingLocalFiles.map(f => f.id));
        const missingLocalChunks = serverSnapshot.chunks.filter(c => missingLocalFileIds.has(c.fileId));

        if (missingLocalFiles.length > 0) {
            await putRecords(db, 'kb_files', missingLocalFiles);
            await putRecords(db, 'kb_chunks', missingLocalChunks);
        }

        // 2. Dorong dokumen dari IndexedDB lokal yang belum ada di server SQLite
        let pushed = 0;
        for (const lf of localFiles) {
            if (!serverFileIds.has(lf.id)) {
                const chunksForFile = localChunks
                    .filter(c => c.fileId === lf.id)
                    .map(c => ({ id: c.id, text: c.text, embedding: c.embedding || [] }));
                const ok = await ingestToServer({
                    id: lf.id,
                    name: lf.name,
                    collection: lf.collection || 'Umum',
                    size: lf.size || 0,
                    timestamp: lf.timestamp || Date.now(),
                    chunks: chunksForFile
                }, fetchImpl);
                if (ok) pushed++;
            }
        }

        if (missingLocalFiles.length > 0 && typeof window !== 'undefined' && typeof window.renderKBList === 'function') {
            try { window.renderKBList(); } catch (_) {}
        }

        return { pulled: missingLocalFiles.length, pushed };
    }

    function installBrowserHooks() {
        if (typeof window === 'undefined' || typeof document === 'undefined') return;

        // Sinkronisasi berkala begitu variabel global `db` (IndexedDB) siap di halaman chat
        let syncStarted = false;
        const tryAutoSync = () => {
            if (syncStarted) return;
            const pageDb = window.db;
            if (pageDb && pageDb.objectStoreNames && pageDb.objectStoreNames.contains('kb_files')) {
                syncStarted = true;
                syncIndexedDB(pageDb).catch(() => {});
            }
        };

        document.addEventListener('DOMContentLoaded', () => {
            setTimeout(tryAutoSync, 900);
            setTimeout(tryAutoSync, 3000);
        });

        // Bungkus deleteKBFile agar penghapusan juga menghapus dari SQLite terpusat
        window.addEventListener('load', () => {
            tryAutoSync();
            if (typeof window.deleteKBFile === 'function' && !window.deleteKBFile.__sharedWrapped) {
                const origDelete = window.deleteKBFile;
                const wrappedDelete = function (fileId) {
                    deleteFromServer(fileId).catch(() => {});
                    return origDelete.apply(this, arguments);
                };
                wrappedDelete.__sharedWrapped = true;
                window.deleteKBFile = wrappedDelete;
            }
            if (typeof window.handleKBFileUpload === 'function' && !window.handleKBFileUpload.__sharedWrapped) {
                const origUpload = window.handleKBFileUpload;
                const wrappedUpload = async function (event) {
                    const result = await origUpload.apply(this, arguments);
                    if (window.db) {
                        await syncIndexedDB(window.db);
                    }
                    return result;
                };
                wrappedUpload.__sharedWrapped = true;
                window.handleKBFileUpload = wrappedUpload;
            }
            if (typeof window.searchKnowledgeBase === 'function' && !window.searchKnowledgeBase.__sharedWrapped) {
                const origSearch = window.searchKnowledgeBase;
                const wrappedSearch = async function (query, topK = 3) {
                    const localHits = await origSearch.apply(this, arguments);
                    if (Array.isArray(localHits) && localHits.length > 0) {
                        return localHits;
                    }
                    let queryEmb = null;
                    if (typeof window.extractEmbedding === 'function') {
                        try { queryEmb = await window.extractEmbedding(query, true); } catch (_) {}
                    }
                    return await searchServer(query, queryEmb, topK, 0.35);
                };
                wrappedSearch.__sharedWrapped = true;
                window.searchKnowledgeBase = wrappedSearch;
            }
        });
    }

    installBrowserHooks();

    return {
        fetchSnapshot,
        ingestToServer,
        deleteFromServer,
        searchServer,
        embedViaServer,
        syncIndexedDB
    };
});
