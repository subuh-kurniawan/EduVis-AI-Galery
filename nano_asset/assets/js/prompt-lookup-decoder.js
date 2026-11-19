/**
 * Prompt Lookup Decoder (PLD) for Browser-based LLM Inference
 * Zero-Draft Model Speculative Decoding in JavaScript
 * 
 * Mekanisme:
 * Mencocokkan n-gram teks yang sedang di-generate terhadap teks prompt/konteks input.
 * Jika ditemukan kecocokan n-gram berulang pada prompt, kandidat kelanjutan token
 * diambil langsung dari teks sumber untuk mempercepat streaming hingga 2x-3x.
 */

(() => {
    'use strict';

    function normalizeText(str) {
        return (str || '').replace(/\r\n/g, '\n');
    }

    /**
     * Mencari kelanjutan token spekulatif dari prompt berdasarkan tail n-gram output saat ini.
     * @param {string} promptText - Teks prompt masukan atau konteks dokumen RAG
     * @param {string} generatedText - Teks yang telah berhasil digenerate sejauh ini
     * @param {Object} options - Konfigurasi n-gram dan batas panjang kandidat
     * @returns {string|null} - Kandidat teks spekulatif atau null jika tidak ada kecocokan
     */
    function findCandidates(promptText, generatedText, options = {}) {
        const {
            maxGram = 5,
            minGram = 2,
            maxCandidateLength = 64
        } = options;

        const prompt = normalizeText(promptText);
        const generated = normalizeText(generatedText);

        if (!prompt || !generated || generated.length < minGram) {
            return null;
        }

        // Tokenisasi berbasis kata/whitespace
        const promptTokens = prompt.split(/(\s+)/);
        const genTokens = generated.split(/(\s+)/);

        const genNonEmpty = genTokens.filter(t => t.trim().length > 0);
        if (genNonEmpty.length < minGram) {
            return null;
        }

        // Coba dari n-gram terbesar ke terkecil (greedy matching)
        for (let gramSize = Math.min(maxGram, genNonEmpty.length); gramSize >= minGram; gramSize--) {
            const tailPhrase = genNonEmpty.slice(-gramSize).join(' ').toLowerCase();

            // Cari kemunculan tailPhrase di dalam promptTokens
            for (let i = 0; i <= promptTokens.length - gramSize; i++) {
                const windowTokens = [];
                for (let j = i; j < promptTokens.length && windowTokens.length < gramSize; j++) {
                    if (promptTokens[j].trim().length > 0) {
                        windowTokens.push(promptTokens[j]);
                    }
                }

                if (windowTokens.length === gramSize) {
                    const windowPhrase = windowTokens.join(' ').toLowerCase();
                    if (windowPhrase === tailPhrase) {
                        // Temukan titik selesai n-gram di prompt, lalu ambil kelanjutannya
                        let matchEndIdx = i;
                        let matchedCount = 0;
                        while (matchEndIdx < promptTokens.length && matchedCount < gramSize) {
                            if (promptTokens[matchEndIdx].trim().length > 0) {
                                matchedCount++;
                            }
                            matchEndIdx++;
                        }

                        // Kumpulkan kandidat kata berikutnya
                        let candidate = '';
                        let candidateTokens = 0;
                        for (let k = matchEndIdx; k < promptTokens.length; k++) {
                            const tok = promptTokens[k];
                            if (candidate.length + tok.length > maxCandidateLength) break;
                            candidate += tok;
                            if (tok.trim().length > 0) {
                                candidateTokens++;
                                if (candidateTokens >= 8) break; // Maksimal 8 token sekaligus
                            }
                        }

                        if (candidate.trim().length > 0) {
                            return candidate;
                        }
                    }
                }
            }
        }

        return null;
    }

    /**
     * Mempercepat proses akumulasi teks streaming menggunakan Prompt Lookup Decoding.
     */
    function accelerateStream(accumulator, promptContext, onSpeculativeChunk) {
        if (!accumulator || !promptContext) return null;
        const candidate = findCandidates(promptContext, accumulator);
        if (candidate && typeof onSpeculativeChunk === 'function') {
            onSpeculativeChunk(candidate);
        }
        return candidate;
    }

    const GemmaPLD = {
        findCandidates,
        accelerateStream,
        normalizeText
    };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = GemmaPLD;
    }
    if (typeof window !== 'undefined') {
        window.GemmaPLD = GemmaPLD;
    }
})();
