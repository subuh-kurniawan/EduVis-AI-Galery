const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const projectRoot = path.resolve(__dirname, '..');
const sandboxModulePath = path.join(projectRoot, 'nano_asset/assets/js/artifact-sandbox.js');

test('artifact-sandbox.js exports core API and helper methods', () => {
    assert.equal(fs.existsSync(sandboxModulePath), true, 'artifact-sandbox.js must exist');
    const Sandbox = require(sandboxModulePath);

    assert.equal(typeof Sandbox.open, 'function');
    assert.equal(typeof Sandbox.close, 'function');
    assert.equal(typeof Sandbox.setTab, 'function');
    assert.equal(typeof Sandbox.setViewport, 'function');
    assert.equal(typeof Sandbox.reload, 'function');
    assert.equal(typeof Sandbox.download, 'function');
    assert.equal(typeof Sandbox.toggleMaximize, 'function');
    assert.equal(typeof Sandbox.fixWithAI, 'function');
    assert.equal(typeof Sandbox.clearConsole, 'function');
    assert.equal(typeof Sandbox.wireGlobalHooks, 'function');
    assert.equal(typeof Sandbox.prepareHarness, 'function');
});

test('prepareHarness wraps HTML snippets and injects console & error bridge', () => {
    const Sandbox = require(sandboxModulePath);
    const snippet = '<div class="card">Hello World</div>';
    const harnessed = Sandbox.prepareHarness(snippet);

    assert.match(harnessed, /<!DOCTYPE html>/i);
    assert.match(harnessed, /GEMMA_ARTIFACT_LOG/);
    assert.match(harnessed, /GEMMA_ARTIFACT_ERROR/);
    assert.match(harnessed, /window\.onerror\s*=/);
    assert.match(harnessed, /unhandledrejection/);
    assert.match(harnessed, /Hello World/);
});

test('prepareHarness detects Tailwind CSS classes and injects local tailwind script', () => {
    const Sandbox = require(sandboxModulePath);
    const codeWithTailwind = '<div class="flex items-center justify-between p-4 bg-blue-500 rounded-xl text-white">Header</div>';
    const harnessed = Sandbox.prepareHarness(codeWithTailwind);

    assert.match(harnessed, /<script src="nano_asset\/assets\/js\/tailwindcss\.js"><\/script>/);
});

test('wireGlobalHooks establishes seamless backward compatibility adapters', () => {
    const Sandbox = require(sandboxModulePath);
    const mockGlobal = {};

    Sandbox.wireGlobalHooks.call(Sandbox);
    // When called, globalThis / window has the adapters
    assert.equal(typeof global.openArtifactDock, 'function');
    assert.equal(typeof global.openPreviewModal, 'function');
    assert.equal(typeof global.openSplitEditor, 'function');
    assert.equal(typeof global.closeArtifactDock, 'function');
    assert.equal(typeof global.downloadCurrentArtifact, 'function');
});

test('workspace pages include artifact-sandbox.js script', () => {
    const pages = ['claude.html', 'VS.html', 'utama.html', 'utamaV2.html'];

    for (const page of pages) {
        const filePath = path.join(projectRoot, page);
        const content = fs.readFileSync(filePath, 'utf8');
        assert.match(
            content,
            /artifact-sandbox\.js/,
            `${page} must include artifact-sandbox.js`
        );
    }
});
