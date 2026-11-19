const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const projectRoot = path.resolve(__dirname, '..');

const metricsPath = path.join(projectRoot, 'nano_asset/assets/js/generation-metrics.js');
const storagePath = path.join(projectRoot, 'nano_asset/assets/js/opfs-storage-manager.js');
const toolsPath = path.join(projectRoot, 'nano_asset/assets/js/local-tools-engine.js');
const ttsPath = path.join(projectRoot, 'nano_asset/assets/js/offline-tts.js');

test('Generation Metrics calculates TTFT, TPS, and renders badge markup', () => {
    assert.equal(fs.existsSync(metricsPath), true, 'generation-metrics.js must exist');
    const GemmaMetrics = require(metricsPath);

    const tracker = GemmaMetrics.createTracker('Halo Gemma');
    assert.ok(tracker);
    assert.equal(tracker.tokenCount, 0);

    // Simulate receiving chunks
    tracker.recordChunk('Halo! Ada yang bisa');
    assert.ok(tracker.firstTokenTime !== null);
    assert.ok(tracker.tokenCount > 0);

    tracker.recordChunk(' saya bantu hari ini?');
    const stats = tracker.finish();

    assert.ok(stats.tokenCount > 0);
    assert.ok(stats.charCount > 0);
    assert.ok(typeof stats.ttftMs === 'number');
    assert.ok(typeof stats.tps === 'number');
    assert.ok(typeof stats.durationSec === 'number');

    const badge = GemmaMetrics.renderMetricBadge(stats);
    assert.match(badge, /gemma-metric-badge/);
    assert.match(badge, /tok\/s/);
    assert.match(badge, /TTFT:/);
});

test('OPFS Storage Manager formats bytes and generates modal UI structure', async () => {
    assert.equal(fs.existsSync(storagePath), true, 'opfs-storage-manager.js must exist');
    const GemmaStorageManager = require(storagePath);

    assert.equal(GemmaStorageManager.formatBytes(0), '0 B');
    assert.equal(GemmaStorageManager.formatBytes(1024), '1 KB');
    assert.equal(GemmaStorageManager.formatBytes(1024 * 1024 * 500), '500 MB');
    assert.equal(GemmaStorageManager.formatBytes(1024 * 1024 * 1024 * 2.5), '2.5 GB');

    const mockQuota = {
        usage: 1024 * 1024 * 2500,
        quota: 1024 * 1024 * 10000,
        percent: '25.0',
        formattedUsage: '2.44 GB',
        formattedQuota: '9.77 GB'
    };

    const mockModels = [
        { name: 'gemma-4-E2B-it.litertlm', size: 1024 * 1024 * 2500, formattedSize: '2.44 GB', lastModified: '01/11/2026' }
    ];

    const modalHtml = GemmaStorageManager.createStorageModalHTML(mockQuota, mockModels);
    assert.match(modalHtml, /gemma-opfs-storage-modal/);
    assert.match(modalHtml, /gemma-4-E2B-it\.litertlm/);
    assert.match(modalHtml, /btn-delete-model/);
    assert.match(modalHtml, /btn-clear-all-models/);
});

test('Local Tools Engine executes calculator, time, and parses tool calls', async () => {
    assert.equal(fs.existsSync(toolsPath), true, 'local-tools-engine.js must exist');
    const GemmaTools = require(toolsPath);

    // Test Calculator
    const calcResult = await GemmaTools.executeTool('calculator', { expression: 'sqrt(144) + 15 * 2' });
    assert.equal(calcResult.result, 42);

    const safeCalcFail = await GemmaTools.executeTool('calculator', { expression: 'process.exit(1)' });
    assert.ok(safeCalcFail.error);

    // Test DateTime
    const timeResult = await GemmaTools.executeTool('get_current_datetime');
    assert.ok(timeResult.hari);
    assert.ok(timeResult.tanggal);
    assert.ok(timeResult.iso);

    // Test Tool Call Detection
    const sampleOutput = 'Berikut perhitungannya:\n<tool_call>\n{"name": "calculator", "arguments": {"expression": "25 * 4"}}\n</tool_call>';
    const detected = GemmaTools.detectToolCall(sampleOutput);
    assert.ok(detected);
    assert.equal(detected.name, 'calculator');
    assert.equal(detected.arguments.expression, '25 * 4');

    // System prompt helper
    const systemPrompt = GemmaTools.getToolSystemPrompt();
    assert.match(systemPrompt, /calculator/);
    assert.match(systemPrompt, /<tool_call>/);
});

test('Offline TTS engine cleans markdown/math syntax and renders speech button', () => {
    assert.equal(fs.existsSync(ttsPath), true, 'offline-tts.js must exist');
    const GemmaTTS = require(ttsPath);

    const rawMarkdown = `
# Judul Bab
Halo **dunia**, ini kode: \`console.log("hai")\`
\`\`\`js
const x = 10;
\`\`\`
Berikut rumus $E = mc^2$ dan tautan [Gemma](https://example.com).
    `;

    const cleaned = GemmaTTS.cleanTextForSpeech(rawMarkdown);
    assert.ok(!cleaned.includes('```'));
    assert.ok(!cleaned.includes('**'));
    assert.ok(!cleaned.includes('#'));
    assert.ok(cleaned.includes('Halo dunia'));
    assert.ok(cleaned.includes('Gemma'));

    const buttonHtml = GemmaTTS.renderSpeakButton('Halo');
    assert.match(buttonHtml, /gemma-tts-btn/);
    assert.match(buttonHtml, /Dengarkan/);
});

test('Workspace HTML pages link all 4 advanced feature scripts', () => {
    const pages = ['utama.html', 'utamaV2.html', 'VS.html', 'claude.html', 'vision_ulti.html'];
    const scripts = [
        'generation-metrics.js',
        'opfs-storage-manager.js',
        'local-tools-engine.js',
        'offline-tts.js'
    ];

    for (const page of pages) {
        const content = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        for (const script of scripts) {
            assert.match(
                content,
                new RegExp(script),
                `${page} must include script tag for ${script}`
            );
        }
    }
});

test('Swift native app integrates OPFS manager, settings menu, and modern macOS UI standards', () => {
    const swiftFile = path.join(projectRoot, 'gemma_webview.swift');
    const swiftContent = fs.readFileSync(swiftFile, 'utf8');

    assert.match(swiftContent, /menuOpenStorageManager/);
    assert.match(swiftContent, /GemmaStorageManager\.openStorageModal\(\)/);
    assert.match(swiftContent, /fullSizeContentView/);
    assert.match(swiftContent, /titlebarAppearsTransparent\s*=\s*true/);
    assert.match(swiftContent, /blendingMode\s*=\s*\.behindWindow/);
    assert.match(swiftContent, /updateDockTileStatus/);
    assert.match(swiftContent, /menuOpenSettings/);
    assert.match(swiftContent, /aiStatus/);
    assert.match(swiftContent, /applicationDockMenu/);
    assert.match(swiftContent, /setupMainMenu/);
    assert.match(swiftContent, /fullScreenPrimary/);
    assert.match(swiftContent, /fullScreenAllowsTiling/);
    assert.match(swiftContent, /menuNewChat/);
    assert.match(swiftContent, /menuExportDocument/);
    assert.match(swiftContent, /menuFindInPage/);
});

test('Apple Liquid Glass and Apple Intelligence Aura styles are unified across css and tools', () => {
    const cssPath = path.join(projectRoot, 'nano_asset/assets/css/ai-renderers.css');
    const cssContent = fs.readFileSync(cssPath, 'utf8');

    assert.match(cssContent, /\.apple-liquid-glass/);
    assert.match(cssContent, /saturate\(200%\)/);
    assert.match(cssContent, /\.apple-ai-aura/);
    assert.match(cssContent, /conic-gradient/);
    assert.match(cssContent, /appleAiGlowSpin/);

    const storageContent = fs.readFileSync(storagePath, 'utf8');
    assert.match(storageContent, /apple-liquid-glass/);

    const metricsContent = fs.readFileSync(metricsPath, 'utf8');
    assert.match(metricsContent, /apple-liquid-glass/);

    const ttsContent = fs.readFileSync(ttsPath, 'utf8');
    assert.match(ttsContent, /apple-liquid-glass/);
});

test('macOS 3-Pane Split View and Search Field satisfy Apple HIG requirements', () => {
    const splitModulePath = path.join(projectRoot, 'nano_asset/assets/js/macos-split-view.js');
    assert.equal(fs.existsSync(splitModulePath), true, 'macos-split-view.js must exist');

    const MacSplitView = require(splitModulePath);
    assert.ok(MacSplitView.initSearchField);
    assert.ok(MacSplitView.toggleSidebar);
    assert.ok(MacSplitView.openInspector);
    assert.ok(MacSplitView.closeInspector);
    assert.ok(MacSplitView.toggleInspector);
    assert.ok(MacSplitView.setInspectorTab);
    assert.ok(MacSplitView.updateParametersView);

    // Mock DOM test for parameter inspector
    const dummyContainer = { innerHTML: '', querySelector: () => null };
    MacSplitView.updateParametersView(dummyContainer);
    assert.match(dummyContainer.innerHTML, /Parameter Inferensi Model/);
    assert.match(dummyContainer.innerHTML, /Temperature/);
    assert.match(dummyContainer.innerHTML, /Top-P/);
    assert.match(dummyContainer.innerHTML, /KV-Cache/);

    // Check CSS definitions for split container, chat pane, and inspector pane
    const cssPath = path.join(projectRoot, 'nano_asset/assets/css/ai-renderers.css');
    const cssContent = fs.readFileSync(cssPath, 'utf8');
    assert.match(cssContent, /\.macos-split-container/);
    assert.match(cssContent, /\.macos-chat-pane/);
    assert.match(cssContent, /\.macos-inspector-pane/);
    assert.match(cssContent, /\.macos-search-field-wrapper/);

    // Verify script tags in workspace pages
    const pages = ['utama.html', 'utamaV2.html', 'VS.html', 'claude.html', 'vision_ulti.html'];
    for (const page of pages) {
        const content = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        assert.match(content, /macos-split-view\.js/, `${page} must include macos-split-view.js`);
    }
});

test('OPFS table supports quantization detection and sortable columns (HIG Lists & Tables)', () => {
    const GemmaStorageManager = require(storagePath);

    assert.equal(GemmaStorageManager.detectQuantization('gemma-4-E2B-it-int4.litertlm'), 'INT4');
    assert.equal(GemmaStorageManager.detectQuantization('model-q4_k_m.gguf'), 'Q4_K_M');
    assert.equal(GemmaStorageManager.detectQuantization('plain.litertlm'), '—');

    const models = [
        { name: 'b.litertlm', size: 100, modified: 3 },
        { name: 'a.litertlm', size: 300, modified: 1 },
        { name: 'c.litertlm', size: 200, modified: 2 }
    ];
    assert.deepEqual(GemmaStorageManager.sortModels(models, 'size', 'desc').map(m => m.name), ['a.litertlm', 'c.litertlm', 'b.litertlm']);
    assert.deepEqual(GemmaStorageManager.sortModels(models, 'name', 'asc').map(m => m.name), ['a.litertlm', 'b.litertlm', 'c.litertlm']);
    assert.deepEqual(GemmaStorageManager.sortModels(models, 'modified', 'asc').map(m => m.name), ['a.litertlm', 'c.litertlm', 'b.litertlm']);

    const html = GemmaStorageManager.createStorageModalHTML(
        { formattedUsage: '1 GB', formattedQuota: '10 GB', percent: '10.0' },
        [{ name: '<x>.litertlm', quant: 'INT4', size: 5, formattedSize: '5 B', lastModified: 'now', status: 'Tersimpan' }],
        { key: 'name', direction: 'asc' }
    );
    assert.match(html, /<table class="opfs-model-table"/);
    assert.match(html, /data-sort="size"/);
    assert.match(html, /aria-sort="ascending"/);
    assert.match(html, /tabular-nums/);
    assert.doesNotMatch(html, /<x>\.litertlm/, 'nama model harus di-escape');
});

test('Knowledge Column View builds cascading hierarchy with preview pane (HIG Column Views)', () => {
    const KCV = require(path.join(projectRoot, 'nano_asset/assets/js/knowledge-column-view.js'));
    const docs = [
        { id: 1, title: 'Makalah B', collection: 'Riset', chunks: ['isi satu', 'isi dua'], size: 10 },
        { id: 2, title: 'Makalah A', collection: 'Riset', chunks: ['x'], size: 5 },
        { id: 3, title: 'Buku', collection: 'Bacaan', chunks: [] }
    ];
    const tree = KCV.buildTree(docs);
    assert.deepEqual(tree.map(n => n.label), ['Bacaan', 'Riset']);
    assert.deepEqual(tree[1].children.map(n => n.label), ['Makalah A', 'Makalah B']);

    // Root only
    assert.equal(KCV.resolveColumns(tree, []).columns.length, 1);
    // Collection selected -> documents column
    assert.equal(KCV.resolveColumns(tree, ['col:Riset']).columns.length, 2);
    // Document selected -> chunk column
    assert.equal(KCV.resolveColumns(tree, ['col:Riset', 'doc:1']).columns.length, 3);
    // Chunk selected -> preview, bukan kolom baru
    const deep = KCV.resolveColumns(tree, ['col:Riset', 'doc:1', 'chunk:1:1']);
    assert.equal(deep.columns.length, 3);
    assert.equal(deep.preview.preview, 'isi dua');
    // Path tidak valid berhenti dengan aman
    assert.equal(KCV.resolveColumns(tree, ['col:Tidak Ada']).columns.length, 1);

    const html = KCV.renderColumnViewHTML(tree, ['col:Riset', 'doc:1', 'chunk:1:0']);
    assert.match(html, /kcv-preview/);
    assert.match(html, /isi satu/);
    assert.match(html, /role="listbox"/);

    for (const page of ['utama.html', 'utamaV2.html', 'VS.html', 'claude.html', 'vision_ulti.html']) {
        assert.match(fs.readFileSync(path.join(projectRoot, page), 'utf8'), /knowledge-column-view\.js/, page);
    }
});

test('Inspector pane is self-building and reachable from the native View menu', () => {
    const split = fs.readFileSync(path.join(projectRoot, 'nano_asset/assets/js/macos-split-view.js'), 'utf8');
    assert.match(split, /function ensureInspectorPane/);
    assert.match(split, /id = 'macos-inspector-pane'/);
    assert.match(split, /btn-inspector-tab-params/);

    const swift = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    assert.match(swift, /menuToggleInspector/);
    assert.match(swift, /menuToggleSidebar/);
    assert.match(swift, /MacSplitView\.toggleInspector/);
});

test('SQLiteVectorStore and Smart API Gateway in gemma_chat_gui.py support centralized RAG and model routing', () => {
    const { execFileSync } = require('node:child_process');
    const pyScript = `
import tempfile, json
from pathlib import Path
import gemma_chat_gui

tmp_db = Path(tempfile.mktemp(suffix=".sqlite3"))
try:
    store = gemma_chat_gui.SQLiteVectorStore(db_path=tmp_db)
    store.upsert_document(
        file_id="doc_kurikulum",
        name="Kurikulum Merdeka.pdf",
        size=1024,
        timestamp=1700000000000,
        collection="Akademik",
        chunks=[
            {"id": "c1", "text": "Profil Pelajar Pancasila mencakup gotong royong dan bernalar kritis.", "embedding": [0.8, 0.2, 0.0]},
            {"id": "c2", "text": "Jadwal ujian semester ganjil dimulai bulan Desember.", "embedding": [0.1, 0.9, 0.0]},
        ],
    )
    vec_hits = store.search(query="Pancasila", embedding=[0.85, 0.15, 0.0], top_k=1, min_score=0.5)
    lex_hits = store.search(query="ujian semester Desember", embedding=None, top_k=1, min_score=0.2)

    class DummyManager:
        def list_models(self):
            return ["gemma-4-E2B-it.litertlm"]

    resolved = gemma_chat_gui.resolve_chat_completion_payload(
        {
            "model": "auto",
            "use_shared_kb": True,
            "messages": [{"role": "user", "content": "Apa isi ujian semester Desember?"}],
        },
        model_manager=DummyManager(),
        kb_store=store,
    )
    print(json.dumps({
        "files_count": len(store.list_files()),
        "vec_top": vec_hits[0]["id"] if vec_hits else None,
        "lex_top": lex_hits[0]["id"] if lex_hits else None,
        "resolved_model": resolved["model"],
        "injected_kb": "[KONTEKS KNOWLEDGE BASE TERPUSAT]" in resolved["messages"][0]["content"],
    }))
finally:
    tmp_db.unlink(missing_ok=True)
`;
    const out = execFileSync('python3', ['-c', pyScript], { cwd: projectRoot, encoding: 'utf8' });
    const result = JSON.parse(out.trim());
    assert.equal(result.files_count, 1);
    assert.equal(result.vec_top, 'c1');
    assert.equal(result.lex_top, 'c2');
    assert.equal(result.resolved_model, 'gemma-4-E2B-it.litertlm');
    assert.equal(result.injected_kb, true);
});

test('Shared KB Sync Bridge and Offline Audio / Webhook endpoints are wired across workspace', async () => {
    const GemmaSharedKB = require(path.join(projectRoot, 'nano_asset/assets/js/shared-kb-sync.js'));
    assert.ok(GemmaSharedKB.fetchSnapshot);
    assert.ok(GemmaSharedKB.ingestToServer);
    assert.ok(GemmaSharedKB.deleteFromServer);
    assert.ok(GemmaSharedKB.searchServer);
    assert.ok(GemmaSharedKB.syncIndexedDB);

    const hits = await GemmaSharedKB.searchServer('kurikulum', [0.5, 0.5], 2, 0.3, async () => ({
        ok: true,
        json: async () => ({ results: [{ id: 'c1', text: 'Contoh hasil', score: 0.91 }] })
    }));
    assert.equal(hits.length, 1);
    assert.equal(hits[0].id, 'c1');

    const GemmaTTS = require(ttsPath);
    assert.ok(GemmaTTS.speakViaServer);

    const guiPy = fs.readFileSync(path.join(projectRoot, 'gemma_chat_gui.py'), 'utf8');
    assert.match(guiPy, /\/api\/kb\/ingest/);
    assert.match(guiPy, /\/api\/kb\/search/);
    assert.match(guiPy, /\/api\/automation\/webhook/);
    assert.match(guiPy, /\/v1\/audio\/speech/);
    assert.match(guiPy, /\/v1\/audio\/transcriptions/);

    for (const page of ['utama.html', 'utamaV2.html', 'VS.html', 'claude.html', 'vision_ulti.html']) {
        assert.match(fs.readFileSync(path.join(projectRoot, page), 'utf8'), /shared-kb-sync\.js/, page);
    }
});

test('LiteRT-LM v0.19 model inspection, deterministic embeddings, and smart model routing work end-to-end', async () => {
    const { execFileSync } = require('node:child_process');
    const pyScript = `
import json
import gemma_chat_gui

g4 = gemma_chat_gui.inspect_litertlm_model("gemma-4-E2B-it.litertlm")
g3 = gemma_chat_gui.inspect_litertlm_model("gemma-3n-E4B-it-int4-Web.litertlm")
emb = gemma_chat_gui.compute_deterministic_embedding("pembelajaran mendalam gemma 4 lokal")
norm2 = sum(x * x for x in emb)

class DummyManager:
    def list_models(self):
        return ["gemma-4-E2B-it.litertlm"]

resolved_gpu = gemma_chat_gui.resolve_chat_completion_payload(
    {
        "model": "gemma-4-E2B-it,gpu",
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": "Halo"}],
    },
    model_manager=DummyManager(),
)

print(json.dumps({
    "g4_format": g4["container_format"],
    "g4_mtp": g4["supports_mtp"],
    "g4_modalities": g4["modalities"],
    "g3_format": g3["container_format"],
    "emb_len": len(emb),
    "emb_norm2": round(norm2, 3),
    "resolved_model": resolved_gpu["model"],
    "resolved_max_completion": resolved_gpu.get("max_completion_tokens"),
    "version": gemma_chat_gui.get_litert_lm_version(),
}))
`;
    const out = execFileSync('python3', ['-c', pyScript], { cwd: projectRoot, encoding: 'utf8' });
    const result = JSON.parse(out.trim());
    assert.equal(result.g4_format, 'litertlm');
    assert.equal(result.g4_mtp, true);
    assert.ok(result.g4_modalities.includes('text'));
    assert.ok(result.g4_modalities.includes('vision'));
    assert.ok(result.g4_modalities.includes('audio'));
    assert.equal(result.g3_format, 'tflite_web');
    assert.equal(result.emb_len, 384);
    assert.ok(Math.abs(result.emb_norm2 - 1.0) < 0.01);
    assert.equal(result.resolved_model, 'gemma-4-E2B-it.litertlm,gpu');
    assert.equal(result.resolved_max_completion, 1024);

    const GemmaSharedKB = require(path.join(projectRoot, 'nano_asset/assets/js/shared-kb-sync.js'));
    assert.equal(typeof GemmaSharedKB.embedViaServer, 'function');
    const vec = await GemmaSharedKB.embedViaServer('halo dunia', 'auto', async () => ({
        ok: true,
        json: async () => ({
            object: 'list',
            data: [{ object: 'embedding', index: 0, embedding: [0.6, 0.8] }]
        })
    }));
    assert.deepEqual(vec, [0.6, 0.8]);

    const MacSplitView = require(path.join(projectRoot, 'nano_asset/assets/js/macos-split-view.js'));
    const dummyContainer = { innerHTML: '', querySelector: () => null };
    MacSplitView.updateParametersView(dummyContainer);
    assert.match(dummyContainer.innerHTML, /LiteRT-LM Engine & Akselerator/);
    assert.match(dummyContainer.innerHTML, /inspector-litert-backend/);
    assert.match(dummyContainer.innerHTML, /inspector-litert-speculative/);
    assert.match(dummyContainer.innerHTML, /inspector-litert-reasoning/);
    assert.match(dummyContainer.innerHTML, /inspector-litert-model-info/);
});

test('EduVisNativeApp includes official LiteRTLM Swift Package dependency and in-process Pure Swift engine', () => {
    const pkgSwift = fs.readFileSync(path.join(projectRoot, 'EduVisNativeApp/Package.swift'), 'utf8');
    assert.match(pkgSwift, /https:\/\/github\.com\/google-ai-edge\/LiteRT-LM/);
    assert.match(pkgSwift, /\.product\(name:\s*"LiteRTLM",\s*package:\s*"LiteRT-LM"\)/);

    const nativeEngine = fs.readFileSync(path.join(projectRoot, 'EduVisNativeApp/NativeLiteRTEngine.swift'), 'utf8');
    assert.match(nativeEngine, /#if canImport\(LiteRTLM\)/);
    assert.match(nativeEngine, /litert_lm_engine_create/);
    assert.match(nativeEngine, /litert_lm_conversation_send_message_stream/);
    assert.match(nativeEngine, /liblitert-lm\.dylib/);

    const localAIService = fs.readFileSync(path.join(projectRoot, 'EduVisNativeApp/LocalAIService.swift'), 'utf8');
    assert.match(localAIService, /NativeLiteRTEngine\.shared/);
    assert.match(localAIService, /pure_swift/);
    assert.match(localAIService, /Menyiapkan environment LiteRT-LM/);

    const settingsSheet = fs.readFileSync(path.join(projectRoot, 'EduVisNativeApp/SettingsSheet.swift'), 'utf8');
    assert.match(settingsSheet, /Mode Mesin Inferensi/);
    assert.match(settingsSheet, /pure_swift/);
    assert.match(settingsSheet, /python_server/);
});

test('First-run auto-bootstrap status and DMG distribution staging are wired across backend and native apps', () => {
    const { execFileSync } = require('node:child_process');
    const pyScript = `
import os, json, tempfile
from pathlib import Path
import gemma_chat_gui

with tempfile.TemporaryDirectory() as tmp:
    status_file = Path(tmp) / "bootstrap_status.json"
    os.environ["EDUVIS_BOOTSTRAP_STATUS_PATH"] = str(status_file)
    os.environ["LITERT_LM_DIR"] = str(Path(tmp) / "litert_dir")
    payload = gemma_chat_gui.write_bootstrap_status("install", "Memasang...", progress=50, ready=False)
    loaded = json.loads(status_file.read_text(encoding="utf-8"))
    litert_exec = gemma_chat_gui.ensure_first_run_requirements()
    done_status = json.loads(status_file.read_text(encoding="utf-8"))
    marker = Path(tmp) / "first_run_complete.json"
    print(json.dumps({
        "wrote_stage": loaded["stage"],
        "wrote_progress": loaded["progress"],
        "ready": done_status["ready"],
        "final_progress": done_status["progress"],
        "has_marker": marker.is_file(),
        "has_exec": bool(litert_exec),
    }))
`;
    const out = execFileSync('python3', ['-c', pyScript], { cwd: projectRoot, encoding: 'utf8' });
    const res = JSON.parse(out.trim());
    assert.equal(res.wrote_stage, 'install');
    assert.equal(res.wrote_progress, 50);
    assert.equal(res.ready, true);
    assert.equal(res.final_progress, 100);
    assert.equal(res.has_marker, true);
    assert.equal(res.has_exec, true);

    const swiftShell = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    assert.match(swiftShell, /bootstrap_status\.json/);

    const localAI = fs.readFileSync(path.join(projectRoot, 'EduVisNativeApp/LocalAIService.swift'), 'utf8');
    assert.match(localAI, /bootstrap_status\.json/);

    const dmgBuilder = fs.readFileSync(path.join(projectRoot, 'scripts/build_dmg.py'), 'utf8');
    assert.match(dmgBuilder, /EduVis Native AI\.app/);
    assert.match(dmgBuilder, /hdiutil/);
});

test('Adopted Liquid Glass JS engine, WebGL refraction shader, and HIG Inspector controls work across workspace', () => {
    const engine = require(path.join(projectRoot, 'nano_asset/assets/js/eduvis-liquid-engine.js'));
    assert.equal(typeof engine.LiquidGlassEngine, 'function');
    assert.equal(typeof engine.ModernMicroInteractions, 'function');
    assert.ok(engine.EduvisUI);

    const webgl = require(path.join(projectRoot, 'nano_asset/assets/js/liquid-glass-webgl.js'));
    assert.equal(typeof webgl.WebGLRenderer, 'function');
    assert.equal(typeof webgl.Container, 'function');
    assert.equal(typeof webgl.Button, 'function');

    const MacSplitView = require(path.join(projectRoot, 'nano_asset/assets/js/macos-split-view.js'));
    const dummyContainer = { innerHTML: '', querySelector: () => null };
    MacSplitView.updateParametersView(dummyContainer);
    assert.match(dummyContainer.innerHTML, /Liquid Glass Control Center/);
    assert.match(dummyContainer.innerHTML, /inspector-lg-blur/);
    assert.match(dummyContainer.innerHTML, /inspector-lg-specular/);
    assert.match(dummyContainer.innerHTML, /inspector-lg-saturate/);
    assert.match(dummyContainer.innerHTML, /inspector-lg-sound/);

    const renderCss = fs.readFileSync(path.join(projectRoot, 'nano_asset/assets/css/ai-renderers.css'), 'utf8');
    assert.match(renderCss, /\.liquid-glass-card/);
    assert.match(renderCss, /\.eduvis-ai-bar/);
    assert.match(renderCss, /\.magnetic-btn/);
    assert.match(renderCss, /\.border-glow-card/);

    const swiftShell = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    assert.match(swiftShell, /eduvis-liquid-engine\.js/);
});

test('EduVisNativeApp adopts full WebKit bridge, font pill, Model Center, LAN QR, About Developer, and 3-Pane Inspector', () => {
    const webViewSwift = fs.readFileSync(path.join(projectRoot, 'EduVisNativeApp/WorkspaceWebView.swift'), 'utf8');
    for (const handler of ['savePng', 'saveSvg', 'saveDocument', 'nativeSpeech', 'aiStatus', 'appTheme']) {
        assert.ok(webViewSwift.includes(`"${handler}"`), `Missing handler ${handler} in WorkspaceWebView.swift`);
    }
    assert.match(webViewSwift, /runOpenPanelWith/);
    assert.match(webViewSwift, /gemma_chat_font_size/);
    assert.match(webViewSwift, /eduvis-liquid-engine\.js/);
    assert.match(webViewSwift, /chat-font-size\.js/);

    const rendererSwift = fs.readFileSync(path.join(projectRoot, 'EduVisNativeApp/AIResponseRendererView.swift'), 'utf8');
    assert.match(rendererSwift, /fontSize: Double/);
    assert.match(rendererSwift, /extractThinkingBlock/);
    assert.match(rendererSwift, /savePng/);
    assert.match(rendererSwift, /saveSvg/);

    const modalsSwift = fs.readFileSync(path.join(projectRoot, 'EduVisNativeApp/FeatureModalsAndInspectorView.swift'), 'utf8');
    for (const viewName of [
        'ChatFontSizePillView',
        'PeluncurGallerySheet',
        'ModelCenterSheet',
        'LanQRSheet',
        'AboutDeveloperSheet',
        'RightInspectorDrawerView'
    ]) {
        assert.ok(modalsSwift.includes(`struct ${viewName}: View`), `Missing ${viewName}`);
    }
    assert.match(modalsSwift, /\/api\/network-info/);
    assert.match(modalsSwift, /\/api\/import-model-upload/);
    assert.match(modalsSwift, /\/api\/delete-model/);
    assert.match(modalsSwift, /qrCodeGenerator/);
    assert.match(modalsSwift, /Subuh Kurniawan/);

    const buildScript = fs.readFileSync(path.join(projectRoot, 'EduVisNativeApp/build_native_app.sh'), 'utf8');
    assert.match(buildScript, /FeatureModalsAndInspectorView\.swift/);
    assert.match(buildScript, /dev\.jpeg/);
});

test('EduVis AI Gallery implements CleanMyMac Cosmic Violet, Left Icon Rail, Storage Bar, and Space Lens Bubble UI', () => {
    const swiftShell = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    assert.match(swiftShell, /func makeCleanMyMacWorkspaceRow\(/);
    assert.match(swiftShell, /func makeCleanMyMacStorageCard\(/);
    assert.match(swiftShell, /func makeSpaceLensBubble\(/);
    assert.match(swiftShell, /func spaceLensBubbleClicked\(/);
    assert.match(swiftShell, /Space Lens/);
    assert.match(swiftShell, /Apple Silicon Unified/);

    const nativeCss = fs.readFileSync(path.join(projectRoot, 'nano_asset/assets/css/native-mac.css'), 'utf8');
    assert.match(nativeCss, /--cmm-bg-deep:\s*#160934/);
    assert.match(nativeCss, /--cmm-accent-gradient:/);
    assert.match(nativeCss, /--nm-accent:\s*#ec4899/);
});

test('Hermes Agent features (Skills, FTS5 Episodic Memory, Cron, Subagents, Self-Heal, Gateway) work end-to-end', () => {
    const { execFileSync } = require('node:child_process');
    const pyScript = `
import tempfile, json
from pathlib import Path
import gemma_chat_gui

tmp_dir = Path(tempfile.mkdtemp(prefix="hermes-test-"))
db_path = tmp_dir / "kb.sqlite3"
store = gemma_chat_gui.SQLiteVectorStore(db_path=db_path)

skills_before = store.list_skills()
assert len(skills_before) >= 3, "Default procedural skills should be seeded"

saved = store.save_skill("ringkas-latex", "Ringkas rumus matematika", "Ekstrak persamaan utama dengan KaTeX.", tags="math,katex")
assert (tmp_dir / "skills" / f"{saved['id']}.md").is_file()
matched_skills = store.match_skills("tolong ringkas persamaan katex matematika")
assert any(s["id"] == saved["id"] for s in matched_skills)

store.add_memory("Bahasa pemrograman favorit saya adalah Swift.", category="Preferensi")
auto_mem = store.auto_extract_memory("Ingat bahwa proyek saya menggunakan LiteRT-LM lokal.")
assert auto_mem is not None
mem_hits = store.search_memories("Swift")
assert len(mem_hits) >= 1 and "Swift" in mem_hits[0]["fact"]

job = store.upsert_cron_job("Audit Memori", "Ringkas status KB lokal", schedule_minutes=30, enabled=True)
store.record_cron_result(job["id"], "Selesai")
jobs = store.list_cron_jobs()
assert any(j["id"] == job["id"] and j["last_result"] == "Selesai" for j in jobs)

payload = gemma_chat_gui.resolve_chat_completion_payload(
    {"model": "auto", "messages": [{"role": "user", "content": "Bagaimana proyek Swift matematika saya?"}], "use_shared_kb": True},
    kb_store=store,
)
injected = payload["messages"][0]["content"]
assert "[MEMORI EPISODIK PENGGUNA]" in injected
assert "[SKILL PROSEDURAL RELEVAN]" in injected
print(json.dumps({"ok": True, "skills": len(store.list_skills()), "memories": len(store.list_memories())}))
`;
    const out = execFileSync('python3', ['-c', pyScript], { cwd: projectRoot, encoding: 'utf8' }).trim();
    const res = JSON.parse(out);
    assert.equal(res.ok, true);

    const swiftShell = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    assert.match(swiftShell, /func openHermesHubPanel\(/);
    assert.match(swiftShell, /\/api\/hermes\/delegate/);
    assert.match(swiftShell, /\/api\/hermes\/self-heal/);

    const modalsSwift = fs.readFileSync(path.join(projectRoot, 'EduVisNativeApp/FeatureModalsAndInspectorView.swift'), 'utf8');
    assert.match(modalsSwift, /struct HermesAgentHubSheet: View/);
    const chatSwift = fs.readFileSync(path.join(projectRoot, 'EduVisNativeApp/ChatViews.swift'), 'utf8');
    assert.match(chatSwift, /saveAsHermesSkill/);
});
