const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const projectRoot = path.resolve(__dirname, '..');
const aiRenderersCssPath = path.join(projectRoot, 'nano_asset/assets/css/ai-renderers.css');

test('ai-renderers.css defines unified theme-independent AI settings modal styles', () => {
    assert.equal(fs.existsSync(aiRenderersCssPath), true, 'ai-renderers.css must exist');
    const css = fs.readFileSync(aiRenderersCssPath, 'utf8');

    // Modal root & card rules
    assert.match(css, /#ai-settings-modal/);
    assert.match(css, /html body\.light-theme #ai-settings-modal/);
    assert.match(css, /html body\.light-theme #ai-settings-modal > div/);

    // Text color safeguards against dark text on dark background in light-theme
    assert.match(css, /html body\.light-theme #ai-settings-modal \.text-white/);
    assert.match(css, /html body\.light-theme #ai-settings-modal \.text-slate-100/);
    assert.match(css, /html body\.light-theme #ai-settings-modal \.text-slate-200/);
    assert.match(css, /html body\.light-theme #ai-settings-modal \.text-slate-400/);

    // Input & textarea background & text color safeguards
    assert.match(css, /html body\.light-theme #ai-settings-modal input/);
    assert.match(css, /html body\.light-theme #ai-settings-modal textarea/);
    assert.match(css, /html body\.light-theme #ai-settings-modal select/);

    // Button & section card safeguards
    assert.match(css, /html body\.light-theme #ai-settings-modal button\[onclick\*="closeAISettingsModal"\]/);
    assert.match(css, /html body\.light-theme #ai-settings-modal button\[onclick\*="applyAISettings"\]/);
});

test('all workspace modules link ai-renderers.css and define #ai-settings-modal', () => {
    const pages = [
        'claude.html',
        'VS.html',
        'utama.html',
        'utamaV2.html',
        'vision_ulti.html',
        'eduVis.html',
        'liquid_chatbot.html',
        'aurora.html'
    ];

    for (const page of pages) {
        const filePath = path.join(projectRoot, page);
        const html = fs.readFileSync(filePath, 'utf8');

        assert.match(html, /ai-renderers\.css/, `${page} must link ai-renderers.css`);
        assert.match(html, /id="ai-settings-modal"/, `${page} must define #ai-settings-modal`);
        assert.match(html, /id="ai-system-prompt"/, `${page} must include ai-system-prompt inside modal`);
    }
});

test('lan-qrcode.js and ai-renderers.css define unified theme-independent LAN QR modal UI', () => {
    const lanQrScriptPath = path.join(projectRoot, 'nano_asset/assets/js/lan-qrcode.js');
    assert.equal(fs.existsSync(lanQrScriptPath), true, 'lan-qrcode.js must exist');
    const js = fs.readFileSync(lanQrScriptPath, 'utf8');
    const css = fs.readFileSync(aiRenderersCssPath, 'utf8');

    // lan-qrcode.js injects dedicated isolated styles and color-scheme
    assert.match(js, /style\.id = 'lan-qr-styles'/, 'lan-qrcode.js should inject dedicated scoped styles');
    assert.match(js, /color-scheme:\s*dark/i, 'lan-qrcode.js should enforce dark color-scheme');
    assert.match(js, /#lan-qr-title/, 'lan-qrcode.js should explicitly style title');
    assert.match(js, /#lan-qr-address-select/, 'lan-qrcode.js should explicitly style select control');
    assert.match(js, /#lan-qr-copy/, 'lan-qrcode.js should explicitly style copy button');
    assert.match(js, /status-url/, 'lan-qrcode.js should use dedicated status classes');
    assert.match(js, /status-success/, 'lan-qrcode.js should use dedicated success class');
    assert.match(js, /status-error/, 'lan-qrcode.js should use dedicated error class');

    // ai-renderers.css safeguards against theme bleed
    assert.match(css, /#lan-qr-modal/, 'ai-renderers.css should define #lan-qr-modal');
    assert.match(css, /html body\.light-theme #lan-qr-modal/, 'ai-renderers.css should protect #lan-qr-modal in light theme');
    assert.match(css, /html body\.light-theme #lan-qr-modal h2/, 'ai-renderers.css should protect h2 in light theme');
    assert.match(css, /html body\.light-theme #lan-qr-modal select/, 'ai-renderers.css should protect select in light theme');
    assert.match(css, /html body\.light-theme #lan-qr-modal button#lan-qr-copy/, 'ai-renderers.css should protect copy button in light theme');
});

