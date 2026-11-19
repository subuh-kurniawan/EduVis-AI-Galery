const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const projectRoot = path.resolve(__dirname, '..');
const swiftShellPath = path.join(projectRoot, 'gemma_webview.swift');

test('Swift native shell implements all 4 major architecture optimizations', () => {
    const swiftSource = fs.readFileSync(swiftShellPath, 'utf8');

    // 1. WebKit & Speech Optimizations: WeakScriptMessageHandler, isInspectable, on-device speech
    assert.match(swiftSource, /class\s+WeakScriptMessageHandler:\s+NSObject,\s+WKScriptMessageHandler/);
    assert.match(swiftSource, /weak\s+var\s+delegate:\s+WKScriptMessageHandler\?/);
    assert.match(swiftSource, /isInspectable\s*=\s*true/);
    assert.match(swiftSource, /requiresOnDeviceRecognition\s*=\s*true/);

    // 2. Multi-WebView workspace caching: instant switching without state reset
    assert.match(swiftSource, /workspaceWebViews:\s*\[String:\s*WKWebView\]/);
    assert.match(swiftSource, /func\s+getOrCreateWebView\(for appView:\s*AppView\)\s*->\s*WKWebView/);
    assert.match(swiftSource, /wv\.isHidden\s*=\s*\(path\s*!=\s*appView\.path\)/);

    // 3. Apple Silicon Unified Memory Guard
    assert.match(swiftSource, /ProcessInfo\.processInfo\.physicalMemory/);
    assert.match(swiftSource, /func\s+getPhysicalMemoryGB\(\)\s*->\s*Double/);
    assert.match(swiftSource, /func\s+checkModelMemoryRequirement\(modelName:\s*String\)\s*->\s*String\?/);
    assert.match(swiftSource, /27b|31b|70b/);

    // 4. macOS Native Menu Bar Status Item
    assert.match(swiftSource, /NSStatusBar\.system\.statusItem/);
    assert.match(swiftSource, /func\s+setupStatusItem\(\)/);
    assert.match(swiftSource, /func\s+updateStatusItemModel\(\)/);
    assert.match(swiftSource, /menuOpenWorkspace/);
    assert.match(swiftSource, /menuShowLauncher/);
    assert.match(swiftSource, /menuOpenBrowser/);
});

test('Swift native shell supports Quick Ask Spotlight, System Services, Dock file drop, window reopen, and memory refresh', () => {
    const swiftSource = fs.readFileSync(swiftShellPath, 'utf8');
    const backendSource = fs.readFileSync(path.join(projectRoot, 'gemma_chat_gui.py'), 'utf8');

    // 1. Floating Quick Ask Spotlight panel + System Services
    assert.match(swiftSource, /func\s+openQuickAskPanel\(\)/);
    assert.match(swiftSource, /func\s+makeQuickAskPanel\(\)/);
    assert.match(swiftSource, /func\s+submitQuickAskPrompt\(\)/);
    assert.match(swiftSource, /func\s+forwardQuickAskToWorkspace\(\)/);
    assert.match(swiftSource, /func\s+handleSystemServicePrompt\(/);
    assert.match(swiftSource, /NSApp\.servicesProvider\s*=\s*self/);

    // 2. Standard macOS Window Lifecycle (⌘W hide, Dock click reopen) & Dock File Drop
    assert.match(swiftSource, /func\s+applicationShouldHandleReopen\(/);
    assert.match(swiftSource, /func\s+windowShouldClose\(_\s+sender:\s*NSWindow\)\s*->\s*Bool/);
    assert.match(swiftSource, /sender\.orderOut\(nil\)/);
    assert.match(swiftSource, /func\s+application\(_\s+sender:\s*NSApplication,\s*open\s+urls:\s*\[URL\]\)/);

    // 3. Live Memory Monitor & Memory Refresh / Purge
    assert.match(swiftSource, /func\s+refreshMemoryStats\(\)/);
    assert.match(swiftSource, /func\s+menuRefreshModelMemory\(\)/);
    assert.match(swiftSource, /func\s+purgeInactiveWebViews\(\)/);
    assert.match(backendSource, /\/api\/system\/memory/);
    assert.match(backendSource, /\/api\/system\/restart-model-server/);
    assert.match(backendSource, /def\s+get_memory_stats\(self\):/);
    assert.match(backendSource, /def\s+restart_server\(self\):/);
});
