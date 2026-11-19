/**
 * Gemma Generation Metrics & Live Benchmark Tracker
 * Menghitung Tokens Per Second (TPS), Time To First Token (TTFT), dan Durasi Total secara real-time.
 */

(() => {
    'use strict';

    class GenerationTracker {
        constructor(prompt = '') {
            this.prompt = prompt || '';
            this.startTime = performance.now();
            this.firstTokenTime = null;
            this.endTime = null;
            this.tokenCount = 0;
            this.charCount = 0;
            this.isCompleted = false;
        }

        recordChunk(chunkText = '') {
            if (!this.firstTokenTime) {
                this.firstTokenTime = performance.now();
            }
            if (chunkText) {
                this.charCount += chunkText.length;
                // Estimasi rasio token (rata-rata 3.8 - 4 karakter per token)
                const estimatedTokens = Math.max(1, Math.round(chunkText.length / 3.8));
                this.tokenCount += estimatedTokens;
            }
        }

        finish() {
            this.endTime = performance.now();
            this.isCompleted = true;
            return this.getStats();
        }

        getStats() {
            const end = this.endTime || performance.now();
            const totalDurationMs = Math.max(1, end - this.startTime);
            const totalDurationSec = totalDurationMs / 1000.0;
            const ttftMs = this.firstTokenTime ? Math.max(0, this.firstTokenTime - this.startTime) : totalDurationMs;

            // Waktu pembentukan token setelah token pertama keluar
            const genDurationSec = this.firstTokenTime ? Math.max(0.01, (end - this.firstTokenTime) / 1000.0) : totalDurationSec;
            const tps = this.tokenCount > 0 ? (this.tokenCount / genDurationSec) : 0;

            return {
                tokenCount: this.tokenCount,
                charCount: this.charCount,
                ttftMs: Math.round(ttftMs),
                durationSec: parseFloat(totalDurationSec.toFixed(2)),
                tps: parseFloat(tps.toFixed(1))
            };
        }
    }

    function createTracker(prompt = '') {
        return new GenerationTracker(prompt);
    }

    /**
     * Menghasilkan HTML badge metrik yang elegan untuk disematkan di footer chat bubble.
     */
    function renderMetricBadge(stats) {
        if (!stats) return '';
        const tpsText = stats.tps > 0 ? `⚡ ${stats.tps} tok/s` : '⚡ Mengukur...';
        const ttftText = `⏱️ TTFT: ${stats.ttftMs}ms`;
        const tokenText = `🏷️ ~${stats.tokenCount} tokens`;
        const durationText = `⌛ ${stats.durationSec}s`;

        return `
            <div class="gemma-metric-badge apple-liquid-glass" style="display:inline-flex; align-items:center; gap:8px; font-size:11px; padding:4px 11px; border-radius:10px; background:rgba(255,255,255,0.05); backdrop-filter:blur(16px) saturate(180%); -webkit-backdrop-filter:blur(16px) saturate(180%); border:1px solid rgba(255,255,255,0.14); box-shadow:inset 0 1px 1px rgba(255,255,255,0.25), 0 4px 12px rgba(0,0,0,0.25); color:#94a3b8; font-family:ui-monospace, SFMono-Regular, Menlo, monospace; margin-top:8px; transition:all 0.2s;" title="Metrik Inferensi On-Device Hardware">
                <span style="color:#38bdf8; font-weight:600;">${tpsText}</span>
                <span style="opacity:0.4;">•</span>
                <span>${ttftText}</span>
                <span style="opacity:0.4;">•</span>
                <span>${tokenText}</span>
                <span style="opacity:0.4;">•</span>
                <span>${durationText}</span>
            </div>
        `.trim();
    }

    const GemmaMetrics = {
        GenerationTracker,
        createTracker,
        renderMetricBadge
    };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = GemmaMetrics;
    }
    if (typeof window !== 'undefined') {
        window.GemmaMetrics = GemmaMetrics;
    }
})();
