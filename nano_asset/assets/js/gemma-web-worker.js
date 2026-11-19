/**
 * Gemma Dedicated Web Worker Engine
 * Mengisolasi komputasi vektor berat, pemrosesan n-gram, dan parsing teks dari Main Thread
 * Menjamin antarmuka UI tetap mulus pada 60 FPS bebas jank.
 */

self.onmessage = function (event) {
    const { id, type, payload } = event.data || {};

    try {
        switch (type) {
            case 'HYBRID_VECTOR_SEARCH': {
                const { queryEmbedding, chunks, queryText, topK = 5 } = payload;
                const results = executeHybridSearch(queryEmbedding, chunks, queryText, topK);
                self.postMessage({ id, type, status: 'success', result: results });
                break;
            }

            case 'BATCH_COSINE_SIMILARITY': {
                const { queryEmbedding, embeddings } = payload;
                const scores = embeddings.map(emb => cosineSimilarity(queryEmbedding, emb));
                self.postMessage({ id, type, status: 'success', result: scores });
                break;
            }

            case 'SMART_CHUNK_TEXT': {
                const { text, chunkSize = 1000, overlap = 200 } = payload;
                const chunks = executeSmartChunking(text, chunkSize, overlap);
                self.postMessage({ id, type, status: 'success', result: chunks });
                break;
            }

            case 'PING': {
                self.postMessage({ id, type, status: 'success', result: 'PONG' });
                break;
            }

            default:
                self.postMessage({ id, type, status: 'error', error: `Unknown task type: ${type}` });
        }
    } catch (err) {
        self.postMessage({ id, type, status: 'error', error: err.message || String(err) });
    }
};

function cosineSimilarity(vecA, vecB) {
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

function computeKeywordScore(query, text, fileName) {
    if (!query || !text) return 0;
    const queryLower = query.toLowerCase().trim();
    const textLower = text.toLowerCase();
    const fileLower = (fileName || '').toLowerCase();

    let score = 0;
    if (queryLower.length > 3 && textLower.includes(queryLower)) {
        score += 0.45;
    }

    const stopWords = new Set(['yang', 'dan', 'di', 'ke', 'dari', 'ini', 'itu', 'untuk', 'pada', 'adalah', 'the', 'and', 'in', 'of', 'to', 'is', 'for', 'with', 'on', 'at', 'a', 'an']);
    const tokens = queryLower.split(/[\s,.;:?!()\[\]{}"'\/\\]+/).filter(w => w.length > 1 && !stopWords.has(w));
    if (tokens.length === 0) return Math.min(score, 1.0);

    let matches = 0;
    let freqBonus = 0;

    for (const token of tokens) {
        if (textLower.includes(token)) {
            matches++;
            let count = 0, pos = 0;
            while ((pos = textLower.indexOf(token, pos)) !== -1 && count < 5) {
                count++;
                pos += token.length;
            }
            freqBonus += Math.min(count - 1, 4) * 0.04;
        } else if (fileLower.includes(token)) {
            matches += 0.5;
        }
    }

    const tokenRatio = matches / tokens.length;
    score += (tokenRatio * 0.45) + Math.min(freqBonus, 0.2);
    return Math.min(score, 1.0);
}

function executeHybridSearch(queryEmbedding, chunks, queryText, topK) {
    if (!Array.isArray(chunks) || chunks.length === 0) return [];

    const scored = chunks.map(chunk => {
        const vScore = queryEmbedding ? cosineSimilarity(queryEmbedding, chunk.embedding) : 0;
        const kScore = queryText ? computeKeywordScore(queryText, chunk.text, chunk.fileName) : 0;
        const hybrid = queryEmbedding ? (0.65 * vScore) + (0.35 * kScore) : kScore;

        return {
            ...chunk,
            score: hybrid,
            vectorScore: vScore,
            keywordScore: kScore
        };
    });

    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, topK);
}

function executeSmartChunking(text, chunkSize, overlap) {
    if (!text) return [];
    const blockPattern = /(?:\r?\n){2,}|(?=\n#{1,4}\s)|(?=\n(?:Bab|BAB|Pasal|Section)\s)|(?=\n\[Halaman\s+\d+\])/g;
    const rawBlocks = text.split(blockPattern).map(b => b.trim()).filter(Boolean);
    if (rawBlocks.length === 0) return [text];

    const chunks = [];
    let currentChunk = "";

    for (const block of rawBlocks) {
        if (currentChunk.length + block.length > chunkSize && currentChunk.length > 0) {
            chunks.push(currentChunk.trim());
            const words = currentChunk.split(/\s+/);
            const overlapWords = words.slice(-Math.floor(overlap / 5)).join(' ');
            currentChunk = overlapWords + "\n\n" + block;
        } else {
            currentChunk += (currentChunk ? "\n\n" : "") + block;
        }
    }
    if (currentChunk.trim().length > 0) chunks.push(currentChunk.trim());
    return chunks;
}
