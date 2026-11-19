/*
 * Voice conversation controller for the local LiteRT-LM API.
 * Include with: <script src="live-conversation.js"></script>
 */
(function () {
    'use strict';

    function stripCodeForSpeech(text, discardIncomplete = false) {
        let output = '';
        let index = 0;

        while (index < text.length) {
            if (text[index] !== '`') {
                output += text[index];
                index += 1;
                continue;
            }

            let delimiterEnd = index;
            while (text[delimiterEnd] === '`') delimiterEnd += 1;
            const delimiterLength = delimiterEnd - index;
            const isFence = delimiterLength >= 3;
            let closingIndex = delimiterEnd;

            while (closingIndex < text.length) {
                const nextTick = text.indexOf('`', closingIndex);
                if (nextTick < 0) {
                    closingIndex = -1;
                    break;
                }
                let closingEnd = nextTick;
                while (text[closingEnd] === '`') closingEnd += 1;
                const closingLength = closingEnd - nextTick;
                if (isFence ? closingLength >= 3 : closingLength === delimiterLength) {
                    closingIndex = nextTick;
                    break;
                }
                closingIndex = closingEnd;
            }

            if (closingIndex < 0) {
                if (discardIncomplete) return output;
                return output + text.slice(index);
            }

            let closingEnd = closingIndex;
            while (text[closingEnd] === '`') closingEnd += 1;
            output += ' ';
            index = closingEnd;
        }

        return output;
    }

    function stripSpeakerPrefixForSpeech(text) {
        if (!text) return '';
        return String(text)
            .replace(/^\s*(?:\[|\*\*|\*)?\s*(?:arsi|eduvis|gemma(?:[-_ ]?\d+[a-z]*)?|ai|asisten|assistant|model|bot|konsultan|tutor|guru|pembicara|narator|narrator|suara|vo|voiceover|voice\s*over|jawaban|respon|response|gadis|ardi|wibowo|citra|bimo|sari|dimas|bayu|tari|juminten|asep|orator|jokowi|lala|kiki|mimi|dewi|piper|[a-zA-Z0-9_-]+(?:\s+[a-zA-Z0-9_-]+){0,3})\s*(?:\]|\*\*|\*)?\s*[:\-–]\s*/i, '')
            .replace(/\n\s*(?:\[|\*\*|\*)?\s*(?:arsi|eduvis|gemma(?:[-_ ]?\d+[a-z]*)?|ai|asisten|assistant|model|bot|konsultan|tutor|guru|pembicara|narator|narrator|suara|vo|voiceover|voice\s*over|jawaban|respon|response|gadis|ardi|wibowo|citra|bimo|sari|dimas|bayu|tari|juminten|asep|orator|jokowi|lala|kiki|mimi|dewi|piper|[a-zA-Z0-9_-]+(?:\s+[a-zA-Z0-9_-]+){0,3})\s*(?:\]|\*\*|\*)?\s*[:\-–]\s*/gi, '\n');
    }

    function isUserGreetingOnly(text) {
        const clean = String(text || '').trim().toLowerCase();
        return /^(?:halo|hai|hello|hi|hey|selamat\s+(?:pagi|siang|sore|malam)|assalamu['’]?alaikum|salam)(?:[\s,!?.]+(?:arsi|narendra|eduvis|ai|asisten|semua|teman|pak|bu))?[\s,!?.]*$/iu.test(clean);
    }

    function stripRepeatedGreetingForSpeech(text) {
        if (!text) return '';
        const cleaned = String(text).replace(
            /^\s*(?:(?:halo|hai|hello|hi|hey|selamat\s+(?:pagi|siang|sore|malam)|assalamu['’]?alaikum(?:\s+warahmatullahi\s+wabarakatuh)?)(?:\s+(?:kembali|lagi|juga|teman|sahabat|pak|bu|kak|bapak|ibu))?[\s,!?.—–-]*){1,2}(?:saya\s+(?:arsi|narendra|eduvis(?:\s+ai)?)\b[^.!?]*[.!?]\s*)?/iu,
            ''
        ).trim();
        // Hanya pakai hasil strip jika masih ada isi jawaban inti setelah salam
        return cleaned.length >= 6 ? cleaned : String(text).trim();
    }

    const SENTENCE_MARKS = new Set(['.', '!', '?', '。', '！', '？', '…']);
    const CLOSING_MARKS = new Set(['"', "'", '”', '’', '»', ')', ']', '}', '】', '〕', '〉', '》', '」', '』']);
    const TITLE_ABBREVIATIONS = new Set([
        'dr', 'drs', 'prof', 'ir', 'bpk', 'sdr', 'tn', 'ny', 'no', 'mr', 'mrs', 'ms', 'mx', 'rev', 'fr'
    ]);
    const COMMON_ABBREVIATIONS = new Set([
        'dll', 'dst', 'dsb', 'dkk', 'ybs', 'yth', 'hlm', 'hal', 'vol', 'jil',
        'ed', 'etc', 'vs', 's.pd', 's.kom', 's.h', 's.t', 's.si'
    ]);
    const MAX_SPEECH_CHUNK_LENGTH = 260;
    const MIN_SOFT_CHUNK_LENGTH = 150;
    const SPEECH_CHUNK_TIMEOUT_MS = 1200;
    const MIN_TIMEOUT_CHUNK_WORDS = 8;
    const TARGET_TIMEOUT_CHUNK_WORDS = 20;
    const MAX_TIMEOUT_CHUNK_WORDS = 32;
    const MAX_TURN_HISTORY_MESSAGES = 120; // Hingga 60 pasang giliran multi-turn
    const MAX_CONTEXT_CHARS = 24000;       // Anggaran aman ~6K-8K token agar tidak overflow context LiteRT-LM lokal
    const NORMAL_PAUSE_MS = 1700;          // Jeda hening nyaman 1.7 detik untuk kalimat normal
    const THINKING_PAUSE_MS = 2400;        // Jeda ekstra 2.4 detik jika kalimat menggantung / pengguna sedang berpikir
    const THINKING_PAUSE_WORDS = new Set([
        'dan', 'atau', 'yang', 'karena', 'kalau', 'jika', 'terus', 'lalu', 'jadi',
        'untuk', 'dengan', 'tentang', 'seperti', 'eee', 'ee', 'eh', 'emm', 'em',
        'hmm', 'hm', 'anu', 'maksudnya', 'yaitu', 'adalah', 'nah', 'tapi', 'tetapi',
        'namun', 'soalnya', 'supaya', 'agar', 'dari', 'di', 'ke', 'pada', 'bahwa',
        'sehingga', 'misalnya', 'contohnya', 'kemudian', 'terkait'
    ]);

    function getAdaptivePauseMs(text) {
        const clean = String(text || '').trim().toLowerCase();
        if (!clean) return NORMAL_PAUSE_MS;
        const words = clean.match(/[\p{L}\p{N}]+/gu) || [];
        if (words.length <= 2) return THINKING_PAUSE_MS;
        const lastWord = words[words.length - 1] || '';
        if (THINKING_PAUSE_WORDS.has(lastWord) || /[,;:—–-]$/.test(clean)) {
            return THINKING_PAUSE_MS;
        }
        return NORMAL_PAUSE_MS;
    }
    const UNSAFE_SPEECH_ENDINGS = new Set([
        'agar', 'apabila', 'atau', 'bahwa', 'dan', 'dari', 'dengan', 'di',
        'hingga', 'jika', 'karena', 'ke', 'ketika', 'meskipun', 'maka',
        'namun', 'oleh', 'pada', 'sehingga', 'sebagai', 'supaya', 'tetapi',
        'untuk', 'walaupun', 'yang'
    ]);

    function isUppercaseLetter(character) {
        return Boolean(character && /\p{Lu}/u.test(character));
    }

    function nextSpeechCharacter(text, index) {
        let cursor = index + 1;
        while (cursor < text.length && (/\s/u.test(text[cursor]) || CLOSING_MARKS.has(text[cursor]))) {
            cursor += 1;
        }
        return text[cursor] || '';
    }

    function isAbbreviationPeriod(text, index) {
        if (/\d/u.test(text[index - 1] || '') && /\d/u.test(text[index + 1] || '')) return true;

        const match = text.slice(0, index + 1).match(/(?:^|[\s([{])([\p{L}\d]+(?:\.[\p{L}\d]+)*)\.$/u);
        if (!match) return false;

        const token = match[1].toLowerCase();
        const nextCharacter = nextSpeechCharacter(text, index);
        if (/^\d+$/u.test(token)) {
            const lineStart = text.lastIndexOf('\n', index - 1) + 1;
            const linePrefix = text.slice(lineStart, index - token.length).trim();
            return !linePrefix && isUppercaseLetter(nextCharacter);
        }
        if (TITLE_ABBREVIATIONS.has(token)) return true;
        if (/^(?:\p{L}\.)+\p{L}?$/u.test(token)) return true;
        if (token.length === 1 && isUppercaseLetter(token) && isUppercaseLetter(nextCharacter)) return true;
        if (COMMON_ABBREVIATIONS.has(token)) return !isUppercaseLetter(nextCharacter);
        return false;
    }

    function findSentenceBoundary(text, flush) {
        for (let index = 0; index < text.length; index += 1) {
            if (text[index] === '\n' || text[index] === '\r') {
                const paragraphBreak = text.slice(index).match(/^(?:\r?\n)[ \t]*(?:\r?\n)/);
                if (paragraphBreak) return index;
                // Pecah juga pada newline tunggal (heading / bullet point) jika sudah ada teks bermakna
                const prefixLine = text.slice(0, index).trim();
                if (prefixLine.length >= 16 || /[:;!?.,…]$/.test(prefixLine)) {
                    return index;
                }
            }
            if (!SENTENCE_MARKS.has(text[index])) continue;

            const isEllipsis = text[index] === '…' || text.startsWith('..', index);
            if (text[index] === '.' && !isEllipsis && isAbbreviationPeriod(text, index)) continue;

            let end = index + 1;
            while (end < text.length && SENTENCE_MARKS.has(text[end])) end += 1;
            while (end < text.length && CLOSING_MARKS.has(text[end])) end += 1;

            let next = end;
            while (next < text.length && /\s/u.test(text[next])) next += 1;
            if (next === end && (!flush || end < text.length)) {
                index = end - 1;
                continue;
            }
            return end;
        }
        return -1;
    }

    function findSoftSpeechBoundary(text) {
        if (text.length < MAX_SPEECH_CHUNK_LENGTH) return -1;

        for (let index = MAX_SPEECH_CHUNK_LENGTH; index >= MIN_SOFT_CHUNK_LENGTH; index -= 1) {
            if (isUnsafeSpeechEnding(text.slice(0, index))) continue;
            if (/[;:,—–]/u.test(text[index - 1] || '') && /\s/u.test(text[index] || '')) {
                return index;
            }
        }
        // Fallback ke spasi aman agar kalimat panjang tanpa koma tetap segera disuarakan
        for (let index = MAX_SPEECH_CHUNK_LENGTH; index >= MIN_SOFT_CHUNK_LENGTH; index -= 1) {
            if (/\s/u.test(text[index] || '') && !isUnsafeSpeechEnding(text.slice(0, index))) {
                return index;
            }
        }
        return -1;
    }

    function countSpeechWords(text) {
        return (text.match(/[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*/gu) || []).length;
    }

    function isUnsafeSpeechEnding(text) {
        const words = text.match(/[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*/gu) || [];
        return UNSAFE_SPEECH_ENDINGS.has((words[words.length - 1] || '').toLowerCase());
    }

    function findTimedSpeechBoundary(text) {
        const candidates = [];
        for (let index = 0; index < text.length; index += 1) {
            if (!/\s/u.test(text[index])) continue;
            const prefix = text.slice(0, index).trimEnd();
            const wordCount = countSpeechWords(prefix);
            if (wordCount < MIN_TIMEOUT_CHUNK_WORDS || wordCount > MAX_TIMEOUT_CHUNK_WORDS) continue;
            if (isUnsafeSpeechEnding(prefix)) continue;
            candidates.push({
                index,
                wordCount,
                isClauseBoundary: /[,;:—–]$/u.test(prefix)
            });
        }

        const clauseBoundaries = candidates.filter(candidate => candidate.isClauseBoundary);
        const withinClauseTarget = clauseBoundaries.filter(candidate => candidate.wordCount <= TARGET_TIMEOUT_CHUNK_WORDS);
        const withinWordTarget = candidates.filter(candidate => candidate.wordCount <= TARGET_TIMEOUT_CHUNK_WORDS);
        const selected = withinClauseTarget[withinClauseTarget.length - 1]
            || clauseBoundaries[0]
            || withinWordTarget[withinWordTarget.length - 1]
            || candidates[0];
        return selected ? selected.index : -1;
    }

    function findFirstChunkBoundary(text) {
        // Ultra-realtime first chunk: segera potong pada klausa (>= 3 kata) atau 7-9 kata aman agar audio mulai < 300ms
        for (let index = 0; index < text.length; index += 1) {
            if (!/\s/u.test(text[index])) continue;
            const prefix = text.slice(0, index).trimEnd();
            const wordCount = countSpeechWords(prefix);
            if (wordCount < 3) continue;
            if (isUnsafeSpeechEnding(prefix)) continue;
            if (/[,;:—–]$/u.test(prefix) && prefix.length >= 16) {
                return index;
            }
            if (wordCount >= 7) {
                return index;
            }
        }
        return -1;
    }

    function splitSpeechBuffer(text, flush = false) {
        const segments = [];
        let remaining = text;

        while (remaining.trim()) {
            const sentenceBoundary = findSentenceBoundary(remaining, flush);
            const softBoundary = findSoftSpeechBoundary(remaining);
            const boundary = softBoundary > 0 &&
                (sentenceBoundary < 0 || sentenceBoundary > MAX_SPEECH_CHUNK_LENGTH)
                ? softBoundary
                : sentenceBoundary;
            if (boundary < 0) break;

            const segment = remaining.slice(0, boundary).trim();
            remaining = remaining.slice(boundary).trimStart();
            if (segment) segments.push(segment);
        }

        if (flush && remaining.trim()) {
            segments.push(remaining.trim());
            remaining = '';
        }
        return { segments, remainder: remaining };
    }

    const LOCAL_MALE_SPEAKER_IDS = new Set([
        'ardi', 'wibowo', 'bimo', 'dimas', 'bayu', 'asep', 'su-00060',
        'orator', 'jokowi', 'prabowo', 'kiki'
    ]);
    const LOCAL_FEMALE_SPEAKER_IDS = new Set([
        'gadis', 'citra', 'sari', 'tari', 'juminten', 'jv-00264',
        'lala', 'mimi', 'dewi', 'damayanti'
    ]);
    const KNOWN_MALE_VOICE_NAMES = new Set([
        'alex', 'albert', 'daniel', 'eddy', 'fred', 'grandpa', 'junior', 'ralph', 'reed', 'rishi', 'rocko'
    ]);
    const KNOWN_FEMALE_VOICE_NAMES = new Set([
        'damayanti', 'samantha', 'flo', 'grandma', 'karen', 'kathy', 'moira', 'sandy', 'shelley', 'tessa'
    ]);

    class LiveConversationController {
        static extractPersonaChangeRequest(text) {
            const input = String(text || '').trim();
            const patterns = [
                /(?:ubah|ganti|rubah)\s+(?:peran|role|persona)(?:\s+(?:ai|anda|mu))?\s+(?:menjadi|ke|sebagai|jadi)\s+(.+)/iu,
                /(?:mulai\s+sekarang[,\s]+)?(?:berperan|bertindak)\s+sebagai\s+(.+)/iu,
                /(?:mulai\s+sekarang\s+)?(?:jadilah|jadikan\s+dirimu)\s+(.+)/iu,
                /mulai\s+sekarang[,\s]+(?:jadi|menjadi)\s+(.+)/iu,
                /(?:mulai\s+sekarang|mulai\s+detik\s+ini)[,\s]+(?:kamu|anda)\s+(?:adalah|jadi|menjadi)\s+(.+)/iu,
                /(?:change|switch)\s+(?:your\s+)?(?:role|persona)\s+(?:to|as)\s+(.+)/iu,
                /act\s+as\s+(.+)/iu
            ];

            for (const pattern of patterns) {
                const match = input.match(pattern);
                const role = match?.[1]?.trim().replace(/[.!?]+$/u, '');
                if (role) return role;
            }
            return null;
        }

        static getVoiceGender(voice = {}) {
            const explicitGender = String(voice.gender || '').trim().toLowerCase();
            if (['male', 'masculine', 'm'].includes(explicitGender)) return 'male';
            if (['female', 'feminine', 'f'].includes(explicitGender)) return 'female';

            const id = String(voice.id || voice.voiceURI || '').trim().toLowerCase();
            if (LOCAL_MALE_SPEAKER_IDS.has(id)) return 'male';
            if (LOCAL_FEMALE_SPEAKER_IDS.has(id)) return 'female';

            const name = String(voice.name || '').trim().toLowerCase();
            if (/\b(male|masculine|man|pria|laki[\s-]?laki|cowok|putra)\b/u.test(name)) return 'male';
            if (/\b(female|feminine|woman|perempuan|wanita|cewek|putri)\b/u.test(name)) return 'female';

            const nameTokens = new Set(name.replace(/[^a-z0-9]+/g, ' ').split(/\s+/u).filter(Boolean));
            for (const token of nameTokens) {
                if (KNOWN_MALE_VOICE_NAMES.has(token)) return 'male';
                if (KNOWN_FEMALE_VOICE_NAMES.has(token)) return 'female';
            }
            return 'unknown';
        }

        constructor(options = {}) {
            this.options = {
                language: 'id-ID',
                voiceLanguage: 'id-ID',
                litertBaseUrl: '',
                litertModel: '',
                systemPrompt: 'Anda adalah asisten suara berbahasa Indonesia. Jawab singkat, jelas, dan natural.',
                personaPrompt: 'Gunakan gaya bahasa natural, santai, dan mudah dipahami.',
                conversationContext: '',
                manualMode: true,
                onStateChange: () => {},
                onBackendChange: () => {},
                onTranscript: () => {},
                onResponse: () => {},
                onSpeechProgress: () => {},
                onLocalTtsFallback: () => {},
                onBeforeAsk: () => {},
                onError: () => {},
                ...options
            };
            this.recognition = null;
            this.session = null;
            this.running = false;
            this.starting = false;
            this.listening = false;
            this.speaking = false;
            this.interimTranscript = '';
            this.finalTranscript = '';
            this.responseBuffer = '';
            this.speechChunkTimer = null;
            this.speechSubmitTimer = null;
            this.recognitionRestartTimer = null;
            this.fullResponseText = '';
            this.responseComplete = false;
            this.clearSpeechChunkTimer();
            this.speechText = '';
            this.speechPlaybackPending = false;
            this.abortController = null;
            this.turnHistory = [];
            this.lastUserPrompt = '';
            this.selfSpeechLock = false;
            this.ttsSuppressionUntil = 0;
            this.lastUserSpeechAt = 0;
            this.autoListenCooldown = 0;
            this.audioCtx = null;
            this.currentAudioSource = null;
            this.audioQueue = [];
            this.systemSpeechUtterances = new Set();
            this.isPlayingQueue = false;
            window.addEventListener('native-speech-event', event => {
                const recognition = this.recognition;
                const detail = event.detail || {};
                if (!recognition?.native) return;
                if (detail.type === 'start') {
                    recognition.onstart?.({});
                } else if (detail.type === 'result') {
                    const result = [{ transcript: detail.transcript || '' }];
                    result.isFinal = Boolean(detail.isFinal);
                    recognition.onresult?.({ resultIndex: 0, results: [result] });
                } else if (detail.type === 'error') {
                    recognition.onerror?.({ error: detail.error || 'unknown' });
                } else if (detail.type === 'end') {
                    recognition.onend?.({});
                }
            });
        }

        initAudioContext() {
            if (window.__eduvisAudioContext) {
                this.audioCtx = window.__eduvisAudioContext;
            } else if (!this.audioCtx) {
                const AudioCtx = window.AudioContext || window.webkitAudioContext;
                if (AudioCtx) {
                    this.audioCtx = new AudioCtx();
                    window.__eduvisAudioContext = this.audioCtx;
                }
            }
            if (this.audioCtx && this.audioCtx.state === 'suspended') {
                this.audioCtx.resume();
            }
            return this.audioCtx;
        }

        start() {
            if (this.starting) return;
            this.starting = true;
            try {
                this.initAudioContext();
                if (!this.createRecognition()) return;

                if (!this.running) {
                    try {
                        this.session = this.createSession();
                        this.running = true;
                    } catch (error) {
                        console.warn('Session init warning, continuing speech recognition:', error);
                        this.session = this.createSession(true);
                        this.running = true;
                    }
                }

                if (this.selfSpeechLock || this.speaking || Date.now() < this.ttsSuppressionUntil) {
                    this.setState('idle');
                    return;
                }

                this.setState('listening');
                this.startListening();
            } finally {
                this.starting = false;
            }
        }

        stop() {
            this.running = false;
            this.abortController?.abort();
            this.abortController = null;
            this.clearRecognitionRestartTimer();
            this.clearSpeechChunkTimer();
            this.clearSpeechSubmitTimer();
            this.recognition?.stop();
            this.audioQueue = [];
            if (this.currentAudioSource) {
                try { this.currentAudioSource.stop(); } catch (_) {}
                this.currentAudioSource = null;
            }
            this.systemSpeechUtterances.clear();
            window.speechSynthesis?.cancel();
            this.speechPlaybackPending = false;
            this.options.onSpeechProgress({ phase: 'cancel', text: this.speechText, charIndex: this.speechText.length });
            this.listening = false;
            this.speaking = false;
            this.setState('idle');
        }

        interrupt() {
            this.abortController?.abort();
            this.abortController = null;
            this.clearRecognitionRestartTimer();
            this.clearSpeechChunkTimer();
            this.audioQueue = [];
            if (this.currentAudioSource) {
                try { this.currentAudioSource.stop(); } catch (_) {}
                this.currentAudioSource = null;
            }
            this.systemSpeechUtterances.clear();
            window.speechSynthesis?.cancel();
            this.speechPlaybackPending = false;
            this.options.onSpeechProgress({ phase: 'cancel', text: this.speechText, charIndex: this.speechText.length });
            this.speaking = false;
            this.ttsSuppressionUntil = 0;
            this.autoListenCooldown = 0;
            if (this.running) {
                this.setState('listening');
                this.startListening();
            }
        }

        createRecognition() {
            const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
            if (Recognition) {
                if (this.recognition && !this.recognition.native) return true;
                this.recognition = new Recognition();
                this.recognition.lang = this.options.language;
                this.recognition.continuous = true;
                this.recognition.interimResults = true;
                this.recognition.maxAlternatives = 1;

                this.recognition.onstart = () => {
                    const now = Date.now();
                    if (this.selfSpeechLock || this.speaking || now < this.ttsSuppressionUntil) {
                        this.recognition.stop();
                        return;
                    }
                    this.listening = true;
                    this.setState('listening');
                };
                this.recognition.onend = () => {
                    this.listening = false;
                    const now = Date.now();
                    if (!this.running || this.speaking || this.selfSpeechLock || now < this.ttsSuppressionUntil) return;
                    if (this.speechSubmitTimer !== null) {
                        // Masih dalam jeda berpikir: jangan potong dulu, biarkan timer yang memutuskan
                        return;
                    }
                    if (this.finalTranscript.trim() || this.abortController) {
                        this.setState('thinking');
                        return;
                    }
                    if (this.options.manualMode) {
                        this.setState('idle');
                        return;
                    }

                    this.setState('listening');
                    this.scheduleRecognitionRestart();
                };
                this.recognition.onerror = event => {
                    const now = Date.now();
                    if (this.selfSpeechLock || now < this.ttsSuppressionUntil) return;
                    if (event.error === 'aborted' || event.error === 'no-speech') return;
                    this.fail(new Error(`Speech recognition: ${event.error}`));
                };
                this.recognition.onresult = event => this.handleRecognitionResult(event);
                return true;
            }

            const nativeSpeech = window.webkit?.messageHandlers?.nativeSpeech;
            if (nativeSpeech) {
                this.recognition = {
                    native: true,
                    start: () => nativeSpeech.postMessage({
                        action: 'start',
                        language: this.options.language
                    }),
                    stop: () => nativeSpeech.postMessage({ action: 'stop' }),
                    onstart: null,
                    onend: null,
                    onerror: null,
                    onresult: null
                };
                return true;
            }

            this.fail(new Error('SpeechRecognition tidak tersedia di browser ini.'));
            return false;
        }

        startListening() {
            const now = Date.now();
            if (!this.running || this.listening || this.speaking || this.selfSpeechLock || now < this.ttsSuppressionUntil || now < this.autoListenCooldown) return;
            this.clearRecognitionRestartTimer();
            try {
                this.finalTranscript = '';
                this.interimTranscript = '';
                this.recognition.start();
            } catch (error) {
                if (error.name !== 'InvalidStateError') this.fail(error);
            }
        }

        scheduleRecognitionRestart() {
            if (this.recognitionRestartTimer !== null) return;
            const delay = Math.max(350, this.autoListenCooldown - Date.now() + 50);
            this.recognitionRestartTimer = setTimeout(() => {
                this.recognitionRestartTimer = null;
                this.startListening();
            }, delay);
        }

        clearRecognitionRestartTimer() {
            if (this.recognitionRestartTimer === null) return;
            clearTimeout(this.recognitionRestartTimer);
            this.recognitionRestartTimer = null;
        }

        clearSpeechSubmitTimer() {
            if (this.speechSubmitTimer === null) return;
            clearTimeout(this.speechSubmitTimer);
            this.speechSubmitTimer = null;
        }

        stopListening() {
            this.clearSpeechSubmitTimer();
            const combined = `${this.finalTranscript} ${this.interimTranscript}`.trim();
            if (combined && !this.speaking && !this.selfSpeechLock) {
                this.commitUserSpeech();
                return;
            }
            try { this.recognition?.stop(); } catch (_) {}
        }

        commitUserSpeech() {
            this.clearSpeechSubmitTimer();
            const combined = `${this.finalTranscript} ${this.interimTranscript}`.trim();
            if (!combined) return;
            this.finalTranscript = '';
            this.interimTranscript = '';
            try { this.recognition?.stop(); } catch (_) {}
            this.ask(combined);
        }

        handleRecognitionResult(event) {
            const now = Date.now();
            if (this.selfSpeechLock || this.speaking || now < this.ttsSuppressionUntil) return;
            let interim = '';
            let finalText = '';
            for (let index = event.resultIndex; index < event.results.length; index += 1) {
                const transcript = event.results[index][0].transcript;
                if (event.results[index].isFinal) finalText += transcript;
                else interim += transcript;
            }
            this.interimTranscript = interim;
            if (this.recognition?.native) {
                if (finalText.trim()) {
                    this.finalTranscript = finalText.trim();
                }
            } else if (finalText) {
                this.finalTranscript = `${this.finalTranscript} ${finalText}`.trim();
            }
            this.options.onTranscript({
                interim: this.interimTranscript,
                final: this.finalTranscript
            });

            if (this.recognition?.native) {
                if (finalText.trim()) {
                    this.recognition.stop();
                    this.ask(this.finalTranscript.trim());
                }
                return;
            }

            // Smart Pause Detection untuk browser SpeechRecognition:
            // Jangan langsung potong saat user jeda berpikir; tunggu jeda adaptif (1.7s normal / 2.4s saat kalimat menggantung)
            const combined = `${this.finalTranscript} ${this.interimTranscript}`.trim();
            if (!combined) return;
            this.clearSpeechSubmitTimer();
            const pauseMs = getAdaptivePauseMs(combined);
            this.speechSubmitTimer = setTimeout(() => {
                this.speechSubmitTimer = null;
                if (!this.running || this.speaking || this.selfSpeechLock) return;
                this.commitUserSpeech();
            }, pauseMs);
        }

        async generateRecap(messages = []) {
            // Berjalan sepenuhnya terpisah & asinkron tanpa mengubah alur, turnHistory, atau sesi suara aktif
            const list = (Array.isArray(messages) ? messages : [])
                .filter(m => m && String(m.content || m.text || '').trim())
                .map(m => `${m.role === 'user' ? 'Pengguna' : 'Asisten'}: ${String(m.content || m.text || '').trim()}`);
            if (!list.length) {
                return 'Belum ada percakapan untuk direkap pada sesi ini.';
            }
            const transcriptText = list.join('\n').slice(-26000);
            const targetUrl = (this.options.litertBaseUrl || 'http://127.0.0.1:1236/v1').replace(/\/$/, '');
            const modelId = this.options.litertModel || 'gemma-4-E2B-it';
            try {
                const res = await fetch(`${targetUrl}/chat/completions`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        model: `${modelId},gpu`,
                        messages: [
                            {
                                role: 'system',
                                content: 'Buat rekap terstruktur dari seluruh percakapan berikut dalam bahasa Indonesia yang ringkas dan akurat. Gunakan format Markdown dengan bagian: 1) **Topik Utama**, 2) **Poin-Poin Penting**, 3) **Kesimpulan & Tindak Lanjut**. Jangan menambahkan salam atau basa-basi.'
                            },
                            {
                                role: 'user',
                                content: `Rekap seluruh percakapan berikut:\n\n${transcriptText}`
                            }
                        ],
                        stream: false
                    })
                });
                if (!res.ok) throw new Error(`HTTP ${res.status}`);
                const data = await res.json();
                const content = data?.choices?.[0]?.message?.content?.trim();
                if (content) return content;
            } catch (err) {
                console.warn('Rekap AI lokal fallback ke ringkasan lokal:', err);
            }
            // Fallback lokal cepat jika endpoint sedang sibuk/offline
            const userLines = list.filter(l => l.startsWith('Pengguna:')).map(l => `- ${l.replace(/^Pengguna:\s*/, '')}`);
            const aiLines = list.filter(l => l.startsWith('Asisten:')).slice(-3).map(l => `- ${l.replace(/^Asisten:\s*/, '').slice(0, 180)}`);
            return `### Rekap Percakapan (${list.length} pesan)\n\n**Topik & Pertanyaan Pengguna:**\n${userLines.join('\n') || '-'}\n\n**Ringkasan Respons Terakhir:**\n${aiLines.join('\n') || '-'}`;
        }

        setTurnHistory(messages = []) {
            if (!Array.isArray(messages)) {
                this.turnHistory = [];
                return;
            }
            this.turnHistory = messages
                .filter(m => m && (m.role === 'user' || m.role === 'assistant' || m.role === 'ai') && String(m.content || m.text || '').trim())
                .map(m => ({
                    role: m.role === 'user' ? 'user' : 'assistant',
                    content: String(m.content || m.text || '').trim()
                }))
                .slice(-MAX_TURN_HISTORY_MESSAGES);
        }

        resetConversation() {
            this.abortController?.abort();
            this.clearSpeechChunkTimer();
            this.audioQueue = [];
            if (this.currentAudioSource) {
                try { this.currentAudioSource.stop(); } catch (_) {}
                this.currentAudioSource = null;
            }
            this.turnHistory = [];
            this.options.conversationContext = '';
            this.responseBuffer = '';
            this.fullResponseText = '';
            this.speechText = '';
            this.lastUserPrompt = '';
            this.responseComplete = false;
            this.speechPlaybackPending = false;
            this.speaking = false;
            this.selfSpeechLock = false;
            this.session = null;
            this.options.onSpeechProgress({ phase: 'reset', text: '', charIndex: 0 });
        }

        createSession(isFallback = false) {
            if (!this.options.litertModel) {
                this.options.litertModel = 'gemma-4-E2B-it';
            }
            this.options.onBackendChange('litert-lm');
            return {
                promptStreaming: async function* (text, { signal } = {}) {
                    const isFollowUp = this.turnHistory.length > 0 || Boolean(this.options.conversationContext);
                    const antiGreetingRule = isFollowUp
                        ? 'ATURAN PERCAKAPAN MENGALIR: Percakapan sedang berlangsung. DILARANG mengawali jawaban dengan salam, sapaan, atau perkenalan ulang (seperti Halo, Hai, Selamat pagi/siang/sore/malam, Assalamualaikum, atau menyebut nama Anda) kecuali pengguna secara eksplisit menyapa. Jangan mengulang kalimat penutup kaku yang sama di setiap giliran. Jaga kesinambungan konteks dari pesan sebelumnya dan jawab secara lisan, hangat, ringkas, serta mengalir natural.'
                        : 'ATURAN PERCAKAPAN MENGALIR: Gunakan bahasa lisan yang hangat, ringkas, dan mengalir natural. Jika pengguna langsung mengajukan pertanyaan atau instruksi, langsung jawab ke intinya tanpa salam panjang atau perkenalan diri berulang.';
                    const systemContent = [
                        this.options.systemPrompt,
                        this.options.personaPrompt,
                        antiGreetingRule,
                        (!this.turnHistory.length && this.options.conversationContext)
                            ? `Riwayat percakapan sebelumnya:\n${this.options.conversationContext}`
                            : ''
                    ].filter(Boolean).join('\n\n');
                    // Smart Context Budget: muat giliran multi-turn sebanyak mungkin hingga batas aman MAX_CONTEXT_CHARS
                    const budget = Math.max(2000, MAX_CONTEXT_CHARS - systemContent.length - String(text || '').length);
                    const selectedTurns = [];
                    let usedChars = 0;
                    for (let i = this.turnHistory.length - 1; i >= 0; i -= 1) {
                        const turn = this.turnHistory[i];
                        const len = (turn.content || '').length + 16;
                        if (usedChars + len > budget && selectedTurns.length > 0) break;
                        selectedTurns.push({ role: turn.role, content: turn.content });
                        usedChars += len;
                    }
                    selectedTurns.reverse();
                    const messages = [{ role: 'system', content: systemContent }, ...selectedTurns, { role: 'user', content: text }];
                    let response;
                    try {
                        const targetUrl = (this.options.litertBaseUrl || 'http://127.0.0.1:1236/v1').replace(/\/$/, '');
                        response = await fetch(`${targetUrl}/chat/completions`, {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                model: `${this.options.litertModel},gpu`,
                                messages,
                                stream: true
                            }),
                            signal
                        });
                    } catch (netErr) {
                        console.warn('LiteRT API connection note:', netErr);
                        yield 'Halo! Saya mendengar Anda: "' + text + '". Menghubungkan ke layanan kecerdasan lokal EduVis AI.';
                        return;
                    }
                    if (!response.ok) {
                        const details = await response.text();
                        throw new Error(`LiteRT-LM API error: HTTP ${response.status}${details ? ` — ${details.slice(0, 300)}` : ''}`);
                    }
                    if (!response.body) throw new Error('LiteRT-LM tidak mengirim stream respons.');

                    const reader = response.body.getReader();
                    const decoder = new TextDecoder();
                    let buffer = '';
                    const readEvent = line => {
                        if (!line.startsWith('data:')) return null;
                        const data = line.slice(5).trim();
                        if (!data || data === '[DONE]') return data === '[DONE]' ? 'done' : null;
                        const event = JSON.parse(data);
                        if (event.error?.message) throw new Error(event.error.message);
                        const content = event.choices?.[0]?.delta?.content;
                        return typeof content === 'string' ? content : null;
                    };

                    while (true) {
                        const { done, value } = await reader.read();
                        buffer += decoder.decode(value || new Uint8Array(), { stream: !done });
                        const lines = buffer.split(/\r?\n/);
                        buffer = lines.pop() || '';
                        for (const line of lines) {
                            const event = readEvent(line);
                            if (event === 'done') return;
                            if (event) yield event;
                        }
                        if (done) break;
                    }
                    if (buffer) {
                        const event = readEvent(buffer);
                        if (event === 'done') return;
                        if (event) yield event;
                    }
                }.bind(this)
            };
        }

        async ask(text) {
            if (!text || !this.session || !this.running) return;
            this.clearRecognitionRestartTimer();
            this.abortController?.abort();
            this.lastUserSpeechAt = Date.now();
            this.setState('thinking');
            // Hangatkan AudioContext sejak awal agar 0ms delay saat audio pertama siap
            const warmCtx = this.initAudioContext();
            if (warmCtx && warmCtx.state === 'suspended') {
                warmCtx.resume().catch(() => {});
            }
            this.audioQueue = [];
            if (this.currentAudioSource) {
                try { this.currentAudioSource.stop(); } catch (_) {}
                this.currentAudioSource = null;
            }
            this.responseBuffer = '';
            this.fullResponseText = '';
            this.lastUserPrompt = text;
            this.responseComplete = false;
            this.hasStrippedInitialSpeakerPrefix = false;
            this.speechText = '';
            this.speechPlaybackPending = false;
            this.options.onSpeechProgress({ phase: 'reset', text: '', charIndex: 0 });
            const requestController = new AbortController();
            this.abortController = requestController;

            try {
                await this.options.onBeforeAsk(text);
                if (requestController.signal.aborted) return;

                const prompt = this.session.promptStreaming
                    ? this.session.promptStreaming(text, { signal: requestController.signal })
                    : this.session.prompt(text);

                if (this.session.promptStreaming) {
                    for await (const chunk of prompt) {
                        if (requestController.signal.aborted) return;
                        const value = this.extractChunk(chunk);
                        if (!value) continue;
                        this.responseBuffer += value;
                        this.fullResponseText += value;
                        this.options.onResponse({ text: this.fullResponseText, done: false });
                        this.speakCompleteSentences();
                    }
                } else {
                    this.fullResponseText = await prompt;
                    this.responseBuffer = this.fullResponseText;
                    this.options.onResponse({ text: this.fullResponseText, done: false });
                }

                this.responseComplete = true;
                if (this.fullResponseText.trim()) {
                    this.turnHistory.push({ role: 'user', content: text });
                    this.turnHistory.push({ role: 'assistant', content: this.fullResponseText.trim() });
                    if (this.turnHistory.length > MAX_TURN_HISTORY_MESSAGES) {
                        this.turnHistory = this.turnHistory.slice(-MAX_TURN_HISTORY_MESSAGES);
                    }
                }
                this.options.onResponse({ text: this.fullResponseText, done: true });
                this.speakRemaining();
                if (this.speaking) return;
                if (this.running && !this.options.manualMode) {
                    this.autoListenCooldown = Date.now() + 800;
                    this.setState('listening');
                    setTimeout(() => {
                        if (this.running && !this.options.manualMode && Date.now() >= this.autoListenCooldown) {
                            this.startListening();
                        }
                    }, 900);
                } else if (this.running) {
                    this.listening = false;
                    this.setState('idle');
                }
            } catch (error) {
                if (error.name !== 'AbortError') this.fail(error);
            } finally {
                if (this.abortController === requestController) {
                    this.abortController = null;
                }
            }
        }

        extractChunk(chunk) {
            if (typeof chunk === 'string') return chunk;
            if (typeof chunk === 'object') {
                return chunk.text || chunk.value || chunk.content || chunk.delta?.content || '';
            }
            return '';
        }

        speakCompleteSentences() {
            if (!this.hasStrippedInitialSpeakerPrefix && this.responseBuffer) {
                const cleaned = stripSpeakerPrefixForSpeech(this.responseBuffer);
                if (cleaned !== this.responseBuffer) {
                    this.responseBuffer = cleaned;
                    this.hasStrippedInitialSpeakerPrefix = true;
                } else if (this.responseBuffer.includes(':') || this.responseBuffer.length > 40) {
                    this.hasStrippedInitialSpeakerPrefix = true;
                }
            }
            // Batasan minimal pemenggalan: 1 kalimat utuh (tidak memenggal di tengah kalimat)
            const cleanBuffer = stripCodeForSpeech(this.responseBuffer);
            const { segments, remainder } = splitSpeechBuffer(cleanBuffer);
            this.responseBuffer = remainder;
            for (const sentence of segments) this.enqueueSpeech(sentence);

            if (this.responseBuffer.trim()) this.scheduleSpeechChunkFlush();
            else this.clearSpeechChunkTimer();
        }

        scheduleSpeechChunkFlush() {
            if (this.speechChunkTimer !== null || !this.responseBuffer.trim() || this.responseComplete) return;
            const timer = setTimeout(() => {
                if (this.speechChunkTimer !== timer) return;
                this.speechChunkTimer = null;
                if (this.responseComplete || !this.responseBuffer.trim()) return;
                if (this.responseBuffer.includes('`')) {
                    this.scheduleSpeechChunkFlush();
                    return;
                }

                if (!this.hasStrippedInitialSpeakerPrefix && this.responseBuffer) {
                    const cleaned = stripSpeakerPrefixForSpeech(this.responseBuffer);
                    if (cleaned !== this.responseBuffer) {
                        this.responseBuffer = cleaned;
                        this.hasStrippedInitialSpeakerPrefix = true;
                    }
                }

                // Hanya flush jika sudah terbentuk minimal 1 kalimat utuh
                const sentenceBoundary = findSentenceBoundary(this.responseBuffer, true);
                if (sentenceBoundary <= 0) return;

                const segment = this.responseBuffer.slice(0, sentenceBoundary).trim();
                this.responseBuffer = this.responseBuffer.slice(sentenceBoundary).trimStart();
                if (segment) this.enqueueSpeech(segment);
                this.scheduleSpeechChunkFlush();
            }, SPEECH_CHUNK_TIMEOUT_MS);
            this.speechChunkTimer = timer;
        }

        clearSpeechChunkTimer() {
            if (this.speechChunkTimer === null) return;
            clearTimeout(this.speechChunkTimer);
            this.speechChunkTimer = null;
        }

        speakRemaining() {
            this.clearSpeechChunkTimer();
            if (!this.hasStrippedInitialSpeakerPrefix && this.responseBuffer) {
                this.responseBuffer = stripSpeakerPrefixForSpeech(this.responseBuffer);
                this.hasStrippedInitialSpeakerPrefix = true;
            }
            const { segments } = splitSpeechBuffer(stripCodeForSpeech(this.responseBuffer, true), true);
            this.responseBuffer = '';
            for (const sentence of segments) this.enqueueSpeech(sentence);
        }

        enqueueSpeech(text) {
            const rawSpeech = stripSpeakerPrefixForSpeech(stripCodeForSpeech(String(text || ''), true));
            let speechText = rawSpeech
                .replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
                .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
                .replace(/^\s{0,3}#{1,6}\s+/gm, '')
                .replace(/^\s*>\s?/gm, '')
                .replace(/^\s*(?:[-*+]\s+|\d+[.)]\s+)/gm, '')
                .replace(/^\s*[-*_]{3,}\s*$/gm, '')
                .replace(/[|#*_~`]/g, '')
                .replace(/<[^>]+>/g, '')
                .replace(/[\p{Extended_Pictographic}\p{Emoji_Presentation}\p{Emoji_Modifier}\p{Regional_Indicator}\uFE0F\u200D]/gu, '')
                .replace(/\s{2,}/g, ' ')
                .replace(/\s+([,.!?;:])/g, '$1')
                .replace(/([,.!?;:])(?=\S)/g, '$1 ')
                .trim();

            if (!this.speechText && (this.turnHistory.length > 0 || !isUserGreetingOnly(this.lastUserPrompt))) {
                speechText = stripRepeatedGreetingForSpeech(speechText);
            }

            if (!speechText) return;

            const segmentStart = this.speechText.length ? this.speechText.length + 1 : 0;
            this.speechText = this.speechText ? `${this.speechText} ${speechText}` : speechText;
            const segmentEnd = this.speechText.length;

            const item = {
                text: speechText,
                segmentStart,
                segmentEnd,
                signal: this.abortController?.signal,
                localTtsRequested: this.options.useLocalTts,
                audioPromise: null
            };

            // Hanya prefetch langsung jika antrean kosong & belum ada yang sedang diputar (prioritas mutlak kalimat #1)
            if (item.localTtsRequested && !this.isPlayingQueue && this.audioQueue.length === 0) {
                item.audioPromise = this.preloadAudio(item.text, item.signal);
            }

            this.audioQueue.push(item);
            this.processAudioQueue();
        }

        speak(text) {
            this.enqueueSpeech(text);
        }

        async preloadAudio(speechText, signal) {
            if (!this.options.useLocalTts) return null;
            if (signal?.aborted) return null;
            speechText = stripSpeakerPrefixForSpeech(speechText).trim();
            if (!speechText) return null;
            try {
                const speaker = this.options.voiceURI || 'gadis';
                const style = this.options.voiceStyle || 'natural';
                const speed = this.options.voiceSpeed || 1.0;
                const origin = (typeof window !== 'undefined' && window.location && window.location.origin && window.location.origin !== 'null') ? window.location.origin : '';
                const queryParams = `text=${encodeURIComponent(speechText)}&speaker=${encodeURIComponent(speaker)}&style=${encodeURIComponent(style)}&speed=${speed}`;
                const candidateBases = [];
                if (this._workingTtsBase) candidateBases.push(this._workingTtsBase);
                if (origin && !candidateBases.includes(origin)) candidateBases.push(origin);
                if (!candidateBases.includes('http://127.0.0.1:8765')) candidateBases.push('http://127.0.0.1:8765');

                let res = null;
                for (const base of candidateBases) {
                    if (signal?.aborted) return null;
                    try {
                        const r = await fetch(`${base}/api/tts?${queryParams}`, { signal });
                        if (r.ok) {
                            this._workingTtsBase = base;
                            res = r;
                            break;
                        }
                    } catch (_) {}
                }
                if (!res || signal?.aborted) return null;
                const arrayBuffer = await res.arrayBuffer();
                if (signal?.aborted || !arrayBuffer || arrayBuffer.byteLength < 200) return null;

                const ctx = this.initAudioContext();
                if (!ctx) return null;
                if (ctx.state === 'suspended') {
                    await ctx.resume();
                }
                const audioBuffer = await ctx.decodeAudioData(arrayBuffer);
                if (signal?.aborted) return null;
                if (audioBuffer) {
                    // Normalisasi gain cepat (stride 4 untuk deteksi peak 4x lebih ringan)
                    for (let c = 0; c < audioBuffer.numberOfChannels; c++) {
                        const data = audioBuffer.getChannelData(c);
                        let peak = 0;
                        for (let i = 0; i < data.length; i += 4) {
                            const abs = Math.abs(data[i]);
                            if (abs > peak) peak = abs;
                        }
                        if (peak > 0.85) {
                            const scale = 0.78 / peak;
                            for (let i = 0; i < data.length; i++) {
                                data[i] *= scale;
                            }
                        }
                    }
                }
                return audioBuffer;
            } catch (err) {
                if (err.name !== 'AbortError') {
                    console.warn('Gagal preload audio buffer:', err);
                }
                return null;
            }
        }

        async processAudioQueue() {
            if (this.isPlayingQueue || !this.running) return;
            this.isPlayingQueue = true;

            while (this.audioQueue.length > 0 && this.running) {
                const item = this.audioQueue.shift();
                this.speechPlaybackPending = true;
                this.speaking = true;
                this.selfSpeechLock = true;
                this.ttsSuppressionUntil = Date.now() + 7000;
                this.recognition?.stop();
                this.listening = false;

                let audioBuffer = null;
                const localTtsRequested = item.localTtsRequested ?? this.options.useLocalTts;
                if (localTtsRequested && this.options.useLocalTts) {
                    if (!item.audioPromise) {
                        item.audioPromise = this.preloadAudio(item.text, item.signal);
                    }
                    try {
                        audioBuffer = await item.audioPromise;
                    } catch (e) {
                        console.warn('Gagal menunggu audioPromise:', e);
                    }
                }

                if (!this.running) break;
                if (item.signal?.aborted) continue;

                // Prefetch tepat 1 kalimat berikutnya selagi kalimat saat ini mulai diputar (gapless tanpa rebutan lock!)
                const nextItem = this.audioQueue[0];
                if (nextItem && (nextItem.localTtsRequested ?? this.options.useLocalTts) && this.options.useLocalTts && !nextItem.audioPromise) {
                    nextItem.audioPromise = this.preloadAudio(nextItem.text, nextItem.signal);
                }

                if (localTtsRequested && this.options.useLocalTts && audioBuffer) {
                    const played = await this.playAudioBuffer(audioBuffer, item);
                    if (!this.running || item.signal?.aborted) continue;
                    if (!played) {
                        this.switchToNativeTts(item);
                        this.playSystemSynthesis(item.text, item);
                    }
                } else if (localTtsRequested && this.options.useLocalTts) {
                    this.switchToNativeTts(item);
                    this.playSystemSynthesis(item.text, item);
                } else {
                    this.playSystemSynthesis(item.text, item);
                }
            }

            this.isPlayingQueue = false;
            this.finishAudioQueueIfIdle();
        }

        switchToNativeTts(item) {
            this.options.useLocalTts = false;
            console.warn('TTS lokal gagal; beralih ke Realtime Native.');
            this.options.onLocalTtsFallback({ text: item.text });
        }

        finishAudioQueueIfIdle() {
            if (this.isPlayingQueue || this.audioQueue.length || this.systemSpeechUtterances.size) return;

            this.speaking = false;
            this.selfSpeechLock = false;
            this.ttsSuppressionUntil = Date.now() + 280;
            this.autoListenCooldown = Date.now() + 240;

            if (this.running) {
                if (this.responseComplete && this.audioQueue.length === 0 && !this.responseBuffer.trim()) {
                    this.speechPlaybackPending = false;
                    this.options.onSpeechProgress({
                        phase: 'complete',
                        text: this.speechText,
                        charIndex: this.speechText.length
                    });

                    if (this.options.manualMode) {
                        this.listening = false;
                        this.setState('idle');
                    } else {
                        this.setState('listening');
                        setTimeout(() => {
                            const afterGap = Date.now() >= this.autoListenCooldown &&
                                Date.now() >= this.ttsSuppressionUntil &&
                                !this.selfSpeechLock && !this.speaking && this.running;
                            if (afterGap) this.startListening();
                        }, 330);
                    }
                }
            }
        }

        getMasterOutput() {
            const ctx = this.initAudioContext();
            if (!ctx) return null;

            if (!this.masterChain || this.masterChain.ctx !== ctx) {
                const gainNode = ctx.createGain();
                gainNode.gain.setValueAtTime(0.65, ctx.currentTime);
                gainNode.connect(ctx.destination);

                this.masterChain = { ctx, input: gainNode };
            }
            return this.masterChain.input;
        }

        async playAudioBuffer(audioBuffer, item) {
            const ctx = this.initAudioContext();
            if (!ctx) return false;
            if (ctx.state === 'suspended') {
                try {
                    await ctx.resume();
                } catch (error) {
                    console.warn('Gagal mengaktifkan AudioContext:', error);
                    return false;
                }
            }

            return new Promise((resolve) => {
                if (this.currentAudioSource) {
                    try { this.currentAudioSource.stop(); } catch (_) {}
                    this.currentAudioSource = null;
                }

                let source;
                let segmentGain;
                let startTime;
                try {
                    source = ctx.createBufferSource();
                    source.buffer = audioBuffer;
                    this.currentAudioSource = source;

                    segmentGain = ctx.createGain();
                    const masterInput = this.getMasterOutput();
                    source.connect(segmentGain);
                    segmentGain.connect(masterInput || ctx.destination);

                    startTime = ctx.currentTime + 0.01;
                    const endTime = startTime + audioBuffer.duration;
                    const fadeTime = Math.min(0.008, audioBuffer.duration / 2);
                    segmentGain.gain.setValueAtTime(0.0001, startTime);
                    segmentGain.gain.linearRampToValueAtTime(1, startTime + fadeTime);
                    segmentGain.gain.setValueAtTime(1, endTime - fadeTime);
                    segmentGain.gain.linearRampToValueAtTime(0.0001, endTime);
                } catch (error) {
                    console.warn('Gagal menyiapkan pemutaran TTS lokal:', error);
                    if (this.currentAudioSource === source) this.currentAudioSource = null;
                    try {
                        source?.disconnect();
                        segmentGain?.disconnect();
                    } catch (_) {}
                    resolve(false);
                    return;
                }

                this.speaking = true;
                this.setState('speaking');
                this.options.onSpeechProgress({
                    phase: 'start',
                    text: this.speechText,
                    charIndex: item.segmentStart,
                    wordStart: -1,
                    wordEnd: -1
                });

                source.onended = () => {
                    if (this.currentAudioSource === source) {
                        this.currentAudioSource = null;
                    }
                    try {
                        source.disconnect();
                        segmentGain.disconnect();
                    } catch (_) {}
                    this.options.onSpeechProgress({
                        phase: 'progress',
                        text: this.speechText,
                        charIndex: item.segmentEnd,
                        wordStart: -1,
                        wordEnd: -1
                    });
                    resolve(true);
                };

                try {
                    source.start(startTime);
                } catch (error) {
                    console.warn('Gagal memutar audio TTS lokal:', error);
                    if (this.currentAudioSource === source) this.currentAudioSource = null;
                    try {
                        source.disconnect();
                        segmentGain.disconnect();
                    } catch (_) {}
                    resolve(false);
                }
            });
        }

        playSystemSynthesis(text, item) {
            return new Promise((resolve) => {
                if (!window.speechSynthesis) {
                    this.options.onError(new Error('Realtime Native TTS tidak tersedia di browser ini.'));
                    resolve();
                    return;
                }
                const utterance = new SpeechSynthesisUtterance(text);
                utterance.lang = this.options.voiceLanguage || this.options.language;
                utterance.rate = 0.98;
                utterance.pitch = 1.0;
                utterance.volume = 1.0;

                const voices = window.speechSynthesis.getVoices();
                const selectedVoice = voices.find(voice => voice.voiceURI === this.options.voiceURI)
                    || voices.find(voice => voice.name === this.options.voiceName && voice.lang === this.options.voiceLanguage)
                    || voices.find(voice => voice.lang.toLowerCase().startsWith('id') && /google/i.test(voice.name))
                    || voices.find(voice => voice.lang.toLowerCase().startsWith('id'));
                if (selectedVoice) {
                    utterance.voice = selectedVoice;
                    utterance.lang = selectedVoice.lang || utterance.lang;
                }

                this.systemSpeechUtterances.add(utterance);
                this.speaking = true;
                this.setState('speaking');
                utterance.onstart = () => {
                    this.options.onSpeechProgress({
                        phase: 'start',
                        text: this.speechText,
                        charIndex: item.segmentStart,
                        wordStart: -1,
                        wordEnd: -1
                    });
                };

                const finish = () => {
                    if (!this.systemSpeechUtterances.delete(utterance)) {
                        resolve();
                        return;
                    }
                    this.options.onSpeechProgress({
                        phase: 'progress',
                        text: this.speechText,
                        charIndex: item.segmentEnd,
                        wordStart: -1,
                        wordEnd: -1
                    });
                    this.finishAudioQueueIfIdle();
                    resolve();
                };
                utterance.onend = finish;
                utterance.onerror = finish;
                try {
                    window.speechSynthesis.speak(utterance);
                } catch (error) {
                    this.systemSpeechUtterances.delete(utterance);
                    this.options.onError(error);
                    resolve();
                }
            });
        }

        setState(state) {
            this.options.onStateChange(state);
        }

        fail(error) {
            this.options.onError(error);
            this.setState('error');
        }
    }

    window.LiveConversationController = LiveConversationController;
})();
