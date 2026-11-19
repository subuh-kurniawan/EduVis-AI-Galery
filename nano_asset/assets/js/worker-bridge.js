/**
 * Gemma Worker Bridge
 * Jembatan komunikasi asinkron antara Main Thread dan Dedicated Web Worker
 * Dilengkapi dengan fallback sinkron otomatis jika Web Worker tidak didukung.
 */

(() => {
    'use strict';

    let workerInstance = null;
    let messageId = 0;
    const pendingPromises = new Map();

    function getWorkerScriptPath() {
        if (typeof document !== 'undefined' && document.currentScript) {
            const src = document.currentScript.src;
            return src.replace(/worker-bridge\.js$/, 'gemma-web-worker.js');
        }
        return 'nano_asset/assets/js/gemma-web-worker.js';
    }

    function initWorker() {
        if (workerInstance) return workerInstance;
        if (typeof Worker === 'undefined') return null;

        try {
            const scriptUrl = getWorkerScriptPath();
            workerInstance = new Worker(scriptUrl);

            workerInstance.onmessage = function (event) {
                const { id, status, result, error } = event.data || {};
                const resolver = pendingPromises.get(id);
                if (!resolver) return;

                pendingPromises.delete(id);
                if (status === 'success') {
                    resolver.resolve(result);
                } else {
                    resolver.reject(new Error(error || 'Worker task failed'));
                }
            };

            workerInstance.onerror = function (err) {
                console.warn('[GemmaWorkerBridge] Worker error, falling back to main-thread execution:', err);
                workerInstance = null;
            };

            return workerInstance;
        } catch (e) {
            console.warn('[GemmaWorkerBridge] Gagal membuat Web Worker:', e);
            workerInstance = null;
            return null;
        }
    }

    function executeTask(type, payload) {
        const worker = initWorker();
        const id = ++messageId;

        if (worker) {
            return new Promise((resolve, reject) => {
                pendingPromises.set(id, { resolve, reject });
                worker.postMessage({ id, type, payload });
                // Timeout proteksi 10 detik
                setTimeout(() => {
                    if (pendingPromises.has(id)) {
                        pendingPromises.delete(id);
                        reject(new Error(`Worker task ${type} timeout`));
                    }
                }, 10000);
            });
        }

        // Fallback langsung di main thread jika worker tidak aktif
        return Promise.resolve(fallbackExecute(type, payload));
    }

    function fallbackCosine(vecA, vecB) {
        if (!vecA || !vecB || vecA.length !== vecB.length) return 0;
        let dot = 0, normA = 0, normB = 0;
        for (let i = 0; i < vecA.length; i++) {
            dot += vecA[i] * vecB[i];
            normA += vecA[i] * vecA[i];
            normB += vecB[i] * vecB[i];
        }
        if (normA === 0 || normB === 0) return 0;
        return dot / (Math.sqrt(normA) * Math.sqrt(normB));
    }

    function fallbackExecute(type, payload) {
        if (type === 'BATCH_COSINE_SIMILARITY') {
            const { queryEmbedding, embeddings } = payload;
            return embeddings.map(emb => fallbackCosine(queryEmbedding, emb));
        }
        if (type === 'HYBRID_VECTOR_SEARCH') {
            const { queryEmbedding, chunks, topK = 5 } = payload;
            const scored = (chunks || []).map(chunk => ({
                ...chunk,
                score: queryEmbedding ? fallbackCosine(queryEmbedding, chunk.embedding) : 0
            }));
            scored.sort((a, b) => b.score - a.score);
            return scored.slice(0, topK);
        }
        if (type === 'PING') return 'PONG';
        return null;
    }

    const GemmaWorkerBridge = {
        initWorker,
        executeTask,
        searchHybrid: (queryEmbedding, chunks, queryText, topK = 5) =>
            executeTask('HYBRID_VECTOR_SEARCH', { queryEmbedding, chunks, queryText, topK }),
        smartChunk: (text, chunkSize = 1000, overlap = 200) =>
            executeTask('SMART_CHUNK_TEXT', { text, chunkSize, overlap }),
        batchCosine: (queryEmbedding, embeddings) =>
            executeTask('BATCH_COSINE_SIMILARITY', { queryEmbedding, embeddings }),
        ping: () => executeTask('PING', {})
    };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = GemmaWorkerBridge;
    }
    if (typeof window !== 'undefined') {
        window.GemmaWorkerBridge = GemmaWorkerBridge;
    }
})();
