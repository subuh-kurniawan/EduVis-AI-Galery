const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const projectRoot = path.resolve(__dirname, '..');
const exportModulePath = path.join(projectRoot, 'nano_asset/assets/js/chat-export.js');
const GemmaExport = require(exportModulePath);
const JSZip = require(path.join(projectRoot, 'nano_asset/assets/js/jszip.min.js'));

test('GemmaExport exports required core methods', () => {
    assert.equal(typeof GemmaExport.extractConversationSnapshot, 'function');
    assert.equal(typeof GemmaExport.generateCleanHtmlDoc, 'function');
    assert.equal(typeof GemmaExport.generateDocxBlob, 'function');
    assert.equal(typeof GemmaExport.printToPdf, 'function');
    assert.equal(typeof GemmaExport.exportToPdf, 'function');
    assert.equal(typeof GemmaExport.exportToDocx, 'function');
    assert.equal(typeof GemmaExport.saveDocumentBlob, 'function');
    assert.equal(typeof GemmaExport.showToast, 'function');
});

test('generateCleanHtmlDoc creates valid clean print HTML with page-break controls and typography', () => {
    const snapshot = {
        title: 'Modul Ekosistem Biologi Fase E',
        exportedAt: 'Senin, 12 Oktober 2026 pukul 10:30',
        messages: [
            {
                sender: 'Pengguna (Guru)',
                isUser: true,
                html: '<p>Tolong buatkan alur rantai makanan padang rumput.</p>',
                text: 'Tolong buatkan alur rantai makanan padang rumput.',
                timestamp: '10:28'
            },
            {
                sender: 'Asisten EduVis AI',
                isUser: false,
                html: '<h2>Rantai Makanan Savana</h2><p>Berikut alur energinya:</p><table><thead><tr><th>Tingkat Trofik</th><th>Organisme</th></tr></thead><tbody><tr><td>Produsen</td><td>Rumput</td></tr></tbody></table>',
                text: 'Rantai Makanan Savana Berikut alur energinya: Produsen Rumput',
                timestamp: '10:30'
            }
        ]
    };

    const html = GemmaExport.generateCleanHtmlDoc(snapshot);

    assert.ok(html.includes('size: A4 portrait'), 'Print document must specify A4 portrait size');
    assert.ok(html.includes('page-break-inside: avoid'), 'Document elements must specify print page-break avoidance');
    assert.ok(html.includes('Modul Ekosistem Biologi Fase E'), 'Header must contain the chat title');
    assert.ok(html.includes('sender-badge user'), 'User message must have user sender badge class');
    assert.ok(html.includes('sender-badge assistant'), 'AI message must have assistant sender badge class');
    assert.ok(html.includes('Tingkat Trofik'), 'Table content must be retained in clean print HTML');
    assert.ok(html.includes('<main class="gemma-export-document">'), 'Export content must be isolated from the chat page styles');
    assert.ok(html.includes('.gemma-export-document {'), 'Print typography must target the isolated export document');
});

test('PDF rendering loads html2pdf lazily and captures an in-viewport export root', () => {
    const exporterSource = fs.readFileSync(exportModulePath, 'utf8');

    assert.match(exporterSource, /ensureHtml2Pdf/);
    assert.match(exporterSource, /loadScriptOnce\('nano_asset\/assets\/js\/html2pdf\.bundle\.min\.js'\)/);
    assert.match(exporterSource, /from\(tempRoot\.querySelector\('\.gemma-export-document'\)\)/);
    assert.match(exporterSource, /clonedRoot\.style\.opacity = '1'/);
    assert.doesNotMatch(exporterSource, /tempRoot\.style\.left = '-99999px'/);
});

test('native document export uses the macOS save bridge and registers the handler', () => {
    const exporterSource = fs.readFileSync(exportModulePath, 'utf8');
    const nativeShell = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');

    assert.match(exporterSource, /messageHandlers\?\.saveDocument/);
    assert.match(exporterSource, /__nativeDocumentSaveComplete/);
    assert.match(exporterSource, /output\('blob'\)/);
    assert.match(nativeShell, /userContentController\.add\((?:self|weakHandler)[^,)]*,\s*name:\s*(?:"saveDocument"|handler)\)/);
    assert.match(nativeShell, /handleDocumentSaveRequest/);
    assert.match(nativeShell, /NSSavePanel\(\)/);
    assert.match(nativeShell, /panel\.begin\(completionHandler: handleResponse\)/);
    assert.match(nativeShell, /NSApp\.activate\(ignoringOtherApps: true\)/);
    assert.match(exporterSource, /120000\)/);
    assert.doesNotMatch(exporterSource, /resolve\(triggerBrowserDownload\(filename, fileBlob\)\)/);
});

test('generateDocxBlob generates valid OOXML package with proper XML structure and tables', async () => {
    const snapshot = {
        title: 'Laporan Pembelajaran Fisika',
        exportedAt: 'Senin, 12 Oktober 2026',
        messages: [
            {
                sender: 'Pengguna (Guru)',
                isUser: true,
                html: '<p>Jelaskan hukum Newton I dan II.</p>'
            },
            {
                sender: 'Asisten EduVis AI',
                isUser: false,
                html: '<h2>Hukum Gerak Newton</h2><p>Ringkasan hukum gerak:</p><table><tr><th>Hukum</th><th>Bunyi</th></tr><tr><td>Newton I</td><td>Kelembaman</td></tr></table>'
            }
        ]
    };

    const docResult = await GemmaExport.generateDocxBlob(snapshot);
    assert.ok(docResult, 'generateDocxBlob must return a document');

    const zipBuffer = docResult.arrayBuffer ? await docResult.arrayBuffer() : docResult;
    const zip = await JSZip.loadAsync(zipBuffer);

    // Verify OpenXML structure
    const contentTypes = await zip.file('[Content_Types].xml').async('string');
    assert.ok(contentTypes.includes('wordprocessingml.document.main+xml'), '[Content_Types].xml must declare main document type');
    assert.ok(contentTypes.includes('core-properties'), '[Content_Types].xml must declare core properties metadata');
    assert.ok(contentTypes.includes('extended-properties'), '[Content_Types].xml must declare app metadata');

    const rels = await zip.file('_rels/.rels').async('string');
    assert.ok(rels.includes('relationships/officeDocument'), '_rels/.rels must link to word/document.xml');
    assert.ok(rels.includes('core-properties'), '_rels/.rels must link to docProps/core.xml');
    assert.ok(rels.includes('extended-properties'), '_rels/.rels must link to docProps/app.xml');

    const docXml = await zip.file('word/document.xml').async('string');
    assert.ok(docXml.includes('Laporan Pembelajaran Fisika'), 'document.xml must include document title');
    assert.ok(docXml.includes('Hukum Gerak Newton'), 'document.xml must include headings');
    assert.ok(docXml.includes('<w:tbl>'), 'document.xml must convert HTML table to Word w:tbl');
    assert.ok(docXml.includes('Kelembaman'), 'document.xml must retain cell text');
    assert.ok(docXml.includes('<w:sectPr>'), 'document.xml must include section properties so Word can open the package');

    const stylesXml = await zip.file('word/styles.xml').async('string');
    assert.ok(stylesXml.includes('Heading1'), 'styles.xml must provide heading definitions');
    assert.ok(stylesXml.includes('Heading6'), 'styles.xml must define every heading level exported by the renderer');

    const coreXml = await zip.file('docProps/core.xml').async('string');
    assert.ok(coreXml.includes('EduVis AI Gallery'), 'core.xml must include package metadata');
});

test('generateDocxBlob embeds images and charts into word/media/ and references them in drawingml', async () => {
    const samplePng = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    const snapshot = {
        title: 'Visualisasi Bagan Pembelajaran',
        exportedAt: 'Senin, 12 Oktober 2026',
        messages: [
            {
                sender: 'Asisten EduVis AI',
                isUser: false,
                html: '<p>Berikut diagram alir:</p><img src="' + samplePng + '" alt="Diagram Alur" />'
            }
        ]
    };

    const docResult = await GemmaExport.generateDocxBlob(snapshot);
    const zipBuffer = docResult.arrayBuffer ? await docResult.arrayBuffer() : docResult;
    const zip = await JSZip.loadAsync(zipBuffer);

    // Verify word/media/ image storage
    const mediaFiles = Object.keys(zip.files).filter(f => f.startsWith('word/media/'));
    assert.ok(mediaFiles.length >= 1, 'ZIP must contain at least one file in word/media/');
    assert.ok(mediaFiles.some(file => file.endsWith('.png')), 'PNG images must retain the correct file extension in the DOCX');

    // Verify relationships
    const wordRels = await zip.file('word/_rels/document.xml.rels').async('string');
    assert.ok(wordRels.includes('relationships/image'), 'word/_rels/document.xml.rels must contain image relationship');
    assert.ok(wordRels.includes('relationships/styles'), 'word/_rels/document.xml.rels must reference styles.xml');

    // Verify drawing markup in document.xml
    const docXml = await zip.file('word/document.xml').async('string');
    assert.ok(docXml.includes('<w:drawing>'), 'document.xml must contain w:drawing element');
    assert.ok(docXml.includes('wp:inline'), 'document.xml must contain wp:inline element');
});

test('generateDocxBlob writes [Content_Types].xml as the FIRST zip entry so Word can open it', async () => {
    const samplePng = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    const snapshot = {
        title: 'Uji Urutan Arsip DOCX',
        exportedAt: 'Senin, 12 Oktober 2026',
        messages: [
            { sender: 'Asisten EduVis AI', isUser: false, html: '<p>Teks pembuka.</p><img src="' + samplePng + '" alt="Gambar" />' }
        ]
    };

    const docResult = await GemmaExport.generateDocxBlob(snapshot);
    const zipBuffer = docResult.arrayBuffer ? await docResult.arrayBuffer() : docResult;
    const zip = await JSZip.loadAsync(zipBuffer);

    // The OPC/OOXML spec REQUIRES [Content_Types].xml to be the first entry.
    // Microsoft Word refuses to open the file ("Word experienced an error trying
    // to open the file") when media or other parts precede it.
    const entries = Object.keys(zip.files);
    assert.equal(
        entries[0],
        '[Content_Types].xml',
        '[Content_Types].xml must be the first entry in the DOCX zip (OPC requirement)'
    );

    // Directory-only entries must never precede the content types part either.
    const firstRealPart = entries.find(name => !name.endsWith('/'));
    assert.equal(
        firstRealPart,
        '[Content_Types].xml',
        'No directory or media entry may precede [Content_Types].xml'
    );
});

test('generateDocxBlob produces schema-ordered OOXML that MS Office accepts', async () => {
    // Exercises headings, lists, tables, code, inline formatting, and an image so
    // every code path that emits <w:pPr>/<w:rPr>/<w:tbl> is covered.
    const samplePng = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    const snapshot = {
        title: 'Dokumen Uji Skema',
        exportedAt: 'Senin, 12 Oktober 2026',
        messages: [
            {
                sender: 'Asisten EduVis AI',
                isUser: false,
                html: '<h1>Judul</h1><h3>Sub</h3><p>Teks <strong>tebal</strong> dan <em>miring</em>.</p>'
                    + '<ul><li>satu</li><li>dua</li></ul><ol><li>pertama</li></ol>'
                    + '<table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody></table>'
                    + '<pre><code>const x = 1;</code></pre>'
                    + '<img src="' + samplePng + '" alt="G" />'
            }
        ]
    };

    const docResult = await GemmaExport.generateDocxBlob(snapshot);
    const zipBuffer = docResult.arrayBuffer ? await docResult.arrayBuffer() : docResult;
    const zip = await JSZip.loadAsync(zipBuffer);

    const docXml = await zip.file('word/document.xml').async('string');
    const stylesXml = await zip.file('word/styles.xml').async('string');

    // 1) Run properties (w:b, w:color, w:sz, ...) must live inside <w:rPr>, never
    //    directly under <w:r>. Word rejects the file otherwise.
    assert.doesNotMatch(
        docXml,
        /<w:r><w:(b|i|sz|color|rFonts|u)\b/,
        'run properties must be wrapped in <w:rPr>, not placed directly under <w:r>'
    );

    // 2) Every <w:tbl> must contain a <w:tblGrid> (OPC CT_Tbl requirement).
    const tblCount = (docXml.match(/<w:tbl>/g) || []).length;
    const gridCount = (docXml.match(/<w:tblGrid>/g) || []).length;
    assert.ok(tblCount >= 1, 'expected at least one table in the fixture');
    assert.equal(gridCount, tblCount, 'every <w:tbl> must contain exactly one <w:tblGrid>');

    // 3) OOXML CT_RPr requires <w:color> to precede <w:sz>. Guard both parts.
    for (const [name, xml] of [['document.xml', docXml], ['styles.xml', stylesXml]]) {
        assert.doesNotMatch(
            xml,
            /<w:sz[^/]*\/>\s*<w:color/,
            `${name}: <w:color> must appear before <w:sz> inside <w:rPr>`
        );
    }

    // 4) OOXML CT_PPr requires <w:spacing> to precede <w:ind>.
    assert.doesNotMatch(
        docXml,
        /<w:ind[^/]*\/>\s*<w:spacing/,
        'document.xml: <w:spacing> must appear before <w:ind> inside <w:pPr>'
    );

    // 5) OOXML CT_Shd REQUIRES the w:val attribute. MS Office rejects the file
    //    ("unreadable content") when <w:shd w:fill="..."/> omits it. WPS tolerates it.
    const shdTags = docXml.match(/<w:shd\b[^>]*>/g) || [];
    assert.ok(shdTags.length >= 1, 'expected at least one <w:shd> in the fixture');
    for (const shd of shdTags) {
        assert.match(
            shd,
            /w:val="/,
            `every <w:shd> must carry the required w:val attribute (offender: ${shd})`
        );
    }
});

test('chat pages include chat-export.js and wire up unified export handlers', () => {
    const pages = ['VS.html', 'claude.html', 'utama.html', 'utamaV2.html'];
    for (const page of pages) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');

        assert.match(
            source,
            /nano_asset\/assets\/js\/chat-export\.js/,
            `${page} must include chat-export.js`
        );
        assert.match(
            source,
            /exportHistoryToPDF/,
            `${page} must define or wire exportHistoryToPDF`
        );
        assert.match(
            source,
            /exportHistoryToDocx/,
            `${page} must define or wire exportHistoryToDocx`
        );
        assert.match(
            source,
            /GemmaExport/,
            `${page} must delegate export operations to GemmaExport`
        );
    }
});

test('native EduVis workspace routes PDF and DOCX exports through the GemmaExport save bridge', () => {
    const source = fs.readFileSync(path.join(projectRoot, 'eduVis.html'), 'utf8');

    // Must load the universal exporter so the native save bridge is available
    assert.match(
        source,
        /nano_asset\/assets\/js\/chat-export\.js/,
        'eduVis.html must include chat-export.js'
    );

    // PDF export must delegate to the bridge (not a blocked <a download> via html2pdf().save())
    assert.match(
        source,
        /window\.GemmaExport\.exportToPdf\(/,
        'eduVis.html PDF export must delegate to GemmaExport.exportToPdf'
    );

    // DOCX export must exist and route through the GemmaExport bridge
    assert.match(
        source,
        /async function (?:exportToDocx|exportHistoryToDocx)\(/,
        'eduVis.html must define exportToDocx or exportHistoryToDocx'
    );
    assert.match(
        source,
        /(?:window\.GemmaExport(?:\?)?\.exportToDocx|window\.GemmaExport\.generateDocxBlob)/,
        'eduVis.html DOCX export must build and export the package via GemmaExport'
    );
});
