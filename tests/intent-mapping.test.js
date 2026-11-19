const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const projectRoot = path.resolve(__dirname, '..');

function loadIntentEnricher() {
    const code = fs.readFileSync(path.join(projectRoot, 'nano_asset/assets/js/intent-enricher.js'), 'utf8');
    const sandbox = { globalThis: {}, window: {} };
    sandbox.window = sandbox;
    sandbox.globalThis = sandbox;
    vm.runInNewContext(code, sandbox);
    return sandbox.GemmaIntent;
}

test('intelligent mapping routes flow / process requests to Mermaid flowchart', () => {
    const enricher = loadIntentEnricher();

    const flowPrompts = [
        'buatkan alur pendaftaran siswa baru',
        'tolong buat diagram alur proses checkout belanja',
        'gambarkan flowchart login aplikasi',
        'bagaimana siklus hidup pengembangan perangkat lunak?',
        'jelaskan tahapan audit ISO',
        'buatkan workflow persetujuan anggaran'
    ];

    for (const prompt of flowPrompts) {
        const intent = enricher.detectIntent(prompt);
        assert.equal(intent.type, 'flowchart', `Expected flowchart intent for "${prompt}"`);
        const enriched = enricher.enrichPrompt(prompt);
        assert.match(enriched, /flowchart TD/i, `Expected flowchart TD directive for "${prompt}"`);
        assert.match(enriched, /```mermaid/i, `Expected mermaid directive for "${prompt}"`);
    }
});

test('intelligent mapping routes data / statistics requests to Chart.js', () => {
    const enricher = loadIntentEnricher();

    const chartPrompts = [
        'tampilkan grafik perbandingan penjualan 2024',
        'buat chart distribusi nilai ujian siswa',
        'buat diagram batang untuk data penduduk',
        'tampilkan tren data ekspor impor 5 tahun terakhir',
        'visualisasi data pendapatan per kuartal'
    ];

    for (const prompt of chartPrompts) {
        const intent = enricher.detectIntent(prompt);
        assert.equal(intent.type, 'chart', `Expected chart intent for "${prompt}"`);
        const enriched = enricher.enrichPrompt(prompt);
        assert.match(enriched, /Chart\.js/i, `Expected Chart.js directive for "${prompt}"`);
        assert.match(enriched, /```chart/i, `Expected chart block directive for "${prompt}"`);
    }
});

test('intelligent mapping routes mindmap requests to Mermaid mindmap', () => {
    const enricher = loadIntentEnricher();

    const mindmapPrompts = [
        'buatkan mindmap konsep kecerdasan buatan',
        'susun peta konsep sistem pernapasan manusia',
        'buat pohon topik manajemen proyek'
    ];

    for (const prompt of mindmapPrompts) {
        const intent = enricher.detectIntent(prompt);
        assert.equal(intent.type, 'mindmap', `Expected mindmap intent for "${prompt}"`);
        const enriched = enricher.enrichPrompt(prompt);
        assert.match(enriched, /mindmap/i, `Expected mindmap directive for "${prompt}"`);
        assert.match(enriched, /root\(\(Topik Utama\)\)/i, `Expected root topic directive for "${prompt}"`);
    }
});

test('regular prompts without visual intent remain unaugmented', () => {
    const enricher = loadIntentEnricher();

    const regularPrompts = [
        'siapa presiden pertama indonesia?',
        'apa perbedaan var, let, dan const dalam javascript?',
        'terjemahkan kalimat ini ke bahasa inggris'
    ];

    for (const prompt of regularPrompts) {
        const intent = enricher.detectIntent(prompt);
        assert.equal(intent.type, 'text');
        const enriched = enricher.enrichPrompt(prompt);
        assert.equal(enriched, prompt);
    }
});

test('smart fallback converts numbered lists to valid Mermaid flowchart TD', () => {
    const enricher = loadIntentEnricher();

    const listText = `
1. Pengguna membuka aplikasi
2. Sistem menampilkan formulir login
3. Pengguna memasukkan kredensial
4. Sistem memverifikasi data
5. Pengguna diarahkan ke dashboard
`;

    const diagram = enricher.convertNumberedListToFlowchart(listText);
    assert.ok(diagram, 'Should produce a diagram string');
    assert.match(diagram, /^flowchart TD/);
    assert.match(diagram, /step1\["1\. Pengguna membuka aplikasi"\]/);
    assert.match(diagram, /step1 --> step2/);
    assert.match(diagram, /step4 --> step5/);
});

test('backward compatibility: global applyKaTeXPrompt delegates to GemmaIntent.enrichPrompt', () => {
    const enricher = loadIntentEnricher();
    const sandbox = { globalThis: {}, window: {} };
    sandbox.window = sandbox;
    sandbox.globalThis = sandbox;
    const code = fs.readFileSync(path.join(projectRoot, 'nano_asset/assets/js/intent-enricher.js'), 'utf8');
    vm.runInNewContext(code, sandbox);

    assert.equal(typeof sandbox.applyKaTeXPrompt, 'function');
    const result = sandbox.applyKaTeXPrompt('buatkan alur login');
    assert.match(result, /flowchart TD/);
});

test('chat pages load intent-enricher.js script', () => {
    const pages = ['utama.html', 'utamaV2.html', 'VS.html', 'claude.html', 'vision_ulti.html'];
    for (const page of pages) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        assert.match(source, /intent-enricher\.js/, `${page} should load intent-enricher.js`);
    }
});
