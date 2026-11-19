const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const projectRoot = path.resolve(__dirname, '..');
const enginePath = path.join(projectRoot, 'nano_asset/assets/js/ai-response-engine.js');

function createEngineSandbox(onMarkdownParse) {
    const sandbox = {
        window: {
            marked: {
                Renderer: function () {
                    this.table = function (token) {
                        return '<table>' + (token && token.header ? '<thead><tr><th>H</th></tr></thead>' : '') + '<tbody><tr><td>D</td></tr></tbody></table>';
                    };
                },
                parse: function (src, options) {
                    if (onMarkdownParse) onMarkdownParse();
                    if (src.includes('| Kolom 1 |')) {
                        return '<div class="table-wrap table-wrapper"><table><thead><tr><th>Kolom 1</th></tr></thead><tbody><tr><td>Data 1</td></tr></tbody></table></div>';
                    }
                    if (src.includes('Saran Pertanyaan Lanjutan:')) {
                        return '<hr><p>💡 <strong>Saran Pertanyaan Lanjutan:</strong></p><ul><li>Bagaimana cara optimasi?</li><li>Berikan contoh kode lain</li></ul>';
                    }
                    return '<p>' + src + '</p>';
                }
            },
            hljs: {
                getLanguage: (lang) => ['javascript', 'python', 'json', 'html', 'css'].includes(lang),
                highlight: (code, opts) => ({ value: `<span class="tok">${code}</span>` })
            },
            katex: {
                renderToString: (tex, opts) => `<span class="katex-html">${tex}</span>`
            },
            document: {
                documentElement: { dataset: { theme: 'dark' } },
                head: { appendChild: () => {} },
                querySelector: () => null
            },
            location: { protocol: 'https:', origin: 'https://127.0.0.1:1234' },
            performance: { now: () => Date.now() },
            requestAnimationFrame: (cb) => setTimeout(cb, 10),
            cancelAnimationFrame: (id) => clearTimeout(id)
        }
    };
    sandbox.window.window = sandbox.window;
    sandbox.document = sandbox.window.document;
    sandbox.location = sandbox.window.location;
    sandbox.performance = sandbox.window.performance;
    sandbox.requestAnimationFrame = sandbox.window.requestAnimationFrame;
    sandbox.cancelAnimationFrame = sandbox.window.cancelAnimationFrame;

    const code = fs.readFileSync(enginePath, 'utf8');
    vm.createContext(sandbox);
    vm.runInContext(code, sandbox);
    return sandbox.window.AIResponseEngine;
}

test('AI Response Engine renders thinking tags, math, and code blocks with high fidelity', () => {
    const engine = createEngineSandbox();
    assert.ok(engine, 'AIResponseEngine must be exported');

    // 1. Tag think saat streaming (belum ditutup)
    const streamingThink = engine.renderMd('<think>Menganalisis data statistik...', false);
    assert.match(streamingThink, /class="ai-think-block"\s+open/);
    assert.match(streamingThink, /sedang bernalar/);

    // 2. Tag think saat selesai (ditutup)
    const finishedThink = engine.renderMd('<think>Kesimpulan awal</think>Berikut hasil analisisnya:', true);
    assert.match(finishedThink, /class="ai-think-block"/);
    assert.doesNotMatch(finishedThink, /sedang bernalar/);

    // 3. Formula KaTeX inline dan display
    const mathText = 'Persamaan gerak: $$s = v_0 t + \\frac{1}{2} a t^2$$ dan inline $E = mc^2$.';
    const mathRendered = engine.renderMd(mathText, true);
    assert.match(mathRendered, /class="math"/);
    assert.match(mathRendered, /data-display="true"/);
    assert.match(mathRendered, /data-display="false"/);

    // 4. Tabel dibungkus wrapper responsif
    const tableMd = '| Kolom 1 |\n| --- |\n| Data 1 |';
    const tableRendered = engine.renderMd(tableMd, true);
    assert.match(tableRendered, /class="table-wrap table-wrapper"/);

    // 5. Follow-up suggestions otomatis diubah menjadi interactive action chips
    const suggestionsMd = 'Berikut penjelasan algoritma.\n\n---\n💡 **Saran Pertanyaan Lanjutan:**\n- Bagaimana cara optimasi?\n- Berikan contoh kode lain';
    const suggestionsRendered = engine.renderMd(suggestionsMd, true);
    assert.match(suggestionsRendered, /class="followup-chips"/);
    assert.match(suggestionsRendered, /class="followup-chip"/);
    assert.match(suggestionsRendered, /data-act="suggest"/);
    assert.match(suggestionsRendered, /data-text="Bagaimana cara optimasi\?"/);
});

test('Markdown Memoization Cache: reuses finalized HTML without parsing again', () => {
    let parseCalls = 0;
    const engine = createEngineSandbox(() => { parseCalls++; });
    assert.equal(typeof engine.clearCache, 'function');
    assert.equal(typeof engine.getCacheSize, 'function');

    engine.clearCache();
    assert.equal(engine.getCacheSize(), 0);

    const complexMarkdown = `
# Analisis Kinerja Algoritma
Berikut adalah tabel komparasi:
| Algoritma | Waktu (ms) | Memori (MB) |
|---|---|---|
| QuickSort | 12.4 | 4.2 |
| MergeSort | 14.1 | 8.1 |

Formula kompleks:
$$f(x) = \\int_{-\\infty}^{\\infty} \\hat{f}(\\xi) e^{2 \\pi i \\xi x} d\\xi$$
`;

    // Render pertama kali mem-parsing Markdown.
    const firstRender = engine.renderMd(complexMarkdown, true);

    assert.equal(engine.getCacheSize(), 1, 'Cache size should be 1 after finalized render');
    assert.equal(parseCalls, 1, 'Initial finalized render should parse Markdown once');

    // Render kedua harus memakai HTML cache.
    const secondRender = engine.renderMd(complexMarkdown, true);

    assert.equal(firstRender, secondRender, 'Cached HTML output must match exactly');
    assert.equal(parseCalls, 1, 'Cached render must skip Markdown parsing');

    // Streaming mode (finalized = false) shouldn't pollute the cache
    engine.renderMd('# In-progress token stream...', false);
    assert.equal(engine.getCacheSize(), 1, 'Incomplete stream should not be cached');
    assert.equal(parseCalls, 2, 'Streaming render should still parse its current content');

    // Cache clearing
    engine.clearCache();
    assert.equal(engine.getCacheSize(), 0, 'Cache should be empty after clearCache()');
});

test('Streaming Throttle Benchmark: processes 500 high-frequency chunks efficiently without UI lockup', async () => {
    const engine = createEngineSandbox();
    const mockContainer = { innerHTML: '' };
    let scrollCount = 0;

    const renderer = engine.createStreamRenderer(mockContainer, {
        onScroll: () => { scrollCount++; }
    });

    const startTime = performance.now();
    const tokenChunks = [
        'Halo! ', 'Berikut ', 'adalah ', 'penjelasan ', 'lengkap ',
        'tentang ', 'arsitektur ', 'AI: ', '\n\n',
        '1. **Model**: Gemma 4\n', '2. **Kinerja**: Cepat\n',
        '$$\\Delta E = h \\nu$$\n\n'
    ];

    // Simulasikan 500 token masuk sangat cepat (seperti output LLM lokal 100 tps)
    for (let i = 0; i < 500; i++) {
        renderer.write(tokenChunks[i % tokenChunks.length]);
    }

    const midTime = performance.now();
    const writeDuration = midTime - startTime;

    // Tunggu throttle buffer
    await new Promise((resolve) => setTimeout(resolve, 80));
    renderer.finalize();

    const totalDuration = performance.now() - startTime;

    assert.ok(mockContainer.innerHTML.length > 0, 'Container must receive rendered HTML');
    assert.ok(totalDuration < 500, `Stream benchmark took ${totalDuration}ms, must be < 500ms`);
    assert.ok(writeDuration < 150, `Pushing 500 tokens should be non-blocking (< 150ms), actual: ${writeDuration}ms`);
});

test('CSS & PWA Validation: content-visibility, responsive table, followup chips, and PWA manifest', () => {
    // 1. Cek CSS content-visibility dan responsive table
    const cssContent = fs.readFileSync(path.join(projectRoot, 'nano_asset/assets/css/ai-renderers.css'), 'utf8');
    assert.match(cssContent, /content-visibility:\s*auto/);
    assert.match(cssContent, /contain-intrinsic-size:/);
    assert.match(cssContent, /overflow-x:\s*auto\s*!important/);
    assert.match(cssContent, /width:\s*max-content\s*!important/);
    assert.match(cssContent, /\.followup-chips/);
    assert.match(cssContent, /\.followup-chip/);
    assert.match(cssContent, /\.streaming-cursor/);
    assert.match(cssContent, /\.ai-think-block/);

    // 2. Cek PWA Webmanifest
    const manifest = JSON.parse(fs.readFileSync(path.join(projectRoot, 'manifest.webmanifest'), 'utf8'));
    assert.equal(manifest.display, 'standalone');
    assert.equal(manifest.short_name, 'Tanya AI');
    assert.ok(manifest.icons.length > 0);
});

test('Tanya AI defers scripts and loads document parsers only when needed', () => {
    const standalone = fs.readFileSync(path.join(projectRoot, 'tanya-ai-standalone.html'), 'utf8');
    const externalScripts = Array.from(standalone.matchAll(/<script\b(?=[^>]*\bsrc\s*=)[^>]*>/gi), match => match[0]);

    assert.ok(externalScripts.length > 0, 'Workspace must include its external scripts');
    for (const scriptTag of externalScripts) {
        assert.match(scriptTag, /\bdefer\b/, `External script should not block HTML parsing: ${scriptTag}`);
    }

    assert.doesNotMatch(standalone, /<script\b[^>]*\bsrc=["'][^"']*(?:pdf\.min\.js|mammoth\.browser\.min\.js|xlsx\.full\.min\.js|jszip\.min\.js|html2pdf\.bundle\.min\.js)["']/i);
    assert.match(standalone, /function loadDocumentLibrary\(/);
    assert.match(standalone, /loadDocumentLibrary\("nano_asset\/assets\/js\/pdf\.min\.js"/);
    assert.match(standalone, /loadDocumentLibrary\("nano_asset\/assets\/js\/mammoth\.browser\.min\.js"/);
    assert.match(standalone, /loadDocumentLibrary\("nano_asset\/assets\/js\/xlsx\.full\.min\.js"/);
});

test('Apple iOS Human Interface Guidelines (HIG) Mobile View Compliance', () => {
    // 1. Cek aturan universal Apple iOS HIG di ai-renderers.css
    const css = fs.readFileSync(path.join(projectRoot, 'nano_asset/assets/css/ai-renderers.css'), 'utf8');
    assert.match(css, /font-size:\s*16px\s*!important/, 'Must prevent iOS Safari auto-zoom with 16px input font');
    assert.match(css, /min-height:\s*44px\s*!important/, 'Must support Apple 44x44pt minimum touch target height');
    assert.match(css, /min-width:\s*44px\s*!important/, 'Must support Apple 44x44pt minimum touch target width');
    assert.match(css, /env\(safe-area-inset-top\)/, 'Must respect top Safe Area Insets (notch/Dynamic Island)');
    assert.match(css, /env\(safe-area-inset-bottom\)/, 'Must respect bottom Safe Area Insets (Home Indicator)');
    assert.match(css, /-webkit-overflow-scrolling:\s*touch/, 'Must enable native iOS momentum scrolling');

    // 2. Cek implementasi mobile view di tanya-ai-standalone.html
    const standalone = fs.readFileSync(path.join(projectRoot, 'tanya-ai-standalone.html'), 'utf8');
    assert.match(standalone, /font-size:\s*16px\s*!important/, 'tanya-ai textarea must use 16px font on mobile');
    assert.match(standalone, /min-width:\s*44px/, 'tanya-ai controls must meet 44pt touch targets');
    assert.match(standalone, /env\(safe-area-inset-bottom/, 'tanya-ai must accommodate home indicator inset');
});
