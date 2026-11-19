const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const projectRoot = path.resolve(__dirname, '..');
const cssPath = path.join(projectRoot, 'nano_asset/assets/css/native-mac.css');

// Memecah daftar selector pada koma tingkat atas saja (koma di dalam :is(...) tidak dihitung).
function splitTopLevel(list) {
    const parts = [];
    let depth = 0, current = '';
    for (const ch of list) {
        if (ch === '(') depth++;
        if (ch === ')') depth--;
        if (ch === ',' && depth === 0) { parts.push(current.trim()); current = ''; continue; }
        current += ch;
    }
    if (current.trim()) parts.push(current.trim());
    return parts.filter(Boolean);
}

test('native-mac.css only affects the native app (every selector is scoped to html.macos-native)', () => {
    const css = fs.readFileSync(cssPath, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    assert.doesNotMatch(css, /@keyframes|@font-face|@import/, 'at-rule global tidak boleh ada di file ini');

    const ruleRe = /([^{}]+)\{([^{}]*)\}/g;
    let match, count = 0;
    while ((match = ruleRe.exec(css))) {
        const prelude = match[1].trim();
        if (prelude.startsWith('@')) continue;
        for (const selector of splitTopLevel(prelude)) {
            count++;
            assert.match(selector, /^html\.macos-native(?![\w-])/, `selector bocor ke klien browser: "${selector}"`);
        }
    }
    assert.ok(count > 15, 'file harus berisi aturan nyata');
});

test('native-mac.css implements Apple chat conventions', () => {
    const css = fs.readFileSync(cssPath, 'utf8');
    assert.match(css, /-apple-system/);
    assert.match(css, /\.chat-bubble-user/);
    assert.match(css, /\.chat-bubble-ai/);
    assert.match(css, /#drop-zone/);
    assert.match(css, /:focus-visible/);
    assert.match(css, /prefers-reduced-motion: reduce/);
    assert.match(css, /user-select:\s*text/);
});

test('native workspace controls use restrained hover, active, and disabled feedback', () => {
    const css = fs.readFileSync(cssPath, 'utf8');
    assert.match(css, /\.sidebar \.nav-item\.active[\s\S]*?inset 3px 0 0 var\(--nm-accent\)/);
    assert.match(css, /body :is\(button,\s*\[role="button"\],\s*a\)[\s\S]*?transition:/);
    assert.match(css, /body button:disabled[\s\S]*?opacity:\s*0\.58/);
    assert.match(css, /\*::-webkit-scrollbar-thumb[\s\S]*?border-radius:\s*999px/);
});

test('every chat page loads native-mac.css and the web client page markup stays untouched by it', () => {
    for (const page of ['utama.html', 'utamaV2.html', 'VS.html', 'claude.html', 'vision_ulti.html']) {
        const html = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        assert.match(html, /native-mac\.css/, `${page} harus memuat native-mac.css`);
        assert.equal(html.split('native-mac.css').length - 1, 1, `${page} hanya boleh memuatnya sekali`);
    }
});

test('native shell injects native-mac.css into every workspace page', () => {
    const swift = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    assert.match(swift, /native-mac\.css/);
    assert.match(swift, /data-native-mac/);
    assert.match(swift, /injectionTime: \.atDocumentEnd/);
});

test('native-mac.css fixes claude user bubble, prose contrast, and window background variables', () => {
    const css = fs.readFileSync(cssPath, 'utf8');
    assert.match(css, /\.chat-bubble-user:has\(\.claude-user-bubble\)[\s\S]*?background:\s*transparent\s*!important/);
    assert.match(css, /\.claude-user-bubble[\s\S]*?background:\s*var\(--nm-accent\)\s*!important/);
    assert.match(css, /\.claude-user-bubble[\s\S]*?width:\s*fit-content\s*!important/);
    assert.match(css, /--mac-window-bg:\s*#1e1e1e/);
    assert.match(css, /--tw-prose-headings:\s*var\(--nm-text\)\s*!important/);
    assert.match(css, /html\.macos-native #chat-area > header[\s\S]*?display:\s*none\s*!important/);
    assert.match(css, /html\.macos-native app-navigation[\s\S]*?display:\s*none\s*!important/);

    const swift = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    assert.match(swift, /toolbarWorkspacePicker/);
    assert.match(swift, /toolbarToggleTheme/);
    assert.match(swift, /toolbarOpenLanQR/);

    const guiPy = fs.readFileSync(path.join(projectRoot, 'gemma_chat_gui.py'), 'utf8');
    assert.match(guiPy, /"agen-ai-otonom\.html"/);
    assert.match(guiPy, /"mesin-pglite-rag\.html"/);
});

test('native macOS table styling supports responsive horizontal scrolling and prevents flex blowout', () => {
    const css = fs.readFileSync(cssPath, 'utf8');
    assert.match(css, /\.table-wrapper[\s\S]*?min-width:\s*0\s*!important/);
    assert.match(css, /\.chat-bubble-ai[\s\S]*?min-width:\s*0\s*!important/);
    assert.match(css, /\.table-wrapper[\s\S]*?overflow-x:\s*auto\s*!important/);
    assert.match(css, /\.table-wrapper\s*>\s*table[\s\S]*?width:\s*max-content\s*!important/);
    assert.match(css, /#messages\s+table[\s\S]*?border-collapse:\s*collapse\s*!important/);

    const helper = fs.readFileSync(path.join(projectRoot, 'nano_asset/assets/js/table-png-export.js'), 'utf8');
    assert.match(helper, /function\s+ensureTableWrapper/);
    assert.match(helper, /table-wrapper custom-scrollbar/);

    const swift = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    assert.match(swift, /html\.macos-native \.table-wrapper[\s\S]*?overflow-x:\s*auto\s*!important/);
    assert.match(swift, /html\.macos-native \.chat-bubble-ai[\s\S]*?min-width:\s*0\s*!important/);
});

test('Apple Liquid Glass HIG layout, concentric geometry, and specular glass surfaces are applied across EduVis AI Gallery', () => {
    const nativeCss = fs.readFileSync(cssPath, 'utf8');
    assert.match(nativeCss, /--lg-blur:\s*blur\((?:var\(--glass-blur,\s*)?30px\)?\)\s+saturate\((?:var\(--glass-saturate,\s*)?200%\)?\)/);
    assert.match(nativeCss, /--lg-specular-border:/);
    assert.match(nativeCss, /--lg-specular-shadow:/);
    assert.match(nativeCss, /--lg-radius-outer:\s*24px/);
    assert.match(nativeCss, /--lg-radius-card:\s*16px/);
    assert.match(nativeCss, /mask-image:/);

    const renderCss = fs.readFileSync(path.join(projectRoot, 'nano_asset/assets/css/ai-renderers.css'), 'utf8');
    assert.match(renderCss, /--apple-lg-blur:/);
    assert.match(renderCss, /\.apple-liquid-glass-pill/);
    assert.match(renderCss, /\.apple-liquid-glass-card/);
    assert.match(renderCss, /\.apple-liquid-glass-toolbar/);

    const swift = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    assert.match(swift, /class LiquidGlassSurfaceView:\s*NSVisualEffectView/);
    assert.match(swift, /func makeLiquidGlassSurface\(/);
    assert.match(swift, /cornerCurve\s*=\s*\.continuous/);

    const indexHtml = fs.readFileSync(path.join(projectRoot, 'index.html'), 'utf8');
    assert.match(indexHtml, /\.ws-card\s*\{[\s\S]*?border-radius:\s*24px/);
    assert.match(indexHtml, /\.ws-preview-frame\s*\{[\s\S]*?border-radius:\s*16px/);

    const modifierSwift = fs.readFileSync(path.join(projectRoot, 'EduVisNativeApp/LiquidGlassModifier.swift'), 'utf8');
    assert.match(modifierSwift, /struct LiquidGlassCardModifier/);
    assert.match(modifierSwift, /func liquidGlassCard\(/);

    assert.match(nativeCss, /#messages\s+\.prose[\s\S]*?font-size:\s*var\(--chat-font-size/);
    assert.match(nativeCss, /\.claude-user-bubble[\s\S]*?font-size:\s*var\(--chat-font-size/);
    assert.match(nativeCss, /\.gemma-font-widget\s+\.gfc-controls[\s\S]*?display:\s*inline-flex\s*!important/);
});

test('HTML UI consistency across Tanya AI, EduVis, Liquid Chatbot, Utama, and native toolbar theme sync', () => {
    const nativeCss = fs.readFileSync(cssPath, 'utf8');
    assert.doesNotMatch(nativeCss, /body:has\(\.composer\):not\(\.dark\)/);
    assert.match(nativeCss, /html\.macos-native\[data-theme="light"\]\s+body/);
    assert.match(nativeCss, /\.main\s*>\s*header\.topbar/);
    assert.match(nativeCss, /padding-bottom:\s*58px\s*!important/);
    assert.match(nativeCss, /\.app-shell\s*>\s*\.sidebar[\s\S]*?var\(--lg-surface-glass\)/);
    assert.match(nativeCss, /#chat-area footer[\s\S]*?background:\s*transparent\s*!important/);

    const swift = fs.readFileSync(path.join(projectRoot, 'gemma_webview.swift'), 'utf8');
    assert.doesNotMatch(swift, /body:has\(\.composer\):not\(\.dark\)/);
    assert.match(swift, /func applyToolbarTheme\(/);
    assert.match(swift, /data-theme/);
    assert.match(swift, /native-mac\.css\?v=11/);
});
