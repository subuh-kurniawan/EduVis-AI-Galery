const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const projectRoot = path.resolve(__dirname, '..');
const normalizerSource = fs.readFileSync(
    path.join(projectRoot, 'nano_asset/assets/js/mermaid-normalizer.js'),
    'utf8'
);
const browserWindow = {};
vm.runInNewContext(normalizerSource, { window: browserWindow });
const mermaidNormalizer = browserWindow.GemmaMermaid;

test('mindmap labels with numbering and punctuation normalize into a valid tree shape', () => {
    const normalized = mermaidNormalizer.normalizeMindmap(
        'mindmap\n' +
        'root((Perubahan Paradigma Pembelajaran Modern))\n' +
        '#1 Paradigma Lama (Tradisional)\n' +
        'Definisi: Berpusat pada guru (teacher-centered)\n' +
        '  Fokus: Hafalan, reproduksi informasi.\n' +
        '#2 Paradigma Baru (Modern)'
    );

    assert.match(normalized, /^mindmap\nroot\(\(Perubahan Paradigma Pembelajaran Modern\)\)/);
    assert.match(normalized, /\["#1 Paradigma Lama \(Tradisional\)"\]/);
    assert.match(normalized, /\["Definisi: Berpusat pada guru \(teacher-centered\)"\]/);
    assert.match(normalized, /\["Fokus: Hafalan, reproduksi informasi\."\]/);
    assert.match(normalized, /\["#2 Paradigma Baru \(Modern\)"\]/);
});

test('mindmap without an explicit root promotes its first label without losing descendants', () => {
    const normalized = mermaidNormalizer.normalizeMindmap(
        'mindmap\nKurikulum (2025)\n  Cabang (A)\n    Anak: materi'
    );

    assert.match(normalized, /^mindmap\nroot\["Kurikulum \(2025\)"\]/);
    assert.match(normalized, /\["Cabang \(A\)"\]/);
    assert.match(normalized, /\["Anak: materi"\]/);
});

test('flowchart normalization remains independent from mindmap handling', () => {
    const normalized = mermaidNormalizer.normalizeFlowchart(
        'flowchart TD\nA[Mulai] --> B{Berhasil?}\nB -->|Ya| C[Selesai]'
    );

    assert.equal(
        normalized,
        'flowchart TD\nA["Mulai"] --> B{"Berhasil?"}\nB -->|"Ya"| C["Selesai"]'
    );
});

test('Mermaid syntax is auto-detected and normalized across supported diagram types', () => {
    const source = fs.readFileSync(
        path.join(projectRoot, 'nano_asset/assets/js/mermaid-normalizer.js'),
        'utf8'
    );
    const browserWindow = {};
    vm.runInNewContext(source, { window: browserWindow });

    for (const diagram of [
        'sequenceDiagram\nAlice->>Bob: Hello',
        'classDiagram\nAnimal <|-- Duck',
        'classDiagram\nclass Engine {\n  +start()\n}',
        'stateDiagram-v2\n[*] --> Active',
        'erDiagram\nCUSTOMER ||--o{ ORDER : places',
        'sequenceDiagram\nAlice-->>Bob: Hello',
        'gantt\ntitle Project timeline',
        'pie title Browser usage\n"A" : 42',
    ]) {
        assert.equal(browserWindow.GemmaMermaid.isDiagram(diagram), true, diagram);
        assert.equal(browserWindow.GemmaMermaid.normalize(diagram), diagram);
    }

    assert.equal(browserWindow.GemmaMermaid.isDiagram('const next = value => value + 1;'), false);

    for (const page of ['VS.html', 'claude.html', 'utama.html', 'utamaV2.html']) {
        const html = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        assert.match(html, /GemmaMermaid\.isDiagram\(code\)/);
        assert.match(html, /if \(lang === 'mermaid' \|\| isMermaidDiagram\)/);
    }
});

test('chat pages unwrap the nested Chart.js configuration before validation', () => {
    const pages = [
        'VS.html',
        'claude.html',
        'utama.html',
        'utamaV2.html',
        'vision_ulti.html',
    ];

    for (const page of pages) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        assert.match(
            source,
            /if\s*\(parsed\s*&&\s*parsed\.chart\s*&&\s*typeof\s+parsed\.chart\s*===\s*['"]object['"]\)\s*\{\s*parsed\s*=\s*parsed\.chart;/,
            `${page} should unwrap the { chart: ... } response format`
        );
    }

    const livePage = fs.readFileSync(path.join(projectRoot, 'gemini_live.html'), 'utf8');
    assert.match(
        livePage,
        /if\s*\(config\s*&&\s*config\.chart\s*&&\s*typeof\s+config\.chart\s*===\s*['"]object['"]\)\s*\{\s*config\s*=\s*config\.chart;/,
        'gemini_live.html should unwrap the { chart: ... } response format'
    );
});

test('AI chart_type data rows are converted to Chart.js datasets for all chat pages', () => {
    const normalizerSource = fs.readFileSync(
        path.join(projectRoot, 'nano_asset/assets/js/chart-config-normalizer.js'),
        'utf8'
    );
    const browserWindow = {};
    vm.runInNewContext(normalizerSource, { window: browserWindow });

    const normalized = browserWindow.normalizeAIChartConfig({
        chart_type: 'bar',
        title: 'Profil Kemiskinan di Indonesia, September 2024',
        data: [
            { label: '2013 Sep', value: 28.6 },
            { label: '2014 Sep', value: 28.28 },
        ],
    });

    assert.equal(normalized.type, 'bar');
    assert.deepEqual(Array.from(normalized.data.labels), ['2013 Sep', '2014 Sep']);
    assert.deepEqual(Array.from(normalized.data.datasets[0].data), [28.6, 28.28]);
    assert.equal(normalized.data.datasets[0].label, 'Profil Kemiskinan di Indonesia, September 2024');
    assert.equal(normalized.options.plugins.title.text, 'Profil Kemiskinan di Indonesia, September 2024');
    assert.equal(normalized.options.responsive, true);
    assert.equal(normalized.options.maintainAspectRatio, false);

    const invalidConfig = { chart_type: 'bar', data: [{ label: 'Tidak valid', value: null }] };
    assert.equal(browserWindow.normalizeAIChartConfig(invalidConfig), invalidConfig);

    for (const page of ['VS.html', 'claude.html', 'utama.html', 'utamaV2.html']) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        assert.match(source, /chart-config-normalizer\.js/);
        assert.match(source, /parsed = window\.normalizeAIChartConfig\(parsed\)/);
    }
});

test('Mermaid loader failures preserve the diagram source in VS and Claude pages', () => {
    for (const page of ['VS.html', 'claude.html']) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        assert.match(source, /mermaidDivs\.forEach\(div\s*=>\s*\{/);
        assert.match(source, /Diagram tidak dapat dirender karena pustaka Mermaid gagal dimuat/);
        assert.match(source, /Lihat kode diagram/);
    }
});

test('Markdown table PNG export helper is loaded on rendered chat and document pages', () => {
    const pages = [
        'VS.html',
        'claude.html',
        'utama.html',
        'utamaV2.html',
        'vision_ulti.html',
        'eduVis.html',
    ];

    for (const page of pages) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        assert.match(
            source,
            /<script\s+src=["'][^"']*table-png-export\.js["']\s+defer><\/script>/,
            `${page} should load table PNG export controls`
        );
    }

    const helper = fs.readFileSync(
        path.join(projectRoot, 'nano_asset/assets/js/table-png-export.js'),
        'utf8'
    );
    assert.match(helper, /\.from\(table\)\s*\.toCanvas\(\)/);
    assert.match(helper, /canvas\.toBlob/);
    assert.match(helper, /Unduh grafik sebagai PNG/);
    assert.match(helper, /chart\.toBase64Image\('image\/png', 1\)/);
});

test('Mermaid export keeps SVG and PNG buttons in its shared toolbar', () => {
    const controls = fs.readFileSync(
        path.join(projectRoot, 'nano_asset/assets/js/ai-mermaid-controls.js'),
        'utf8'
    );
    const nativeShell = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    assert.match(controls, /Unduh diagram sebagai SVG/);
    assert.match(controls, /Unduh diagram sebagai PNG/);
    assert.match(controls, /mermaid-btn-svg/);
    assert.match(controls, /mermaid-btn-png/);
    assert.match(controls, /window\.saveSvgMarkup\s*=\s*saveSvg/);
    assert.match(controls, /messageHandlers\?\.saveSvg/);
    assert.match(nativeShell, /userContentController\.add\((?:self|weakHandler),\s*name:\s*"saveSvg"\)/);
    assert.match(nativeShell, /panel\.allowedContentTypes\s*=\s*\[\.svg\]/);
    assert.match(nativeShell, /handleSvgSaveRequest/);

    for (const page of ['VS.html', 'claude.html']) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        assert.match(source, /window\.saveSvgMarkup\(/, `${page} should use the shared SVG saver`);
    }
});

test('Gemini Live loads PNG export controls for its Chart.js and Markdown table output', () => {
    const source = fs.readFileSync(path.join(projectRoot, 'gemini_live.html'), 'utf8');
    assert.match(source, /table-png-export\.js/);
});

test('PNG exports use the native save bridge when available and do not change chart sizing', () => {
    const helper = fs.readFileSync(
        path.join(projectRoot, 'nano_asset/assets/js/table-png-export.js'),
        'utf8'
    );
    assert.match(helper, /messageHandlers\.savePng\.postMessage/);
    assert.match(helper, /window\.savePngBlob\s*=/);
    assert.match(helper, /window\.savePngDataUrl\s*=/);
    assert.doesNotMatch(helper, /wrapper\.style\.position\s*=/);

    const nativeShell = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    assert.match(nativeShell, /userContentController\.add\((?:self|weakHandler),\s*name:\s*"savePng"\)/);
    assert.match(nativeShell, /NSSavePanel\(\)/);
    assert.match(nativeShell, /imageData\.write\(to:\s*destination,\s*options:\s*\.atomic\)/);
});

test('native WebView cache reload clears only HTTP caches and preserves site storage', () => {
    const nativeShell = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    assert.match(nativeShell, /WKWebsiteDataTypeDiskCache/);
    assert.match(nativeShell, /WKWebsiteDataTypeMemoryCache/);
    assert.match(nativeShell, /removeData\(\s*ofTypes:\s*cacheTypes/);
    assert.match(nativeShell, /(?:self\.)?(?:webView|currentWebView)\??\.reloadFromOrigin\(\)/);
    assert.doesNotMatch(nativeShell, /WKWebsiteDataType(?:Cookies|LocalStorage|IndexedDBDatabases)/);
    assert.match(nativeShell, /Bersihkan cache WebView dan muat ulang/);
});

test('native app title matches the EduVis AI Gallery landing page', () => {
    const nativeShell = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    const landingPage = fs.readFileSync(path.join(projectRoot, 'index.html'), 'utf8');
    const launcher = fs.readFileSync(path.join(projectRoot, 'gemma_chat_gui.py'), 'utf8');
    assert.match(nativeShell, /private let appName = "EduVis AI Gallery"/);
    assert.match(nativeShell, /labelWithString: "EduVis AI Gallery"/);
    assert.match(nativeShell, /NSApp\.applicationIconImage = icon/);
    assert.match(nativeShell, /startStandaloneBackend\(\)/);
    assert.match(nativeShell, /--backend-only/);
    assert.match(nativeShell, /Process\(\)/);
    assert.match(launcher, /CFBundleIconFile/);
    assert.match(launcher, /generate_app_icon\.swift/);
    assert.match(launcher, /"EduVisProjectDirectory":\s*str\(PROJECT_DIR\)/);
    assert.match(launcher, /"EduVisPythonExecutable":\s*sys\.executable/);
    assert.match(landingPage, /rel="icon" type="image\/svg\+xml" href="nano_asset\/assets\/eduvis-icon\.svg"/);
    assert.equal(fs.existsSync(path.join(projectRoot, 'nano_asset/assets/eduvis-icon.svg')), true);
    assert.doesNotMatch(nativeShell, /EDUVIS\s+·\s+LITERT-LM/);
    assert.match(landingPage, /<span>EduVis AI Gallery<\/span>/);
    assert.doesNotMatch(nativeShell, /EduVis LiteRT-LM Gallery/);
});

test('native launcher follows landing-page structure while preserving native workspace controls', () => {
    const nativeShell = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    const appViews = nativeShell.slice(
        nativeShell.indexOf('private let appViews = ['),
        nativeShell.indexOf('private var window:')
    );
    const launcher = nativeShell.slice(
        nativeShell.indexOf('private func makeLauncherView()'),
        nativeShell.indexOf('private func updateStartupStatus()')
    );
    assert.match(appViews, /Utama/);
    assert.match(appViews, /VS/);
    assert.match(appViews, /Claude/);
    assert.match(appViews, /EduVis/);
    assert.match(appViews, /EduVis Live/);
    assert.match(appViews, /Liquid Chatbot/);
    assert.match(appViews, /Aurora/);
    assert.match(appViews, /Tanya AI/);
    assert.match(appViews, /tanya-ai-standalone\.html/);
    assert.match(launcher, /EduVis AI Gallery/);
    assert.match(launcher, /antarmuka/);
    assert.match(launcher, /tampilan/);
    assert.match(launcher, /Berjalan di jaringan lokal/);
    assert.match(launcher, /Pilih ruang kerja Anda\./);
    assert.match(launcher, /Workspace tersedia/);
    assert.match(launcher, /leftRail\.leadingAnchor\.constraint\(equalTo:\s*view\.leadingAnchor/);
    assert.match(launcher, /spaceLensContainer\.leadingAnchor\.constraint\(equalTo:\s*leftCenterColumn\.trailingAnchor/);
    assert.match(launcher, /leftRail|makeCleanMyMacRailIcon/);
    assert.match(launcher, /tooltip:\s*"Segarkan Memori LiteRT-LM"/);
    assert.match(launcher, /NSPopUpButton\(\)/);
    assert.match(launcher, /action: #selector\(openSelectedView\)/);
    assert.match(launcher, /startupStatus = NSTextField/);
    assert.match(launcher, /Banner EduVis AI Gallery/);
    assert.match(launcher, /TENTANG TEKNOLOGI/);
    assert.match(nativeShell, /readinessPath = CommandLine\.arguments\[3\]/);
});

test('native model center supports status, selection, deletion, and drag-and-drop imports', () => {
    const nativeShell = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    const launcher = fs.readFileSync(path.join(projectRoot, 'gemma_chat_gui.py'), 'utf8');
    assert.match(nativeShell, /Pusat Model…/);
    assert.match(nativeShell, /Seret file \.litertlm ke sini/);
    assert.match(nativeShell, /NSOpenPanel\(\)/);
    assert.match(nativeShell, /uploadTask\(with:\s*request,\s*fromFile:\s*url\)/);
    assert.match(nativeShell, /Gunakan Model/);
    assert.match(nativeShell, /confirmDeleteModel/);
    assert.match(nativeShell, /didSendBodyData/);
    assert.match(launcher, /\/api\/import-model-upload/);
    assert.match(launcher, /MAX_MODEL_UPLOAD_SIZE/);
    assert.match(launcher, /is_loopback/);
    assert.match(launcher, /self\.model_manager\.import_model\(temporary_path,\s*model_id\)/);
});

test('Gemini Live uses native macOS speech recognition inside the launcher', () => {
    const nativeShell = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    const launcher = fs.readFileSync(path.join(projectRoot, 'gemma_chat_gui.py'), 'utf8');
    const conversation = fs.readFileSync(path.join(projectRoot, 'live-conversation.js'), 'utf8');

    assert.match(nativeShell, /import AVFoundation/);
    assert.match(nativeShell, /import Speech/);
    assert.match(nativeShell, /add\((?:self|weakHandler), name: "nativeSpeech"\)/);
    assert.match(nativeShell, /SFSpeechRecognizer\.requestAuthorization/);
    assert.match(nativeShell, /AVCaptureDevice\.requestAccess\(for: \.audio/);
    assert.match(launcher, /NSMicrophoneUsageDescription/);
    assert.match(launcher, /NSSpeechRecognitionUsageDescription/);
    assert.match(launcher, /"\-n",\s*"\-W",\s*str\(webview_bundle\)/);
    assert.match(launcher, /CFBundleIdentifier/);
    assert.match(conversation, /window\.webkit\?\.messageHandlers\?\.nativeSpeech/);
    assert.match(conversation, /native-speech-event/);
});

test('Gemini Live forwards native speech events through its existing recognition handlers', () => {
    const conversation = fs.readFileSync(path.join(projectRoot, 'live-conversation.js'), 'utf8');
    const listeners = new Map();
    const postedMessages = [];
    const browserWindow = {
        webkit: {
            messageHandlers: {
                nativeSpeech: {
                    postMessage: message => postedMessages.push(message)
                }
            }
        },
        addEventListener: (name, listener) => listeners.set(name, listener)
    };
    vm.runInNewContext(conversation, { window: browserWindow });

    const controller = new browserWindow.LiveConversationController();
    assert.equal(controller.createRecognition(), true);
    let receivedTranscript = '';
    let receivedFinal = false;
    controller.recognition.onresult = event => {
        receivedTranscript = event.results[0][0].transcript;
        receivedFinal = event.results[0].isFinal;
    };
    controller.recognition.start();
    assert.equal(postedMessages[0].action, 'start');
    assert.equal(postedMessages[0].language, 'id-ID');

    listeners.get('native-speech-event')({
        detail: { type: 'result', transcript: 'Halo', isFinal: true }
    });
    assert.equal(receivedTranscript, 'Halo');
    assert.equal(receivedFinal, true);
});

test('landing page links all workspaces to their local preview images', () => {
    const landingPage = fs.readFileSync(path.join(projectRoot, 'index.html'), 'utf8');
    const server = fs.readFileSync(path.join(projectRoot, 'gemma_chat_gui.py'), 'utf8');
    const cards = [
        ['utama.html', 'nano_asset/assets/landing-utama.jpg'],
        ['VS.html', 'nano_asset/assets/landing-vs.jpg'],
        ['claude.html', 'nano_asset/assets/landing-claude.jpg'],
        ['utamaV2.html', 'nano_asset/assets/landing-v2.jpg'],
        ['liquid_chatbot.html', 'nano_asset/assets/landing-v2.jpg'],
        ['aurora.html', 'nano_asset/assets/landing-eduvis.jpg'],
        ['gemini_live.html', 'nano_asset/assets/landing-live.jpg'],
        ['analisis-kode.html', 'nano_asset/assets/landing-vs.jpg'],
    ];

    for (const [page, image] of cards) {
        assert.match(landingPage, new RegExp(`data-app-page="${page}" href="${page}"`));
        assert.match(landingPage, new RegExp(`<img src="${image}"`));
        assert.equal(fs.existsSync(path.join(projectRoot, image)), true, `${image} should exist`);
    }
    assert.match(landingPage, /data-app-page="tanya-ai-standalone\.html" href="tanya-ai-standalone\.html"/);
    assert.match(landingPage, /Tanya AI Standalone/);
    assert.match(server, /"tanya-ai-standalone\.html"/);
    assert.match(server, /requested_path\.is_relative_to\(assets_path\)/);
    assert.match(landingPage, /Sembilan antarmuka/);
    assert.match(landingPage, /<span>9 tampilan<\/span>/);
    assert.doesNotMatch(landingPage, /data-app-page="eduVis\.html"/);
});

test('shared AI room navigation includes Tanya AI and standalone page marks its current room', () => {
    const navigation = fs.readFileSync(path.join(projectRoot, 'nano_asset/assets/js/app-navigation.js'), 'utf8');
    const standalone = fs.readFileSync(path.join(projectRoot, 'tanya-ai-standalone.html'), 'utf8');
    assert.match(navigation, /id: 'tanya-ai', label: 'Tanya AI', href: '\.\/tanya-ai-standalone\.html'/);
    assert.match(standalone, /<script src="nano_asset\/assets\/js\/app-navigation\.js" defer><\/script>/);
    assert.match(standalone, /<app-navigation current="tanya-ai"><\/app-navigation>/);
});

test('Tanya AI settings use the local LiteRT-LM model and import controls', () => {
    const standalone = fs.readFileSync(path.join(projectRoot, 'tanya-ai-standalone.html'), 'utf8');
    assert.match(standalone, /id="loadModels"/);
    assert.match(standalone, /id="importedModels"/);
    assert.match(standalone, /id="localModelFile"/);
    assert.match(standalone, /id="importLocalModel"/);
    assert.match(standalone, /min="2048" max="16384" step="512"/);
    assert.match(standalone, /fetch\("\/api\/models"/);
    assert.match(standalone, /fetch\("\/api\/local-models"/);
    assert.match(standalone, /fetch\("\/api\/import-model"/);
    assert.match(standalone, /fetch\("\/api\/delete-model"/);
    assert.match(standalone, /getLocalApiBaseUrl/);
});

test('Tanya AI standalone loads local Markdown and visualization libraries', () => {
    const standalone = fs.readFileSync(path.join(projectRoot, 'tanya-ai-standalone.html'), 'utf8');
    const assets = [
        'nano_asset/assets/js/marked.min.js',
        'nano_asset/assets/js/mermaid-normalizer.js',
        'nano_asset/assets/js/chart-config-normalizer.js',
        'nano_asset/assets/js/tanya-ai-smart-prompt.js',
        'nano_asset/assets/js/highlight.min.js',
        'nano_asset/assets/js/katex.min.js',
        'nano_asset/assets/js/chart.min.js',
        'nano_asset/assets/js/mermaid.min.js',
        'nano_asset/assets/js/d3.v7.min.js',
        'nano_asset/assets/js/markmap-view.min.js',
        'nano_asset/assets/js/markmap-lib.min.js',
        'nano_asset/assets/css/katex.min.css',
    ];

    for (const asset of assets) {
        assert.ok(standalone.includes(asset), `${asset} should be referenced`);
        assert.equal(fs.existsSync(path.join(projectRoot, asset)), true, `${asset} should exist`);
    }
});

test('Tanya AI can extract PDF, DOCX, and spreadsheet attachments for analysis', () => {
    const standalone = fs.readFileSync(path.join(projectRoot, 'tanya-ai-standalone.html'), 'utf8');
    for (const asset of [
        'nano_asset/assets/js/pdf.min.js',
        'nano_asset/assets/js/mammoth.browser.min.js',
        'nano_asset/assets/js/xlsx.full.min.js',
    ]) {
        assert.ok(standalone.includes(asset), `${asset} should be referenced`);
        assert.equal(fs.existsSync(path.join(projectRoot, asset)), true, `${asset} should exist`);
    }

    assert.match(standalone, /async function extractDocumentText\(file\)/);
    assert.match(standalone, /pdfjsLib\.getDocument/);
    assert.match(standalone, /mammoth\.extractRawText/);
    assert.match(standalone, /XLSX\.utils\.sheet_to_csv/);
    assert.match(standalone, /PDF hasil pindai memerlukan OCR/);
    assert.match(standalone, /application\/pdf/);
    assert.match(standalone, /application\/vnd\.openxmlformats-officedocument\.wordprocessingml\.document/);
});

test('Tanya AI standalone renders visual formats and uses isolated code runners', () => {
    const standalone = fs.readFileSync(path.join(projectRoot, 'tanya-ai-standalone.html'), 'utf8');
    const pythonWorker = fs.readFileSync(
        path.join(projectRoot, 'nano_asset/assets/js/tanya-ai-python-worker.js'),
        'utf8'
    );
    assert.match(standalone, /renderer\.code\s*=\s*function/);
    assert.match(standalone, /window\.GemmaMermaid\.normalizeMindmap/);
    assert.match(standalone, /window\.GemmaMermaid\.normalizeFlowchart/);
    assert.match(standalone, /validateChartConfig\(config\)/);
    assert.match(standalone, /katex\.renderToString/);
    assert.match(standalone, /new Worker\("nano_asset\/assets\/js\/tanya-ai-python-worker\.js"\)/);
    assert.match(standalone, /sandbox="allow-scripts"/);
    assert.match(standalone, /data-act="svgdownload"/);
    assert.match(standalone, /data-act="pngdownload"/);
    assert.match(standalone, /\.prose \.diagram-wrapper\s*\{[^}]*resize:\s*vertical/);
    assert.match(standalone, /\.prose \.diagram-wrapper\s*\{[^}]*max-height:\s*80vh/);
    assert.match(standalone, /indexedDB\.open\("GeminiChatDB"\)/);
    assert.match(standalone, /createObjectStore\("sessions", \{ keyPath: "id", autoIncrement: true \}\)/);
    assert.match(standalone, /appSource: "tanya-ai-standalone"/);
    assert.match(standalone, /fileMetadata: metadata\.length \? metadata : null/);
    assert.match(standalone, /Impor percakapan lintas ruang/);
    assert.match(standalone, /initializeVisuals\(body\)/);
    assert.match(pythonWorker, /importScripts\("pyodide\.js"\)/);
});

test('Tanya AI smart prompt mapping routes visual and code requests into system instructions', () => {
    const mappingSource = fs.readFileSync(
        path.join(projectRoot, 'nano_asset/assets/js/tanya-ai-smart-prompt.js'),
        'utf8'
    );
    const browserWindow = {};
    vm.runInNewContext(mappingSource, { window: browserWindow });
    const map = browserWindow.TanyaAISmartPrompt.mapFormatInstructions;

    assert.match(map('Buat peta pikiran tentang fotosintesis'), /satu blok ```mermaid/);
    assert.match(map('Buat flow-chart proses login'), /flowchart TD/);
    assert.match(map('Tampilkan grafik pertumbuhan pengguna'), /satu blok ```chart/);
    assert.match(map('Tulis fungsi JavaScript untuk mengurutkan daftar'), /fenced code block/);
    assert.equal(map('Jelaskan fotosintesis dengan sederhana'), '');

    const standalone = fs.readFileSync(path.join(projectRoot, 'tanya-ai-standalone.html'), 'utf8');
    assert.match(standalone, /id="promptMapping" type="checkbox" checked/);
    assert.match(standalone, /provider\.promptMapping/);
    assert.match(standalone, /window\.TanyaAISmartPrompt/);
    assert.match(standalone, /promptMapping: \$\("promptMapping"\)\.checked/);
});

test('landing page developer modal uses the local portrait and has accessible open and close controls', () => {
    const landingPage = fs.readFileSync(path.join(projectRoot, 'index.html'), 'utf8');
    assert.match(landingPage, /<dialog[^>]*id="developer-modal"[^>]*aria-labelledby="developer-name"/);
    assert.match(landingPage, /id="developer-open"[^>]*aria-haspopup="dialog"[^>]*aria-controls="developer-modal"/);
    assert.match(landingPage, /src="nano_asset\/assets\/landing-developer\.jpeg" alt="Foto Subuh Kurniawan"/);
    assert.match(landingPage, /<h2 id="developer-name">Subuh Kurniawan<\/h2>/);
    assert.match(landingPage, /Developer — EduVis Project/);
    assert.match(landingPage, /developerModal\.showModal\(\)/);
    assert.match(landingPage, /developerModal\.close\(\)/);
    assert.equal(fs.existsSync(path.join(projectRoot, 'nano_asset/assets/landing-developer.jpeg')), true);
});

test('landing page shows usage and model setup splash with a reopen control', () => {
    const landingPage = fs.readFileSync(path.join(projectRoot, 'index.html'), 'utf8');
    assert.match(landingPage, /<dialog[^>]*id="guide-modal"[^>]*aria-labelledby="guide-title"/);
    assert.match(landingPage, /id="guide-open"[^>]*aria-haspopup="dialog"[^>]*aria-controls="guide-modal"/);
    assert.match(landingPage, /id="guide-title">Petunjuk penggunaan &(?:amp;)? pemuatan model<\/h2>/);
    assert.match(landingPage, /Pilih workspace/);
    assert.match(landingPage, /file model berformat <code>\.litertlm<\/code>/);
    assert.match(landingPage, /Impor Model Lokal/);
    assert.match(landingPage, /Impor ke LiteRT-LM/);
    assert.match(landingPage, /id="guide-suppress" type="checkbox"/);
    assert.match(landingPage, /localStorage\.setItem\(guidePreferenceKey, 'true'\)/);
    assert.match(landingPage, /guideModal\.showModal\(\)/);
    assert.match(landingPage, /guideModal\.close\(\)/);
});

test('Utama pages expand chart replies and keep Chart.js responsive to the container', () => {
    const pages = ['utama.html', 'utamaV2.html'];
    const helper = fs.readFileSync(
        path.join(projectRoot, 'nano_asset/assets/js/table-png-export.js'),
        'utf8'
    );
    assert.match(helper, /canvas\.closest\('#messages \.chat-bubble-ai'\)/);
    assert.match(helper, /messageBubble\.classList\.add\('has-chart-output'\)/);
    assert.match(helper, /messageBubble\.closest\('#messages \.max-w-4xl'\)\?\.classList\.add\('has-chart-output-row'\)/);
    assert.ok(
        helper.indexOf("messageBubble.classList.add('has-chart-output')") <
        helper.indexOf('wrapper.querySelector(`:scope > .${chartToolbarClass}`)'),
        'chart reply sizing should be marked even if its export toolbar already exists'
    );

    for (const file of pages) {
        const source = fs.readFileSync(path.join(projectRoot, file), 'utf8');
        const bubbleSelector = file === 'utamaV2.html'
            ? '#messages .v2-chat-reply.has-chart-output'
            : '#messages .chat-bubble-ai.has-chart-output';
        if (file === 'utama.html') {
            assert.match(source, /#messages \.max-w-4xl\.has-chart-output-row\s*\{\s*width:\s*100%\s*!important;\s*max-width:\s*100%\s*!important;/);
        }
        assert.match(source, new RegExp(`${bubbleSelector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*\\{[\\s\\S]*?width:\\s*100%\\s*!important;[\\s\\S]*?max-width:\\s*100%\\s*!important;`));
        assert.match(source, /height:\s*clamp\(240px,\s*42vw,\s*350px\)\s*!important;/);
        assert.match(source, /height:\s*clamp\(240px,\s*75vw,\s*340px\)\s*!important;/);
        assert.equal((source.match(/config\.options\.maintainAspectRatio = false;/g) || []).length, 3);
        assert.equal((source.match(/config\.options\.responsive = true;/g) || []).length, 3);
    }
});

test('completed AI replies initialize and resize charts without requiring a UI switch', () => {
    for (const page of ['utama.html', 'utamaV2.html']) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        const finishIndex = source.indexOf('function finishLoadingBubble(');
        assert.notEqual(finishIndex, -1, `${page} should finalize completed AI replies`);
        const finishHandler = source.slice(finishIndex, finishIndex + 6000);

        assert.match(
            finishHandler,
            /setTimeout\(async\s*\(\)\s*=>\s*\{\s*await new Promise\(resolve => requestAnimationFrame\(\(\) => requestAnimationFrame\(resolve\)\)\);/,
            `${page} should wait for the final reply layout before rendering charts`
        );
        assert.match(finishHandler, /const chart = new Chart\(canvas\.getContext\('2d'\), config\)/);
        assert.match(finishHandler, /if \(canvas\.isConnected\) chart\.resize\(\)/);
    }

    for (const page of ['VS.html', 'claude.html']) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        const renderIndex = source.indexOf('window.renderMarkdownAndMermaid = async function(');
        assert.notEqual(renderIndex, -1, `${page} should render final AI replies`);
        const renderHandler = source.slice(renderIndex, renderIndex + 1000);

        assert.match(
            renderHandler,
            /if \(!skipMermaid\) \{\s*await new Promise\(resolve => requestAnimationFrame\(\(\) => requestAnimationFrame\(resolve\)\)\);\s*await window\.initializeSmartComponents\(target\);/,
            `${page} should initialize charts and diagrams after the final reply is laid out`
        );
    }
});
