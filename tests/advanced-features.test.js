const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const PLD = require('../nano_asset/assets/js/prompt-lookup-decoder.js');
const WorkerBridge = require('../nano_asset/assets/js/worker-bridge.js');
const MultimodalRAG = require('../nano_asset/assets/js/multimodal-rag.js');
const CacheGuard = require('../nano_asset/assets/js/kv-cache-guard.js');

test('Prompt Lookup Decoder (PLD) matches repeating n-grams from prompt correctly', () => {
    const prompt = 'Fungsi fotosintesis pada tumbuhan hijau menghasilkan oksigen dan glukosa dari air dan karbon dioksida dengan bantuan sinar matahari.';
    const generated = 'Proses tersebut menjelaskan bahwa fotosintesis pada tumbuhan hijau';

    const candidate = PLD.findCandidates(prompt, generated, { minGram: 3 });
    assert.ok(candidate, 'PLD should find matching candidate continuation');
    assert.match(candidate.toLowerCase(), /menghasilkan oksigen/, 'Candidate should predict the continuation from the prompt');
});

test('Prompt Lookup Decoder returns null safely for empty or non-matching inputs', () => {
    assert.equal(PLD.findCandidates('', 'teks'), null);
    assert.equal(PLD.findCandidates('prompt teks', ''), null);
    assert.equal(PLD.findCandidates('hanya teks ini', 'sesuatu yang sama sekali berbeda'), null);
});

test('Gemma Worker Bridge provides synchronous fallback when Worker is unavailable', async () => {
    const queryEmb = [0.1, 0.5, 0.8];
    const chunks = [
        { id: 1, text: 'Dokumen A', embedding: [0.1, 0.5, 0.8] },
        { id: 2, text: 'Dokumen B', embedding: [0.9, -0.2, 0.1] }
    ];

    const results = await WorkerBridge.searchHybrid(queryEmb, chunks, 'Dokumen', 2);
    assert.ok(Array.isArray(results), 'Results must be an array');
    assert.equal(results.length, 2);
    assert.ok(results[0].score > results[1].score, 'Closest embedding must be ranked first');

    const ping = await WorkerBridge.ping();
    assert.equal(ping, 'PONG');
});

test('Gemma Worker script exists and defines all required handlers', () => {
    const workerScript = fs.readFileSync(
        path.join(__dirname, '../nano_asset/assets/js/gemma-web-worker.js'),
        'utf8'
    );
    assert.match(workerScript, /HYBRID_VECTOR_SEARCH/);
    assert.match(workerScript, /BATCH_COSINE_SIMILARITY/);
    assert.match(workerScript, /SMART_CHUNK_TEXT/);
});

test('Multimodal RAG creates structured visual chunks and formats references cleanly', () => {
    const chunk = MultimodalRAG.createVisualChunk({
        fileName: 'Arsitektur_Gemma4.pdf',
        caption: 'Bagan Alur WebGPU dan MediaPipe Inference',
        page: 3,
        section: 'Arsitektur Sistem'
    });

    assert.equal(chunk.kind, 'visual');
    assert.equal(chunk.page, 3);
    assert.match(chunk.text, /Bagan Alur WebGPU/);

    const formattedContext = MultimodalRAG.formatMultimodalContext([
        { text: 'Penjelasan umum teks sistem', fileName: 'Dok1.txt', score: 0.95 },
        chunk
    ]);

    assert.match(formattedContext, /REFERENSI KNOWLEDGE BASE MULTIMODAL LOKAL/);
    assert.match(formattedContext, /Deskripsi Visual: Bagan Alur WebGPU/);
});

test('KV-Cache Guard determines optimal cache profile based on memory tiers', () => {
    const lowTier = CacheGuard.getRecommendedCacheProfile('Gemma 4 E2B', 4);
    assert.equal(lowTier.kvPrecision, 'int8');
    assert.equal(lowTier.maxTokens, 1024);

    const medTier = CacheGuard.getRecommendedCacheProfile('Gemma 4 E4B', 8);
    assert.equal(medTier.kvPrecision, 'fp8');
    assert.equal(medTier.maxTokens, 2048);

    const highTier = CacheGuard.getRecommendedCacheProfile('Gemma 4 12B', 32);
    assert.equal(highTier.maxTokens, 2048);
    assert.equal(highTier.tier, 'high');
});

test('KV-Cache Guard Sliding Window preserves essential turns and prevents OOM', () => {
    const turns = [
        { role: 'system', content: 'You are Gemma 4' },
        { role: 'user', content: 'Turn 1' },
        { role: 'assistant', content: 'Answer 1' },
        { role: 'user', content: 'Turn 2' },
        { role: 'assistant', content: 'Answer 2' },
        { role: 'user', content: 'Turn 3' },
        { role: 'assistant', content: 'Answer 3' },
        { role: 'user', content: 'Turn 4' },
        { role: 'assistant', content: 'Answer 4' },
        { role: 'user', content: 'Turn 5' },
        { role: 'assistant', content: 'Answer 5' }
    ];

    const trimmed = CacheGuard.applySlidingWindow(turns, {
        maxTurns: 6,
        preserveFirst: 1,
        preserveRecent: 2
    });

    assert.equal(trimmed[0].role, 'system', 'First turn (system) must be preserved');
    assert.match(trimmed[1].content, /ringkas demi menjaga kestabilan memori/, 'Notice turn must explain trimming');
    assert.equal(trimmed[trimmed.length - 1].content, 'Answer 5', 'Most recent turn must be preserved');
});

test('KV-Cache Guard estimates memory in Megabytes correctly', () => {
    const memoryMB = CacheGuard.estimateKVCacheMemoryMB(2048, 2048, 18, 'int8');
    assert.ok(parseFloat(memoryMB) > 0);
    assert.equal(typeof memoryMB, 'string');
});

test('AI Response Engine exists and exports required methods and helpers', () => {
    const engineCode = fs.readFileSync(
        path.join(__dirname, '../nano_asset/assets/js/ai-response-engine.js'),
        'utf8'
    );
    assert.match(engineCode, /window\.AIResponseEngine\s*=/);
    assert.match(engineCode, /renderMd:/);
    assert.match(engineCode, /initializeVisuals:/);
    assert.match(engineCode, /createStreamRenderer:/);
    assert.match(engineCode, /safeMathMarkup/);
});

test('PWA manifest exists, is valid JSON, and is allowed by gemma_chat_gui.py', () => {
    const manifestPath = path.join(__dirname, '../manifest.webmanifest');
    assert.ok(fs.existsSync(manifestPath), 'manifest.webmanifest must exist');
    const content = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    assert.equal(content.short_name, 'Tanya AI');
    assert.equal(content.display, 'standalone');

    const guiPy = fs.readFileSync(path.join(__dirname, '../gemma_chat_gui.py'), 'utf8');
    assert.match(guiPy, /"manifest\.webmanifest"/);
});

test('Workspace HTML pages support mobile keyboard with interactive-widget viewport', () => {
    const pages = [
        'tanya-ai-standalone.html', 'claude.html', 'utama.html', 'aurora.html', 'VS.html',
        'index.html', 'agen-ai-otonom.html', 'ai-liquid-glass.html', 'analisis-kode.html',
        'eduVis.html', 'eduVisw.html', 'gemini_live.html', 'id.html', 'index2.html',
        'liquid_chatbot.html', 'mesin-pglite-rag.html', 'utamaV2.html', 'vision_ulti.html'
    ];
    for (const page of pages) {
        const html = fs.readFileSync(path.join(__dirname, '..', page), 'utf8');
        assert.match(html, /interactive-widget=resizes-content/, `${page} must support interactive-widget`);
        assert.match(html, /apple-mobile-web-app-capable/, `${page} must support mobile web app capable`);
    }
});
