/**
 * Gemma KV-Cache Guard & Memory Governor
 * Mengelola alokasi memori KV-Cache (INT8/FP8/FP16) dan Sliding Window Attention
 * Mencegah WebGPU Device Lost / Out-Of-Memory (OOM) pada percakapan panjang.
 */

(() => {
    'use strict';

    /**
     * Memperkirakan kapasitas RAM sistem perangkat (dalam GB).
     */
    function detectSystemMemoryGB() {
        if (typeof navigator !== 'undefined' && navigator.deviceMemory) {
            return navigator.deviceMemory;
        }
        // Fallback wajar untuk browser desktop
        return 8;
    }

    /**
     * Menghitung profil KV-Cache yang optimal berdasarkan kapasitas RAM dan nama model.
     */
    function getRecommendedCacheProfile(modelName = '', systemRamGB = null) {
        const ram = systemRamGB || detectSystemMemoryGB();
        const isBigModel = /12b|26b|31b/i.test(modelName);

        if (ram <= 4) {
            return {
                maxTokens: 1024,
                kvPrecision: 'int8',
                slidingWindowTurns: 6,
                tier: 'low',
                safeThresholdRatio: 0.75,
                advice: 'Profil Hemat RAM (INT8 KV-Cache, konteks 1024 token)'
            };
        } else if (ram <= 8) {
            return {
                maxTokens: isBigModel ? 1024 : 2048,
                kvPrecision: isBigModel ? 'int8' : 'fp8',
                slidingWindowTurns: isBigModel ? 8 : 14,
                tier: 'medium',
                safeThresholdRatio: 0.82,
                advice: 'Profil Seimbang (FP8/INT8 KV-Cache, konteks 2048 token)'
            };
        } else {
            return {
                maxTokens: isBigModel ? 2048 : 4096,
                kvPrecision: isBigModel ? 'fp8' : 'fp16',
                slidingWindowTurns: 24,
                tier: 'high',
                safeThresholdRatio: 0.90,
                advice: 'Profil Kinerja Tinggi (FP16/FP8 KV-Cache, konteks 4096 token)'
            };
        }
    }

    /**
     * Memangkas riwayat percakapan secara cerdas (Sliding Window Attention)
     * Mempertahankan turn awal (system context) dan turn terbaru, sambil mereduksi turn tengah jika mendekati batas token.
     */
    function applySlidingWindow(turns = [], options = {}) {
        if (!Array.isArray(turns) || turns.length <= 4) {
            return turns;
        }

        const {
            maxTurns = 12,
            preserveRecent = 4,
            preserveFirst = 1
        } = options;

        if (turns.length <= maxTurns) {
            return turns;
        }

        const firstTurns = turns.slice(0, preserveFirst);
        const recentTurns = turns.slice(-preserveRecent);

        const noticeTurn = {
            role: 'system',
            content: `[Catatan Sistem: ${turns.length - preserveFirst - preserveRecent} putaran percakapan terdahulu diringkas demi menjaga kestabilan memori WebGPU KV-Cache]`
        };

        return [...firstTurns, noticeTurn, ...recentTurns];
    }

    /**
     * Memperkirakan pemakaian memori KV-Cache (dalam Megabyte).
     * Formula dasar KV-Cache: 2 * num_layers * hidden_size * seq_len * bytes_per_elem
     */
    function estimateKVCacheMemoryMB(seqLength, hiddenSize = 2048, numLayers = 18, precision = 'fp8') {
        const bytesPerElem = precision === 'int8' || precision === 'fp8' ? 1 : 2;
        const totalBytes = 2 * numLayers * hiddenSize * seqLength * bytesPerElem;
        return (totalBytes / (1024 * 1024)).toFixed(2);
    }

    const GemmaCacheGuard = {
        detectSystemMemoryGB,
        getRecommendedCacheProfile,
        applySlidingWindow,
        estimateKVCacheMemoryMB
    };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = GemmaCacheGuard;
    }
    if (typeof window !== 'undefined') {
        window.GemmaCacheGuard = GemmaCacheGuard;
    }
})();
