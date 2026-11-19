const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const projectRoot = path.resolve(__dirname, '..');

test('local multilingual-e5-small model assets exist and are valid', () => {
    const modelDir = path.join(projectRoot, 'nano_asset/models/multilingual-e5-small');
    const requiredFiles = [
        'config.json',
        'tokenizer.json',
        'tokenizer_config.json',
        'special_tokens_map.json',
        'onnx/model_quantized.onnx'
    ];

    for (const file of requiredFiles) {
        const filePath = path.join(modelDir, file);
        assert.equal(fs.existsSync(filePath), true, `Expected ${file} to exist in multilingual-e5-small`);
        const stats = fs.statSync(filePath);
        assert.ok(stats.size > 0, `Expected ${file} to be non-empty`);
    }

    const config = JSON.parse(fs.readFileSync(path.join(modelDir, 'config.json'), 'utf8'));
    assert.equal(config.hidden_size, 384, 'Expected hidden_size to be 384 dimensions');
    assert.ok(config.max_position_embeddings >= 512, 'Expected at least 512 max position embeddings');
});

test('chat pages load multilingual-e5-small with asymmetric prefix and fallback', () => {
    const pages = ['utama.html', 'utamaV2.html', 'VS.html', 'claude.html'];

    for (const page of pages) {
        const source = fs.readFileSync(path.join(projectRoot, page), 'utf8');
        assert.match(
            source,
            /multilingual-e5-small/,
            `${page} should attempt loading multilingual-e5-small`
        );
        assert.match(
            source,
            /all-MiniLM-L6-v2/,
            `${page} should maintain fallback to all-MiniLM-L6-v2`
        );
        assert.match(
            source,
            /extractEmbedding\(query,\s*true\)/,
            `${page} should extract query embedding with isQuery=true`
        );
        assert.match(
            source,
            /extractEmbedding\(chunkTextData,\s*false\)/,
            `${page} should extract chunk embedding with isQuery=false`
        );
    }
});
