/**
 * Gemma Multimodal RAG Engine (Text + Vision)
 * Terinspirasi dari EmbeddingGemma-2-Text-Vision (litert-community)
 * Memetakan teks dokumen dan aset visual (diagram, grafik, gambar tabel) ke dalam representasi terpadu.
 */

(() => {
    'use strict';

    const MODEL_ID = 'litert-community/embeddinggemma-2-text-vision-440m-litert-lm';

    /**
     * Membangun representasi metadata visual untuk RAG multimodal.
     */
    function createVisualChunk(options = {}) {
        const {
            id = `vis_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
            fileName = 'Dokumen Visual',
            caption = '',
            page = 1,
            section = '',
            thumbnailUrl = '',
            embedding = null,
            tags = []
        } = options;

        return {
            id,
            kind: 'visual',
            fileName,
            text: caption ? `[Visual / Gambar: ${caption}]` : `[Diagram / Gambar pada ${fileName} Hal. ${page}]`,
            caption,
            page,
            section,
            thumbnailUrl,
            embedding,
            tags,
            timestamp: new Date().toISOString()
        };
    }

    /**
     * Menghasilkan teks prompt multimodal terstruktur dari hasil pencarian RAG (teks + gambar).
     */
    function formatMultimodalContext(searchResults = []) {
        if (!Array.isArray(searchResults) || searchResults.length === 0) {
            return '';
        }

        const formatted = searchResults.map((item, idx) => {
            const isVisual = item.kind === 'visual';
            const pageTag = item.page ? `Hal. ${item.page}` : '';
            const sectionTag = item.section ? `Bagian: ${item.section}` : '';
            const meta = [item.fileName, pageTag, sectionTag, isVisual ? 'Tipe: Diagram/Gambar' : 'Tipe: Teks']
                .filter(Boolean)
                .join(' | ');

            const score = typeof item.score === 'number' ? ` (${(item.score * 100).toFixed(0)}% cocok)` : '';

            if (isVisual) {
                return `[Konteks ${idx + 1} - ${meta}${score}]\nDeskripsi Visual: ${item.caption || item.text}`;
            }
            return `[Konteks ${idx + 1} - ${meta}${score}]\n${item.text}`;
        });

        return [
            '=== REFERENSI KNOWLEDGE BASE MULTIMODAL LOKAL ===',
            'Model dapat merujuk informasi teks maupun deskripsi diagram visual berikut:',
            formatted.join('\n\n---\n\n'),
            '=== AKHIR REFERENSI ==='
        ].join('\n');
    }

    /**
     * Ekstraksi fitur gambar sederhana berbasis thumbnail kanvas (sebelum model vision WASM penuh dimuat).
     */
    async function extractImageFeatures(imgElement) {
        if (!imgElement) return null;
        try {
            const canvas = document.createElement('canvas');
            canvas.width = 16;
            canvas.height = 16;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(imgElement, 0, 0, 16, 16);
            const imgData = ctx.getImageData(0, 0, 16, 16).data;

            // Normalisasi luminance 64-dimensi sederhana untuk fallback
            const features = new Array(64).fill(0);
            for (let i = 0; i < 256; i++) {
                const r = imgData[i * 4] / 255.0;
                const g = imgData[i * 4 + 1] / 255.0;
                const b = imgData[i * 4 + 2] / 255.0;
                const lum = 0.299 * r + 0.587 * g + 0.114 * b;
                features[i % 64] += lum / 4.0;
            }
            return features;
        } catch (e) {
            console.warn('[GemmaMultimodalRAG] Gagal ekstraksi fitur gambar:', e);
            return null;
        }
    }

    const GemmaMultimodalRAG = {
        MODEL_ID,
        createVisualChunk,
        formatMultimodalContext,
        extractImageFeatures
    };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = GemmaMultimodalRAG;
    }
    if (typeof window !== 'undefined') {
        window.GemmaMultimodalRAG = GemmaMultimodalRAG;
    }
})();
