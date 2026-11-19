const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const projectRoot = path.resolve(__dirname, '..');
const memoryManagerPath = path.join(projectRoot, 'nano_asset/assets/js/context-memory-manager.js');
const GemmaMemory = require(memoryManagerPath);

test('GemmaMemory exports required core methods', () => {
    assert.equal(typeof GemmaMemory.compactHistory, 'function');
    assert.equal(typeof GemmaMemory.buildPromptContext, 'function');
    assert.equal(typeof GemmaMemory.extractHeuristicSummary, 'function');
    assert.equal(typeof GemmaMemory.archiveToKnowledgeBase, 'function');
    assert.equal(typeof GemmaMemory.exportConversationAsMemoryDocument, 'function');
    assert.equal(typeof GemmaMemory.estimateTokens, 'function');
    assert.equal(typeof GemmaMemory.getContextBreakdown, 'function');
    assert.equal(typeof GemmaMemory.renderContextGauge, 'function');
});

test('compactHistory leaves history untouched if below threshold', async () => {
    const messages = [
        { role: 'user', text: 'Halo AI' },
        { role: 'assistant', text: 'Halo! Ada yang bisa saya bantu?' }
    ];

    const result = await GemmaMemory.compactHistory(messages, { thresholdTurns: 6 });
    assert.equal(result.compacted, false);
    assert.equal(result.messages.length, 2);
    assert.equal(result.evictedCount, 0);
});

test('compactHistory condenses older turns when exceeding threshold', async () => {
    const messages = [];
    for (let i = 1; i <= 14; i++) {
        messages.push({
            role: i % 2 === 1 ? 'user' : 'assistant',
            text: `Pesan nomor ${i} membahas modul pembelajaran ${i}`
        });
    }

    const result = await GemmaMemory.compactHistory(messages, {
        thresholdTurns: 10,
        keepRecentTurns: 4
    });

    assert.equal(result.compacted, true);
    assert.equal(result.messages.length, 4);
    assert.equal(result.evictedCount, 10);
    assert.ok(result.summary.length > 0);
    assert.match(result.summary, /Topik sebelumnya mencakup/i);
});

test('buildPromptContext properly prepends system prompt and session summary', () => {
    const recent = [
        { role: 'user', content: 'Lanjutkan langkah berikutnya.' },
        { role: 'assistant', content: 'Langkah selanjutnya adalah asesmen.' }
    ];

    const summary = 'Pengguna sedang merancang RPP Biologi Fase E Ekosistem.';
    const systemPrompt = 'Anda adalah asisten EduVis AI.';

    const context = GemmaMemory.buildPromptContext(recent, summary, systemPrompt);

    assert.equal(context.length, 4);
    assert.equal(context[0].role, 'system');
    assert.equal(context[0].content, 'Anda adalah asisten EduVis AI.');

    assert.equal(context[1].role, 'system');
    assert.match(context[1].content, /\[Konteks Pembahasan Sebelumnya\]:/);
    assert.match(context[1].content, /RPP Biologi Fase E Ekosistem/);

    assert.equal(context[2].role, 'user');
    assert.equal(context[3].role, 'assistant');
});

test('exportConversationAsMemoryDocument formats conversation into clean Markdown', () => {
    const messages = [
        { role: 'user', text: 'Buatkan modul ajar fotosintesis.' },
        { role: 'assistant', text: 'Berikut modul ajar fotosintesis:\n1. Reaksi terang\n2. Reaksi gelap' }
    ];

    const markdownDoc = GemmaMemory.exportConversationAsMemoryDocument(messages, 'Modul Fotosintesis');
    assert.match(markdownDoc, /# Dokumen Memori: Modul Fotosintesis/);
    assert.match(markdownDoc, /👤 Guru \/ Pengguna:/);
    assert.match(markdownDoc, /🤖 Asisten EduVis AI:/);
    assert.match(markdownDoc, /Reaksi terang/);
});

test('archiveToKnowledgeBase stores document metadata and vector chunks in IndexedDB mock', async () => {
    const mockStorage = {
        kb_files: new Map(),
        kb_chunks: new Map()
    };

    const mockDb = {
        transaction: (stores, mode) => {
            const storeName = Array.isArray(stores) ? stores[0] : stores;
            return {
                objectStore: (name) => ({
                    add: (record) => {
                        mockStorage[name].set(record.id, record);
                        const req = { onsuccess: null, onerror: null };
                        setTimeout(() => req.onsuccess?.({ target: { result: record.id } }), 0);
                        return req;
                    },
                    get: (id) => {
                        const req = { onsuccess: null, onerror: null };
                        setTimeout(() => req.onsuccess?.({ target: { result: mockStorage[name].get(id) } }), 0);
                        return req;
                    },
                    put: (record) => {
                        mockStorage[name].set(record.id, record);
                        const req = { onsuccess: null, onerror: null };
                        setTimeout(() => req.onsuccess?.({ target: { result: record.id } }), 0);
                        return req;
                    }
                })
            };
        }
    };

    const result = await GemmaMemory.archiveToKnowledgeBase(mockDb, {
        title: 'Modul Biologi Ekosistem',
        content: 'Paragraf pertama tentang rantai makanan.\n\nParagraf kedua tentang jaring-jaring makanan dan dekomposer.',
        extractEmbeddingFn: async (text) => new Array(384).fill(0.05)
    });

    assert.equal(result.success, true);
    assert.equal(result.title, 'Modul Biologi Ekosistem');
    assert.equal(mockStorage.kb_files.size, 1);
    assert.ok(mockStorage.kb_chunks.size >= 2);

    const fileRecord = Array.from(mockStorage.kb_files.values())[0];
    assert.equal(fileRecord.name, 'Modul Biologi Ekosistem');
    assert.equal(fileRecord.type, 'session_memory');

    const firstChunk = Array.from(mockStorage.kb_chunks.values())[0];
    assert.equal(firstChunk.embedding.length, 384);
});

test('chat pages load context-memory-manager.js and wire up memory management', () => {
    const pages = ['VS.html', 'claude.html', 'utama.html', 'utamaV2.html'];
    for (const page of pages) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        assert.match(
            source,
            /<script src="nano_asset\/assets\/js\/context-memory-manager\.js"><\/script>/,
            `${page} must include context-memory-manager.js`
        );
        assert.match(
            source,
            /checkAndCompactHistory\(\)/,
            `${page} must invoke checkAndCompactHistory in saveMessageToHistory`
        );
        assert.match(
            source,
            /archiveSessionToKnowledgeBase\(\)/,
            `${page} must define archiveSessionToKnowledgeBase`
        );
        assert.match(
            source,
            /\[Konteks Pembahasan Sebelumnya\]:/,
            `${page} must inject session summary into getChatHistoryFromDB`
        );
        assert.match(
            source,
            /archiveSessionToKnowledgeBase/,
            `${page} must have UI element triggering archiveSessionToKnowledgeBase`
        );
    }
});

test('WKWebView environment (no window.ai) produces valid summary via heuristic fallback', async () => {
    // In WKWebView on macOS, window.ai is undefined.
    // When no local HTTP server is reachable, summarizeWithFallback must use Tier 3 heuristic.
    const messages = [
        { role: 'user', text: 'Tolong buatkan modul ajar IPA materi fotosintesis kelas 7 SMP.' },
        { role: 'assistant', text: 'Berikut modul ajar IPA materi fotosintesis kelas 7:\n1. Pengertian klorofil\n2. Reaksi terang dan gelap\n3. Eksperimen Sachs' },
        { role: 'user', text: 'Tambahkan lembar kerja peserta didik (LKPD).' },
        { role: 'assistant', text: 'Berikut LKPD fotosintesis dengan lembar observasi dan pertanyaan pemandu.' }
    ];

    const summary = await GemmaMemory.summarizeWithFallback(messages, {
        existingSummary: '',
        apiBaseUrl: 'http://127.0.0.1:99999', // invalid / unreachable port to trigger fallback
        summaryTimeoutMs: 50
    });

    assert.ok(summary.length > 0);
    assert.match(summary, /Topik sebelumnya mencakup/i);
    assert.match(summary, /fotosintesis/i);
});

test('chat pages preserve sessionSummary and apply RAG relevance threshold', () => {
    const pages = ['VS.html', 'claude.html', 'utama.html', 'utamaV2.html'];
    for (const page of pages) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');

        // Verify sessionSummary in saveCurrentSession
        assert.match(
            source,
            /sessionSummary:\s*window\.__currentSessionSummary\s*\|\|\s*''/,
            `${page} must store sessionSummary in sessionData`
        );

        // Verify sessionSummary restoration in loadSession
        assert.match(
            source,
            /window\.__currentSessionSummary\s*=\s*session\.sessionSummary\s*\|\|\s*''/,
            `${page} must restore window.__currentSessionSummary in loadSession`
        );

        // Verify RAG relevance threshold
        assert.match(
            source,
            /scoredChunks\s*=\s*scoredChunks\.filter\(\s*c\s*=>\s*c\.score\s*>\s*0\.35\s*\)/,
            `${page} must filter scoredChunks with threshold 0.35`
        );

        // Verify stream line buffering in sendToOllama
        assert.match(
            source,
            /buffer\s*\+=\s*decoder\.decode\(value,\s*\{\s*stream:\s*true\s*\}\);[\s\S]*?const lines = buffer\.split\('\\n'\);[\s\S]*?buffer = lines\.pop\(\);/,
            `${page} must buffer partial lines across chunks in sendToOllama`
        );
    }
});

test('GemmaMemory estimateTokens calculates token count properly', () => {
    assert.equal(GemmaMemory.estimateTokens(''), 0);
    assert.equal(GemmaMemory.estimateTokens(null), 0);
    // 35 characters -> Math.ceil(35 / 3.5) = 10 tokens
    assert.equal(GemmaMemory.estimateTokens('12345678901234567890123456789012345'), 10);
});

test('GemmaMemory getContextBreakdown correctly evaluates green, yellow, and orange thresholds', () => {
    // 1. Green state (< 50%): Total tokens ~200 / 4096 = ~5%
    const greenMessages = [
        { role: 'user', content: 'Halo AI, apa kabar?' },
        { role: 'assistant', content: 'Halo! Saya baik dan siap membantu modul ajar.' }
    ];
    const greenBreakdown = GemmaMemory.getContextBreakdown(greenMessages, {
        maxTokens: 4096,
        systemPrompt: 'Anda adalah AI asisten.',
        sessionSummary: ''
    });
    assert.equal(greenBreakdown.state, 'green');
    assert.ok(greenBreakdown.percentage < 50);
    assert.equal(greenBreakdown.messageCount, 2);
    assert.ok(greenBreakdown.remainingTokens > 3000);

    // 2. Yellow state (50% - 75%): Total tokens ~2200 / 4096 = ~54%
    const longText = 'A'.repeat(7700);
    const yellowMessages = [{ role: 'user', content: longText }];
    const yellowBreakdown = GemmaMemory.getContextBreakdown(yellowMessages, {
        maxTokens: 4096,
        systemPrompt: 'Anda adalah AI asisten.',
        sessionSummary: 'Ringkasan sesi sebelumnya.'
    });
    assert.equal(yellowBreakdown.state, 'yellow');
    assert.ok(yellowBreakdown.percentage >= 50 && yellowBreakdown.percentage < 75);

    // 3. Orange state (> 75%): Total tokens ~3300 / 4096 = ~80%
    const veryLongText = 'B'.repeat(11200);
    const orangeMessages = [{ role: 'user', content: veryLongText }];
    const orangeBreakdown = GemmaMemory.getContextBreakdown(orangeMessages, {
        maxTokens: 4096,
        systemPrompt: 'Anda adalah AI asisten.',
        sessionSummary: 'Ringkasan sesi sebelumnya.'
    });
    assert.equal(orangeBreakdown.state, 'orange');
    assert.ok(orangeBreakdown.percentage >= 75);
    assert.ok(orangeBreakdown.remainingTokens < 1000);
});

test('GemmaMemory renderContextGauge updates element styling and tooltip across states', () => {
    function createMockElement() {
        const classes = new Set();
        const attributes = {};
        return {
            classList: {
                add: (...cls) => cls.forEach(c => classes.add(c)),
                remove: (...cls) => cls.forEach(c => classes.delete(c)),
                contains: (c) => classes.has(c),
                get classes() { return Array.from(classes); }
            },
            setAttribute: (name, val) => { attributes[name] = val; },
            getAttribute: (name) => attributes[name],
            innerHTML: '',
            textContent: ''
        };
    }

    // 1. Green state render
    const elGreen = createMockElement();
    const bdGreen = GemmaMemory.renderContextGauge(elGreen, [{ role: 'user', content: 'Halo' }], { maxTokens: 4096 });
    assert.equal(bdGreen.state, 'green');
    assert.ok(elGreen.innerHTML.includes('🟢'));
    assert.ok(elGreen.classList.contains('text-emerald-400'));
    assert.ok(elGreen.getAttribute('title').includes('Kapasitas Konteks KV-Cache'));
    assert.ok(elGreen.getAttribute('title').includes('• Sisa Anggaran Output AI:'));

    // 2. Yellow state render
    const elYellow = createMockElement();
    const bdYellow = GemmaMemory.renderContextGauge(elYellow, [{ role: 'user', content: 'X'.repeat(7500) }], { maxTokens: 4096 });
    assert.equal(bdYellow.state, 'yellow');
    assert.ok(elYellow.innerHTML.includes('🟡'));
    assert.ok(elYellow.classList.contains('text-amber-400'));

    // 3. Orange state render
    const elOrange = createMockElement();
    const bdOrange = GemmaMemory.renderContextGauge(elOrange, [{ role: 'user', content: 'Y'.repeat(12000) }], { maxTokens: 4096 });
    assert.equal(bdOrange.state, 'orange');
    assert.ok(elOrange.innerHTML.includes('🟠'));
    assert.ok(elOrange.classList.contains('text-orange-400'));
    assert.ok(elOrange.getAttribute('title').includes('⚠️ Peringatan: Auto-Compact Summary Buffer aktif'));
});

test('all chat interfaces provide context gauge pill and wire up updateContextViewer', () => {
    const pages = ['VS.html', 'claude.html', 'utama.html', 'utamaV2.html'];
    for (const page of pages) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');

        // Verify context-viewer-badge in markup
        assert.match(
            source,
            /id="context-viewer-badge"/,
            `${page} must include id="context-viewer-badge" in header`
        );

        // Verify updateContextViewer function definition
        assert.match(
            source,
            /function updateContextViewer\(\)/,
            `${page} must define updateContextViewer()`
        );

        // Verify updateContextViewer calls renderContextGauge
        assert.match(
            source,
            /GemmaMemory\.renderContextGauge\(/,
            `${page} updateContextViewer must call GemmaMemory.renderContextGauge`
        );

        // Verify invocations in lifecycle
        assert.match(
            source,
            /updateContextViewer\(\);/,
            `${page} must invoke updateContextViewer() in chat lifecycle`
        );
    }
});



test('getContextBreakdown counts only the history window actually sent to the model', () => {
    const history = Array.from({ length: 20 }, (_, i) => ({ role: i % 2 ? 'assistant' : 'user', text: 'x'.repeat(35) }));
    const full = GemmaMemory.getContextBreakdown(history, { maxTokens: 4096 });
    const windowed = GemmaMemory.getContextBreakdown(history, { maxTokens: 4096, historyWindow: 10, sessionSummary: 'Ringkasan.' });
    assert.equal(full.historyTokens, 200);
    assert.equal(windowed.historyTokens, 100);
    assert.equal(windowed.messageCount, 10);
    assert.equal(windowed.totalMessageCount, 20);
    assert.equal(windowed.hasSummary, true);
    assert.equal(full.hasSummary, false);
});

test('Context Inspector API is exported and safe to call outside a browser', () => {
    assert.equal(typeof GemmaMemory.openContextInspector, 'function');
    assert.equal(typeof GemmaMemory.closeContextInspector, 'function');
    assert.equal(typeof GemmaMemory.clearStoredSummary, 'function');
    assert.doesNotThrow(() => GemmaMemory.closeContextInspector());
});

test('chat pages wire Context Inspector actions (compact now / clear summary)', () => {
    for (const page of ['VS.html', 'claude.html', 'utama.html', 'utamaV2.html']) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        assert.match(source, /async function checkAndCompactHistory\(force = false\)/, `${page} must support forced compaction`);
        assert.match(source, /thresholdTurns: compactThreshold/, `${page} must use the force-aware threshold`);
        assert.match(source, /historyWindow:/, `${page} must pass the sent history window to the gauge`);
        assert.match(source, /onCompactNow: \(\) => checkAndCompactHistory\(true\)/, `${page} must wire Ringkas Sekarang`);
        assert.match(source, /onClearSummary: async \(\) => \{ await window\.GemmaMemory\.clearStoredSummary\(db\)/, `${page} must wire Hapus Ringkasan`);
    }
});
