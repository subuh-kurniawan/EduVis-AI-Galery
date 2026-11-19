const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const SCRIPT_PATH = path.join(__dirname, '..', 'nano_asset', 'assets', 'js', 'chat-font-size.js');
const CSS_PATH = path.join(__dirname, '..', 'nano_asset', 'assets', 'css', 'ai-renderers.css');

test('chat-font-size.js exists, loads, and initializes the global API', () => {
    assert.ok(fs.existsSync(SCRIPT_PATH), 'chat-font-size.js harus ada');
    const code = fs.readFileSync(SCRIPT_PATH, 'utf-8');
    assert.ok(code.length > 500, 'chat-font-size.js tidak boleh kosong');

    // Create a mock browser DOM environment
    const storageMap = new Map();
    const styleElements = new Map();
    const eventsDispatched = [];

    const mockDocument = {
        readyState: 'complete',
        documentElement: {
            style: {
                properties: {},
                setProperty(name, val) { this.properties[name] = val; },
                getPropertyValue(name) { return this.properties[name] || ''; }
            },
            setAttribute(name, val) { this[name] = val; }
        },
        head: {
            appendChild(el) { styleElements.set(el.id, el); return el; }
        },
        body: {
            appendChild(el) { return el; }
        },
        getElementById(id) {
            return styleElements.get(id) || null;
        },
        createElement(tag) {
            return {
                tagName: tag.toUpperCase(),
                id: '',
                style: {},
                classList: {
                    classes: new Set(),
                    add(c) { this.classes.add(c); },
                    remove(c) { this.classes.delete(c); },
                    toggle(c) {
                        if (this.classes.has(c)) { this.classes.delete(c); return false; }
                        this.classes.add(c); return true;
                    },
                    contains(c) { return this.classes.has(c); }
                },
                setAttribute() {},
                getAttribute() {},
                addEventListener() {},
                querySelectorAll() { return []; },
                contains() { return false; },
                innerHTML: '',
                textContent: ''
            };
        },
        addEventListener() {},
        dispatchEvent(evt) { eventsDispatched.push(evt); }
    };

    const mockWindow = {
        document: mockDocument,
        localStorage: {
            getItem(key) { return storageMap.get(key) || null; },
            setItem(key, val) { storageMap.set(key, String(val)); },
            removeItem(key) { storageMap.delete(key); }
        },
        addEventListener() {},
        dispatchEvent(evt) { eventsDispatched.push(evt); },
        CustomEvent: class CustomEvent {
            constructor(type, init) {
                this.type = type;
                this.detail = init?.detail || {};
            }
        }
    };
    mockWindow.window = mockWindow;
    mockWindow.globalThis = mockWindow;

    const context = vm.createContext(mockWindow);
    vm.runInContext(code, context);

    // Verifikasi ekspor fungsi global
    assert.equal(typeof context.setChatFontSize, 'function', 'setChatFontSize harus tersedia di window');
    assert.equal(typeof context.getChatFontSize, 'function', 'getChatFontSize harus tersedia di window');
    assert.equal(typeof context.increaseChatFontSize, 'function', 'increaseChatFontSize harus tersedia di window');
    assert.equal(typeof context.decreaseChatFontSize, 'function', 'decreaseChatFontSize harus tersedia di window');
    assert.equal(typeof context.resetChatFontSize, 'function', 'resetChatFontSize harus tersedia di window');
    assert.equal(typeof context.ubahUkuranTextChat, 'function', 'alias ubahUkuranTextChat harus tersedia di window');
    assert.equal(typeof context.setChatTextSize, 'function', 'alias setChatTextSize harus tersedia di window');
    assert.ok(context.ChatFontSize && typeof context.ChatFontSize.set === 'function', 'Objek namespace ChatFontSize harus diekspor');

    // 1. Pengujian nilai default awal
    assert.equal(context.getChatFontSize(), 15, 'Ukuran default awal harus 15px');

    // 2. Pengujian setChatFontSize dengan angka
    const newSize = context.setChatFontSize(18);
    assert.equal(newSize, 18);
    assert.equal(context.getChatFontSize(), 18);
    assert.equal(mockDocument.documentElement.style.getPropertyValue('--chat-font-size'), '18px');
    assert.equal(mockWindow.localStorage.getItem('gemma_chat_font_size'), '18');

    // 3. Pengujian setChatFontSize dengan string satuan (contoh: '20px')
    context.setChatFontSize('20px');
    assert.equal(context.getChatFontSize(), 20);

    // 4. Pengujian batasan minimum & maksimum (clamping)
    context.setChatFontSize(5);
    assert.equal(context.getChatFontSize(), 11, 'Ukuran minimum harus di-clamp ke 11px');

    context.setChatFontSize(50);
    assert.equal(context.getChatFontSize(), 32, 'Ukuran maksimum harus di-clamp ke 32px');

    // 5. Pengujian kenaikan & penurunan relatif
    context.setChatFontSize(16);
    context.increaseChatFontSize(2);
    assert.equal(context.getChatFontSize(), 18, 'increaseChatFontSize(2) harus menaikkan 2px');

    context.decreaseChatFontSize(3);
    assert.equal(context.getChatFontSize(), 15, 'decreaseChatFontSize(3) harus menurunkan 3px');

    // 6. Pengujian preset
    context.setChatFontSize('xs');
    assert.equal(context.getChatFontSize(), 12, 'Preset xs harus 12px');

    context.setChatFontSize('2xl');
    assert.equal(context.getChatFontSize(), 22.5, 'Preset 2xl harus 22.5px');

    // 7. Pengujian reset
    context.resetChatFontSize();
    assert.equal(context.getChatFontSize(), 15, 'resetChatFontSize harus mengembalikan ke 15px');

    // 8. Pengujian injeksi stylesheet dinamis
    const dynamicStyle = mockDocument.getElementById('chat-font-size-dynamic-override');
    assert.ok(dynamicStyle, 'Style override dinamis harus dibuat');
    assert.ok(dynamicStyle.textContent.includes('--chat-font-size: 15px !important;'), 'Style override harus memuat ukuran font aktif');
    assert.ok(dynamicStyle.textContent.includes('.chat-bubble-user'), 'Style override harus menargetkan .chat-bubble-user');
    assert.ok(dynamicStyle.textContent.includes('.chat-bubble-ai'), 'Style override harus menargetkan .chat-bubble-ai');
    assert.ok(dynamicStyle.textContent.includes('.bubble'), 'Style override harus menargetkan .bubble');
});

test('ai-renderers.css mendefinisikan variabel dan aturan universal font size chat', () => {
    assert.ok(fs.existsSync(CSS_PATH), 'ai-renderers.css harus ada');
    const css = fs.readFileSync(CSS_PATH, 'utf-8');
    assert.ok(css.includes('--chat-font-size:'), 'ai-renderers.css harus mendefinisikan --chat-font-size');
    assert.ok(css.includes('--chat-font-size-code:'), 'ai-renderers.css harus mendefinisikan --chat-font-size-code');
    assert.ok(css.includes('.chat-bubble-user'), 'ai-renderers.css harus menargetkan .chat-bubble-user');
    assert.ok(css.includes('.chat-bubble-ai'), 'ai-renderers.css harus menargetkan .chat-bubble-ai');
});

test('seluruh halaman HTML workspace menautkan chat-font-size.js', () => {
    const rootDir = path.join(__dirname, '..');
    const htmlFiles = fs.readdirSync(rootDir).filter(f => f.endsWith('.html'));

    assert.ok(htmlFiles.length >= 15, 'Setidaknya 15 file HTML harus diperiksa');

    for (const file of htmlFiles) {
        const fullPath = path.join(rootDir, file);
        const html = fs.readFileSync(fullPath, 'utf-8');
        assert.ok(
            html.includes('chat-font-size.js'),
            `File ${file} harus memuat tautan skrip chat-font-size.js`
        );
    }
});

test('EduVisNativeApp menautkan chat-font-size.js pada AIResponseRendererView', () => {
    const swiftPath = path.join(__dirname, '..', 'EduVisNativeApp', 'AIResponseRendererView.swift');
    assert.ok(fs.existsSync(swiftPath), 'AIResponseRendererView.swift harus ada');
    const content = fs.readFileSync(swiftPath, 'utf-8');
    assert.ok(
        content.includes('chat-font-size.js'),
        'AIResponseRendererView.swift harus memuat chat-font-size.js dalam template web'
    );
});

test('chat-font-size.js, toolbar native, dan Inspector selalu menampilkan kontrol Aa dan menskalakan mode macos-native', () => {
    const js = fs.readFileSync(SCRIPT_PATH, 'utf-8');
    assert.match(js, /html\.macos-native\s+#messages\s+\.prose/);
    assert.match(js, /html\.macos-native\s+#messages\s+\.katex/);
    assert.match(js, /function\s+expandChatFontSizeWidget/);
    assert.doesNotMatch(js, /class="gfc-pill\s+\$\{isMinimized/);

    const swiftShell = fs.readFileSync(path.join(__dirname, '..', 'gemma_webview.swift'), 'utf-8');
    assert.match(swiftShell, /toolbarDecreaseFontSize/);
    assert.match(swiftShell, /toolbarIncreaseFontSize/);
    assert.match(swiftShell, /toolbarResetFontSize/);
    assert.match(swiftShell, /gemma_chat_font_size_minimized/);

    const splitJs = fs.readFileSync(path.join(__dirname, '..', 'nano_asset', 'assets', 'js', 'macos-split-view.js'), 'utf-8');
    assert.match(splitJs, /inspector-chat-font-slider/);
    assert.match(splitJs, /inspector-chat-font-dec/);
    assert.match(splitJs, /inspector-chat-font-inc/);
});
