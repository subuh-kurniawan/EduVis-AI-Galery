const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(
    path.join(__dirname, '..', 'live-conversation.js'),
    'utf8'
);
const screenWakeLockSource = fs.readFileSync(
    path.join(__dirname, '..', 'nano_asset', 'assets', 'js', 'screen-wake-lock.js'),
    'utf8'
);
const livePage = fs.readFileSync(
    path.join(__dirname, '..', 'gemini_live.html'),
    'utf8'
);
const futuristicLivePage = fs.readFileSync(
    path.join(__dirname, '..', 'gemini_live_futuristik.html'),
    'utf8'
);

function createController(fetch, extraWindow = {}, controllerOptions = {}, extraGlobals = {}) {
    const window = {
        location: { origin: 'http://127.0.0.1:1234' },
        addEventListener() {},
        ...extraWindow
    };
    vm.runInNewContext(source, {
        window,
        fetch,
        console,
        setTimeout: () => ({}),
        clearTimeout() {},
        ...extraGlobals
    });
    return new window.LiveConversationController({ useLocalTts: true, ...controllerOptions });
}

function createTimerHarness() {
    const timers = [];
    return {
        timers,
        setTimeout(callback, delay) {
            const timer = { callback, delay, cancelled: false };
            timers.push(timer);
            return timer;
        },
        clearTimeout(timer) {
            if (timer) timer.cancelled = true;
        }
    };
}

function getVoiceGender(voice) {
    const window = { addEventListener() {} };
    vm.runInNewContext(source, { window, fetch: async () => null, console });
    return window.LiveConversationController.getVoiceGender(voice);
}

test('interrupting a response aborts its in-flight local TTS request', async () => {
    let requestSignal;
    const controller = new AbortController();
    const conversation = createController((url, options) => new Promise((resolve, reject) => {
        requestSignal = options.signal;
        options.signal.addEventListener('abort', () => {
            reject(Object.assign(new Error('aborted'), { name: 'AbortError' }));
        }, { once: true });
    }));

    const pendingAudio = conversation.preloadAudio('Kalimat yang akan dibacakan.', controller.signal);
    controller.abort();

    assert.equal(await pendingAudio, null);
    assert.equal(requestSignal.aborted, true);
});

test('conversation instructions and selected persona are sent as a system message', async () => {
    let requestBody;
    const conversation = createController(async (_url, options) => {
        requestBody = JSON.parse(options.body);
        throw new Error('stop after capturing request');
    }, {}, {
        systemPrompt: 'Anda adalah EduVis Konsultan.',
        personaPrompt: 'Gunakan gaya komunikasi profesional.'
    }, { console: { warn() {} } });

    for await (const _chunk of conversation.createSession().promptStreaming('Jelaskan topik ini.')) {}

    assert.equal(requestBody.messages[0].role, 'system');
    assert.match(requestBody.messages[0].content, /EduVis Konsultan/u);
    assert.match(requestBody.messages[0].content, /komunikasi profesional/u);
    assert.equal(requestBody.messages[1].role, 'user');
});

test('explicit role-change requests extract a custom persona without matching identity questions', () => {
    const conversation = createController(async () => null);
    const extractRole = conversation.constructor.extractPersonaChangeRequest;

    assert.equal(extractRole('Ganti peran AI menjadi tutor matematika.'), 'tutor matematika');
    assert.equal(extractRole('Mulai sekarang, berperan sebagai konsultan hukum.'), 'konsultan hukum');
    assert.equal(extractRole('Act as a science teacher.'), 'a science teacher');
    assert.equal(extractRole('Siapa nama Anda?'), null);
});

test('an aborted queued speech segment does not fall back to stale system speech', async () => {
    const conversation = createController(async () => {
        throw new Error('TTS should not be requested for an aborted item');
    });
    const controller = new AbortController();
    controller.abort();
    let fallbackPlayed = false;

    conversation.running = true;
    conversation.playSystemSynthesis = async () => {
        fallbackPlayed = true;
    };
    conversation.audioQueue.push({
        text: 'Teks lama.',
        signal: controller.signal,
        audioPromise: Promise.resolve(null)
    });

    await conversation.processAudioQueue();

    assert.equal(fallbackPlayed, false);
    assert.equal(conversation.isPlayingQueue, false);
});

test('local TTS failure switches the active response and later segments to native speech', async () => {
    const conversation = createController(async () => null);
    const nativeSpeech = [];
    let localPreloadRequests = 0;
    let fallbackCount = 0;

    conversation.running = true;
    conversation.playSystemSynthesis = async text => nativeSpeech.push(text);
    conversation.preloadAudio = async () => {
        localPreloadRequests += 1;
        return null;
    };
    conversation.options.onLocalTtsFallback = () => {
        fallbackCount += 1;
        conversation.enqueueSpeech('Kalimat berikutnya.');
    };
    conversation.audioQueue.push({
        text: 'TTS lokal gagal.',
        localTtsRequested: true,
        audioPromise: Promise.resolve(null)
    });

    await conversation.processAudioQueue();

    assert.deepEqual(nativeSpeech, ['TTS lokal gagal.', 'Kalimat berikutnya.']);
    assert.equal(conversation.options.useLocalTts, false);
    assert.equal(localPreloadRequests, 0);
    assert.equal(fallbackCount, 1);
});

test('local audio playback failure falls back to native speech', async () => {
    const conversation = createController(async () => null);
    const nativeSpeech = [];
    let fallbackCount = 0;

    conversation.running = true;
    conversation.playAudioBuffer = async () => false;
    conversation.playSystemSynthesis = async text => nativeSpeech.push(text);
    conversation.options.onLocalTtsFallback = () => {
        fallbackCount += 1;
    };
    conversation.audioQueue.push({
        text: 'Audio lokal tidak dapat diputar.',
        localTtsRequested: true,
        audioPromise: Promise.resolve({})
    });

    await conversation.processAudioQueue();

    assert.deepEqual(nativeSpeech, ['Audio lokal tidak dapat diputar.']);
    assert.equal(conversation.options.useLocalTts, false);
    assert.equal(fallbackCount, 1);
});

test('automatic speech recognition restarts after an empty recognition session', () => {
    const timers = createTimerHarness();
    const states = [];
    class FakeRecognition {
        start() {
            this.startCalls = (this.startCalls || 0) + 1;
        }

        stop() {}
    }
    const conversation = createController(
        async () => null,
        { SpeechRecognition: FakeRecognition },
        { manualMode: false, onStateChange: state => states.push(state) },
        timers
    );
    conversation.running = true;
    conversation.createRecognition();

    conversation.recognition.onend();

    assert.equal(states.at(-1), 'listening');
    assert.equal(timers.timers.length, 1);
    timers.timers[0].callback();
    assert.equal(conversation.recognition.startCalls, 1);
});

test('speech recognition starts synchronously during a microphone activation', () => {
    class FakeRecognition {
        start() {
            this.startCalls = (this.startCalls || 0) + 1;
        }

        stop() {}
    }
    const conversation = createController(
        async () => null,
        { SpeechRecognition: FakeRecognition },
        { manualMode: false }
    );

    conversation.start();

    assert.equal(conversation.running, true);
    assert.equal(conversation.recognition.startCalls, 1);
});

test('speech recognition does not restart after submitting a final transcript', () => {
    const timers = createTimerHarness();
    const states = [];
    class FakeRecognition {
        start() {}
        stop() {}
    }
    const conversation = createController(
        async () => null,
        { SpeechRecognition: FakeRecognition },
        { manualMode: false, onStateChange: state => states.push(state) },
        timers
    );
    conversation.running = true;
    conversation.createRecognition();
    conversation.finalTranscript = 'Halo';

    conversation.recognition.onend();

    assert.equal(states.at(-1), 'thinking');
    assert.equal(timers.timers.length, 0);
});

test('local audio playback uses one output path and click-safe segment fades', async () => {
    const automation = [];
    const connections = [];
    const fakeParam = {
        value: 1,
        setValueAtTime(value, time) {
            automation.push(['set', value, time]);
        },
        linearRampToValueAtTime(value, time) {
            automation.push(['ramp', value, time]);
        }
    };
    const createNode = () => ({
        connections: [],
        connect(node) {
            this.connections.push(node);
            connections.push([this, node]);
        },
        disconnect() {},
        gain: { ...fakeParam },
        threshold: { ...fakeParam },
        knee: { ...fakeParam },
        ratio: { ...fakeParam },
        attack: { ...fakeParam },
        release: { ...fakeParam }
    });
    const context = {
        state: 'suspended',
        currentTime: 4,
        destination: {},
        sources: [],
        async resume() {
            this.state = 'running';
        },
        createGain: createNode,
        createDynamicsCompressor() {
            throw new Error('Local WAV playback should not use a dynamics compressor');
        },
        createBufferSource() {
            const sourceNode = createNode();
            sourceNode.start = time => {
                sourceNode.startTime = time;
                sourceNode.onended();
            };
            this.sources.push(sourceNode);
            return sourceNode;
        }
    };
    const analyser = { context };
    const conversation = createController(async () => null, {
        __eduvisAudioContext: context,
        __eduvisAudioAnalyser: analyser
    });

    await conversation.playAudioBuffer({ duration: 1 }, {
        segmentStart: 0,
        segmentEnd: 10
    });

    const sourceNode = context.sources[0];
    assert.equal(context.state, 'running');
    assert.equal(sourceNode.connections.length, 1);
    assert.notEqual(sourceNode.connections[0], analyser);
    assert.equal(sourceNode.startTime, 4.01);
    assert.ok(automation.some(([type, value]) => type === 'set' && value === 0.65));
    assert.ok(automation.some(([type, value]) => type === 'ramp' && value === 0.0001));
});

test('Gemini Live visualizer does not route microphone analysis to speaker output', () => {
    assert.match(livePage, /audioMicSource\.connect\(audioAnalyser\)/);
    assert.doesNotMatch(livePage, /audioAnalyser\.connect\(audioCtx\.destination\)/);
});

test('Gemini Live settings are scrollable and the history drawer escapes the app stacking context', () => {
    assert.match(livePage, /id="settings-modal"[^>]*role="dialog"[^>]*aria-modal="true"/);
    assert.match(livePage, /\.settings-modal-panel\s*\{[^}]*overflow-y:\s*auto/s);
    assert.match(livePage, /\.settings-modal\s*\{\s*z-index:\s*70\s*;/);
    assert.match(livePage, /@media \(max-width: 440px\)\s*\{\s*\.topbar \{ flex-wrap: wrap;/);
    assert.match(livePage, /<textarea id="litert-endpoint" rows="2" readonly/);
    assert.match(livePage, /<\/main>\s*<\/div>\s*<!-- RIGHT SIDEBAR -->\s*<aside class="rightbar glass">/);
    assert.match(livePage, /if \(event\.key === 'Escape'\) \{\s*if \(settingsModal && !settingsModal\.classList\.contains\('hidden'\)\)/);
});

test('futuristic Gemini Live can submit text through the shared response controller', () => {
    assert.match(futuristicLivePage, /<form class="composer" id="chatForm"/);
    assert.match(futuristicLivePage, /<input id="chatInput" type="text"/);
    assert.match(futuristicLivePage, /\$\('chatForm'\)\.addEventListener\('submit', submitTextMessage\)/);
    assert.match(futuristicLivePage, /await liveAI\.ask\(text\)/);
    assert.match(futuristicLivePage, /window\.location\.port === '1236' \? '1236' : '1234'/);
    assert.match(futuristicLivePage, /new URLSearchParams\(window\.location\.search\)\.get\('model'\)/);
    assert.match(futuristicLivePage, /<section class="card voice"[\s\S]*?<form class="composer" id="chatForm"/);
    assert.match(futuristicLivePage, /id="responsePreview" aria-live="polite"/);
    assert.match(futuristicLivePage, /responsePreview\.textContent = data\.text/);
});

test('futuristic settings and conversation use the reference modal and drawer layout', () => {
    assert.match(futuristicLivePage, /id="settings-toggle"/);
    assert.match(futuristicLivePage, /id="settings-modal" class="settings-modal" role="dialog" aria-modal="true"/);
    assert.match(futuristicLivePage, /id="history-toggle"/);
    assert.match(futuristicLivePage, /<aside class="rightbar card" id="conversation-drawer"/);
    assert.match(futuristicLivePage, /<div id="history-backdrop" class="history-backdrop"/);
    assert.match(futuristicLivePage, /function setSettingsModalOpen\(/);
    assert.match(futuristicLivePage, /function setHistoryOpen\(/);
    assert.match(futuristicLivePage, /\.rightbar\.open\{transform:translateX\(0\);opacity:1;pointer-events:auto\}/);
    assert.match(futuristicLivePage, /\.settings-modal\.open\{display:flex\}/);
    assert.match(futuristicLivePage, /@media \(max-width:900px\)\{[\s\S]*?html,body\{height:100%;overflow:hidden\}[\s\S]*?\.app\{[^}]*100dvh[^}]*\}[\s\S]*?\.dock\{position:fixed;[^}]*\}/);
});

test('futuristic Live shows the selected voice persona while speaking', () => {
    assert.match(futuristicLivePage, /<img class="speaking-avatar" id="speakingAvatar"/);
    assert.match(futuristicLivePage, /assistantName === 'Narendra' \? 'narendra' : 'arsi'/);
    assert.match(futuristicLivePage, /avatar-orb-\$\{persona\}-speaking\.svg/);
    assert.match(futuristicLivePage, /if \(s === 'speaking'\) showSpeakingAvatar\(\)/);

    for (const persona of ['arsi', 'narendra']) {
        const avatarPath = path.join(
            __dirname,
            '..',
            'nano_asset',
            'assets',
            'avatars',
            `avatar-orb-${persona}-speaking.svg`
        );
        assert.ok(fs.existsSync(avatarPath), `Missing ${persona} speaking avatar`);
        assert.match(fs.readFileSync(avatarPath, 'utf8'), /<svg[\s>]/);
    }
});

test('Gemini Live keeps its voice persona visible with state-specific animations', () => {
    assert.match(livePage, /<img class="assistant-avatar" id="assistantAvatar"/);
    assert.match(livePage, /assistantName === 'Narendra' \? 'narendra' : 'arsi'/);
    assert.match(livePage, /avatar-orb-\$\{persona\}\.svg/);
    assert.match(livePage, /orb\.className = `orb \$\{state\}`;\s*showAvatar\(\)/);

    for (const state of ['idle', 'listening', 'thinking', 'speaking', 'error']) {
        assert.ok(livePage.includes(`.orb.has-avatar.${state} .assistant-avatar`));
    }

    for (const persona of ['arsi', 'narendra']) {
        const avatarPath = path.join(
            __dirname,
            '..',
            'nano_asset',
            'assets',
            'avatars',
            `avatar-orb-${persona}.svg`
        );
        assert.ok(fs.existsSync(avatarPath), `Missing static ${persona} avatar`);
        const avatarSvg = fs.readFileSync(avatarPath, 'utf8');
        assert.match(avatarSvg, /<svg[\s>]/);
        assert.doesNotMatch(avatarSvg, /<animate(?:Transform)?\b|<g transform="translate\(160, 246\)"/);
    }
});

test('both Gemini Live pages load the screen wake lock helper', () => {
    assert.match(livePage, /nano_asset\/assets\/js\/screen-wake-lock\.js/);
    assert.match(futuristicLivePage, /nano_asset\/assets\/js\/screen-wake-lock\.js/);
});

test('screen wake lock releases while hidden and reacquires when visible', async () => {
    const documentEvents = {};
    const windowEvents = {};
    const warnings = [];
    let requestCount = 0;
    let releaseCount = 0;
    const document = {
        visibilityState: 'visible',
        documentElement: { dataset: {} },
        addEventListener(type, callback) {
            documentEvents[type] = callback;
        }
    };
    const window = {
        addEventListener(type, callback) {
            windowEvents[type] = callback;
        }
    };
    const navigator = {
        wakeLock: {
            async request(type) {
                assert.equal(type, 'screen');
                requestCount += 1;
                let releaseListener;
                return {
                    released: false,
                    addEventListener(type, callback) {
                        if (type === 'release') releaseListener = callback;
                    },
                    async release() {
                        if (this.released) return;
                        this.released = true;
                        releaseCount += 1;
                        releaseListener?.();
                    }
                };
            }
        }
    };
    const flushPromises = () => new Promise(resolve => setImmediate(resolve));

    vm.runInNewContext(screenWakeLockSource, {
        document,
        window,
        navigator,
        console: { warn: (...args) => warnings.push(args) }
    });
    await flushPromises();
    assert.equal(requestCount, 1);
    assert.equal(document.documentElement.dataset.screenWakeLock, 'active');

    document.visibilityState = 'hidden';
    documentEvents.visibilitychange();
    await flushPromises();
    assert.equal(releaseCount, 1);
    assert.equal(document.documentElement.dataset.screenWakeLock, 'inactive');

    document.visibilityState = 'visible';
    documentEvents.visibilitychange();
    await flushPromises();
    assert.equal(requestCount, 2);
    assert.equal(document.documentElement.dataset.screenWakeLock, 'active');

    windowEvents.pagehide();
    await flushPromises();
    assert.equal(releaseCount, 2);
    assert.equal(document.documentElement.dataset.screenWakeLock, 'inactive');
    assert.deepEqual(warnings, []);
});

test('unsupported screen wake lock is reported without throwing', async () => {
    const documentEvents = {};
    const document = {
        visibilityState: 'visible',
        documentElement: { dataset: {} },
        addEventListener(type, callback) {
            documentEvents[type] = callback;
        }
    };
    const warnings = [];
    vm.runInNewContext(screenWakeLockSource, {
        document,
        window: { addEventListener() {} },
        navigator: {},
        console: { warn: (...args) => warnings.push(args) }
    });
    await new Promise(resolve => setImmediate(resolve));

    assert.equal(document.documentElement.dataset.screenWakeLock, 'unsupported');
    documentEvents.pointerdown();
    assert.equal(warnings.length, 1);
});

test('selected local and system voice metadata resolves the assistant name gender', () => {
    assert.equal(getVoiceGender({ id: 'ardi', gender: 'male' }), 'male');
    assert.equal(getVoiceGender({ id: 'gadis' }), 'female');
    assert.equal(getVoiceGender({ name: 'Daniel', lang: 'en-GB' }), 'male');
    assert.equal(getVoiceGender({ name: 'Damayanti', lang: 'id-ID' }), 'female');
    assert.equal(getVoiceGender({ id: 'piper-news', gender: 'unknown' }), 'unknown');
});

test('system speech uses the selected Indonesian voice at a conversational pace', async () => {
    const damayanti = {
        voiceURI: 'com.apple.speech.synthesis.voice.damayanti',
        name: 'Damayanti',
        lang: 'id-ID'
    };
    let spokenUtterance;
    class FakeSpeechSynthesisUtterance {
        constructor(text) {
            this.text = text;
        }
    }
    const speechSynthesis = {
        getVoices: () => [damayanti],
        speak(utterance) {
            spokenUtterance = utterance;
            utterance.onend();
        }
    };
    const conversation = createController(
        async () => null,
        { speechSynthesis },
        { voiceURI: damayanti.voiceURI, voiceName: damayanti.name, voiceLanguage: damayanti.lang },
        { SpeechSynthesisUtterance: FakeSpeechSynthesisUtterance }
    );

    await conversation.playSystemSynthesis('Halo, saya Arsi.', {
        segmentStart: 0,
        segmentEnd: 17
    });

    assert.equal(spokenUtterance.voice, damayanti);
    assert.equal(spokenUtterance.lang, 'id-ID');
    assert.ok(spokenUtterance.rate >= 0.95 && spokenUtterance.rate <= 1.05);
    assert.equal(spokenUtterance.pitch, 1);
});

test('realtime system speech queues ready sentences without waiting between utterances', async () => {
    const utterances = [];
    class FakeSpeechSynthesisUtterance {
        constructor(text) {
            this.text = text;
        }
    }
    const speechSynthesis = {
        getVoices: () => [],
        speak(utterance) {
            utterances.push(utterance);
        }
    };
    const conversation = createController(
        async () => null,
        { speechSynthesis },
        { useLocalTts: false },
        { SpeechSynthesisUtterance: FakeSpeechSynthesisUtterance }
    );
    conversation.running = true;
    conversation.responseComplete = true;
    conversation.speechText = 'Kalimat satu. Kalimat dua.';
    conversation.audioQueue.push(
        { text: 'Kalimat satu.', segmentStart: 0, segmentEnd: 13, audioPromise: Promise.resolve(null) },
        { text: 'Kalimat dua.', segmentStart: 14, segmentEnd: 26, audioPromise: Promise.resolve(null) }
    );

    await conversation.processAudioQueue();

    assert.equal(utterances.length, 2);
    assert.equal(conversation.systemSpeechUtterances.size, 2);
    assert.equal(conversation.speaking, true);

    utterances[0].onstart();
    utterances[0].onend();
    assert.equal(conversation.speaking, true);
    utterances[1].onstart();
    utterances[1].onend();
    assert.equal(conversation.speaking, false);
    assert.equal(conversation.speechPlaybackPending, false);
});

test('local TTS sentence splitting respects abbreviations, decimals and closing quotes', () => {
    const conversation = createController(async () => null);
    const segments = [];
    conversation.enqueueSpeech = text => segments.push(text);
    conversation.responseBuffer = 'Dr. Sari memakai versi 3.14. Ia berkata, “Sudah selesai!” Berikutnya, gunakan daftar dll. K.H. Ahmad hadir. Terima kasih.';

    conversation.speakCompleteSentences();

    assert.deepEqual(segments, [
        'Dr. Sari memakai versi 3.14.',
        'Ia berkata, “Sudah selesai!”',
        'Berikutnya, gunakan daftar dll.',
        'K.H. Ahmad hadir.'
    ]);
    assert.equal(conversation.responseBuffer, 'Terima kasih.');

    conversation.speakRemaining();
    assert.equal(segments[4], 'Terima kasih.');
});

test('long local TTS segments prefer clause punctuation over arbitrary cuts', () => {
    const conversation = createController(async () => null);
    const segments = [];
    conversation.enqueueSpeech = text => segments.push(text);
    conversation.responseBuffer = `${'kata '.repeat(24)}dan lainnya, ${'penjelasan '.repeat(8)}`;

    conversation.speakCompleteSentences();

    assert.equal(segments.length, 1);
    assert.ok(segments[0].endsWith(','));
    assert.match(conversation.responseBuffer, /^penjelasan/u);
});

test('local TTS flushes a safe partial phrase after the streaming timeout', () => {
    const timers = createTimerHarness();
    const conversation = createController(async () => null, {}, {}, timers);
    const segments = [];
    conversation.enqueueSpeech = text => segments.push(text);
    conversation.responseBuffer = 'Saya akan menjelaskan cara ini, karena model memerlukan data';

    conversation.speakCompleteSentences();

    assert.equal(segments.length, 0);
    assert.equal(timers.timers[0].delay, 500);
    timers.timers[0].callback();

    assert.deepEqual(segments, ['Saya akan menjelaskan cara ini,']);
    assert.equal(conversation.responseBuffer, 'karena model memerlukan data');
    assert.equal(timers.timers.length, 2);
});

test('local TTS waits for the minimum phrase length before timeout flushing', () => {
    const timers = createTimerHarness();
    const conversation = createController(async () => null, {}, {}, timers);
    const segments = [];
    conversation.enqueueSpeech = text => segments.push(text);
    conversation.responseBuffer = 'Saya akan';

    conversation.speakCompleteSentences();
    timers.timers[0].callback();

    assert.deepEqual(segments, []);
    assert.equal(conversation.responseBuffer, 'Saya akan');
    assert.equal(timers.timers.length, 1);

    conversation.responseBuffer += ' menjelaskan cara ini, sekarang';
    conversation.speakCompleteSentences();
    timers.timers[1].callback();

    assert.deepEqual(segments, ['Saya akan menjelaskan cara ini,']);
    assert.equal(conversation.responseBuffer, 'sekarang');
});

test('local TTS does not split a long sentence at an arbitrary word boundary', () => {
    const timers = createTimerHarness();
    const conversation = createController(async () => null, {}, {}, timers);
    const segments = [];
    conversation.enqueueSpeech = text => segments.push(text);
    const sentence = 'kata '.repeat(40).trim();
    conversation.responseBuffer = sentence;

    conversation.speakCompleteSentences();
    timers.timers[0].callback();

    assert.deepEqual(segments, []);
    assert.equal(conversation.responseBuffer, sentence);

    conversation.responseBuffer += '. ';
    conversation.speakCompleteSentences();

    assert.deepEqual(segments, [`${sentence}.`]);
    assert.equal(conversation.responseBuffer, '');
    assert.equal(conversation.responseBuffer, '');
});

test('stopping a conversation cancels its pending speech chunk timer', () => {
    const timers = createTimerHarness();
    const conversation = createController(async () => null, {}, {}, timers);
    conversation.responseBuffer = 'Teks streaming belum selesai';
    conversation.speakCompleteSentences();

    const pendingTimer = timers.timers[0];
    conversation.stop();
    pendingTimer.callback();

    assert.equal(pendingTimer.cancelled, true);
    assert.equal(conversation.responseBuffer, 'Teks streaming belum selesai');
});
