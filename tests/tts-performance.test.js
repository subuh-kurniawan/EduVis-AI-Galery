const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const server = fs.readFileSync(path.join(root, 'tts_server.py'), 'utf8');
const launcher = fs.readFileSync(path.join(root, 'gemma_chat_gui.py'), 'utf8');

test('local VITS startup serves health while the model warms and skips unused RVC warmup', () => {
    const synthesizer = server.slice(
        server.indexOf('def get_synthesizer():'),
        server.indexOf('# Global RVC Voice Converter')
    );
    const main = server.slice(server.indexOf('def main():'), server.indexOf('if __name__ == "__main__":'));

    assert.doesNotMatch(synthesizer, /get_rvc_converter\(/);
    assert.match(synthesizer, /SYNTHESIZER\s*=\s*Synthesizer\(/);
    assert.ok(main.indexOf('ReusableHTTPServer(server_address') < main.indexOf('threading.Thread('));
    assert.ok(main.indexOf('threading.Thread(') < main.indexOf('httpd.serve_forever()'));
    assert.match(server, /"synthesizer_loading": SYNTHESIZER_LOADING/);
    assert.match(server, /if SYNTHESIZER_LOADING:[\s\S]*?self\.send_response\(503\)/);
    assert.match(server, /with SYNTHESIS_LOCK:/);
});

test('launcher reuses an in-progress local TTS worker instead of starting duplicates', () => {
    const ensureServer = launcher.slice(
        launcher.indexOf('def ensure_tts_server():'),
        launcher.indexOf('def stop_tts_server():')
    );
    assert.match(ensureServer, /with TTS_SERVER_LOCK:/);
    assert.match(ensureServer, /TTS_SERVER_PROCESS\.poll\(\)\s+is None/);
    assert.match(ensureServer, /TTS_SERVER_PROCESS\s*=\s*subprocess\.Popen/);
});

test('local app pages and scripts are served without stale browser caching', () => {
    const staticServer = server.slice(
        server.indexOf('# Serve static files from ROOT_DIR'),
        server.indexOf('self.send_response(404)', server.indexOf('# Serve static files from ROOT_DIR'))
    );
    assert.match(staticServer, /if ext in \{".html", "\.js"\}:[\s\S]*?send_header\("Cache-Control", "no-store"\)/);
});
