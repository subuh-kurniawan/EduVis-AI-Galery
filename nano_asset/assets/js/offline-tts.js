/**
 * Gemma Offline Text-to-Speech (TTS) Engine
 * Sintesis suara offline alami (Bahasa Indonesia & English) berbasis Web Speech API
 * Membersihkan format Markdown, rumus matematika, dan blok kode sebelum diucapkan.
 */

(() => {
    'use strict';

    /**
     * Membersihkan sintaks Markdown, tag HTML, rumus LaTeX, dan code block agar enak didengar.
     */
    function cleanTextForSpeech(text) {
        if (!text) return '';
        let clean = text
            // Hapus blok kode ```...```
            .replace(/```[\s\S]*?```/g, ' [blok kode dilewati] ')
            // Hapus inline code `...`
            .replace(/`([^`]+)`/g, '$1')
            // Hapus gambar markdown ![alt](url)
            .replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
            // Hapus link markdown [text](url) -> text
            .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
            // Hapus formula matematika $$...$$ atau $...$
            .replace(/\$\$[\s\S]*?\$\$/g, ' [rumus matematika] ')
            .replace(/\$([^$]+)\$/g, '$1')
            // Hapus heading markdown ###
            .replace(/^#{1,6}\s+/gm, '')
            // Hapus penekanan bold/italic **teks** / *teks*
            .replace(/(\*\*|__)(.*?)\1/g, '$2')
            .replace(/(\*|_)(.*?)\1/g, '$2')
            // Hapus tag HTML
            .replace(/<[^>]+>/g, '')
            // Bersihkan baris kosong berlebih
            .replace(/\n{2,}/g, '. ')
            .replace(/\s+/g, ' ')
            .trim();

        return clean;
    }

    function getBestVoice(lang = 'id-ID') {
        if (typeof window === 'undefined' || !window.speechSynthesis) return null;
        const voices = window.speechSynthesis.getVoices();
        if (!voices || voices.length === 0) return null;

        // Cari suara yang cocok dengan prefix bahasa
        const prefix = lang.slice(0, 2).toLowerCase();
        const matched = voices.find(v => v.lang.toLowerCase().startsWith(prefix));
        return matched || voices[0];
    }

    let currentAudio = null;

    async function speakViaServer(text, options = {}) {
        const clean = cleanTextForSpeech(text);
        if (!clean) return null;
        const fn = options.fetchImpl || (typeof fetch === 'function' ? fetch : null);
        if (!fn) return null;
        try {
            const res = await fn('/v1/audio/speech', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    input: clean,
                    voice: options.voice || 'Damayanti',
                    speed: options.rate || 1.0
                })
            });
            if (!res.ok) return null;
            const blob = await res.blob();
            if (typeof URL !== 'undefined' && typeof Audio !== 'undefined') {
                const url = URL.createObjectURL(blob);
                currentAudio = new Audio(url);
                if (typeof options.onStart === 'function') currentAudio.onplay = options.onStart;
                currentAudio.onended = () => {
                    URL.revokeObjectURL(url);
                    currentAudio = null;
                    if (typeof options.onEnd === 'function') options.onEnd();
                };
                await currentAudio.play();
                return currentAudio;
            }
            return blob;
        } catch (err) {
            if (typeof options.onError === 'function') options.onError(err);
            return null;
        }
    }

    function speak(text, options = {}) {
        if (options.preferServer || typeof window === 'undefined' || !window.speechSynthesis) {
            speakViaServer(text, options);
            return null;
        }

        stop(); // Hentikan ucapan yang sedang berjalan

        const clean = cleanTextForSpeech(text);
        if (!clean) return null;

        const {
            rate = 1.0,
            pitch = 1.0,
            lang = 'id-ID',
            onStart = null,
            onEnd = null,
            onError = null
        } = options;

        const utterance = new SpeechSynthesisUtterance(clean);
        utterance.rate = rate;
        utterance.pitch = pitch;
        utterance.lang = lang;

        const voice = getBestVoice(lang);
        if (voice) utterance.voice = voice;

        if (typeof onStart === 'function') utterance.onstart = onStart;
        if (typeof onEnd === 'function') utterance.onend = onEnd;
        if (typeof onError === 'function') utterance.onerror = onError;

        window.speechSynthesis.speak(utterance);
        return utterance;
    }

    function stop() {
        if (currentAudio) {
            try { currentAudio.pause(); } catch (_) {}
            currentAudio = null;
        }
        if (typeof window !== 'undefined' && window.speechSynthesis) {
            window.speechSynthesis.cancel();
        }
    }

    function pause() {
        if (typeof window !== 'undefined' && window.speechSynthesis) {
            window.speechSynthesis.pause();
        }
    }

    function resume() {
        if (typeof window !== 'undefined' && window.speechSynthesis) {
            window.speechSynthesis.resume();
        }
    }

    function isSpeaking() {
        if (typeof window === 'undefined' || !window.speechSynthesis) return false;
        return window.speechSynthesis.speaking;
    }

    /**
     * Menghasilkan tombol HTML "🔊 Dengarkan" ringkas untuk disematkan di bubble chat.
     */
    function renderSpeakButton(text) {
        const escaped = (text || '').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
        return `
            <button class="gemma-tts-btn apple-liquid-glass" onclick="window.GemmaTTS && window.GemmaTTS.speak(this.closest('.prose, .message-content, .chat-bubble')?.innerText || '')" style="display:inline-flex; align-items:center; gap:6px; font-size:11px; padding:4px 10px; border-radius:8px; background:rgba(255,255,255,0.06); backdrop-filter:blur(16px) saturate(180%); -webkit-backdrop-filter:blur(16px) saturate(180%); border:1px solid rgba(255,255,255,0.14); box-shadow:inset 0 1px 1px rgba(255,255,255,0.25), 0 4px 12px rgba(0,0,0,0.2); color:#94a3b8; cursor:pointer; margin-top:6px; transition:all 0.2s cubic-bezier(0.16, 1, 0.3, 1);" title="Bacakan teks dengan suara offline">
                <span>🔊</span> <span style="font-weight:500;">Dengarkan</span>
            </button>
        `.trim();
    }

    const GemmaTTS = {
        cleanTextForSpeech,
        getBestVoice,
        speak,
        speakViaServer,
        stop,
        pause,
        resume,
        isSpeaking,
        renderSpeakButton
    };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = GemmaTTS;
    }
    if (typeof window !== 'undefined') {
        window.GemmaTTS = GemmaTTS;
    }
})();
