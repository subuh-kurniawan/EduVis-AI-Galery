const fs = require('node:fs');
const path = require('node:path');
const postcss = require('postcss');
const tailwindcss = require('tailwindcss');

const projectRoot = path.resolve(__dirname, '..');
const configPath = path.join(projectRoot, 'tailwind.config.js');
const stylesheetPath = path.join(projectRoot, 'nano_asset/assets/css/aku.css');
const startMarker = '/* utamaV2 Tailwind utilities: start */';
const endMarker = '/* utamaV2 Tailwind utilities: end */';

async function build() {
  const stylesheet = fs.readFileSync(stylesheetPath, 'utf8');
  const start = stylesheet.indexOf(startMarker);
  const end = stylesheet.indexOf(endMarker);
  if ((start === -1) !== (end === -1) || (start !== -1 && end < start)) {
    throw new Error('Penanda utilitas Tailwind V2 di aku.css tidak valid.');
  }

  const baseStylesheet = start === -1
    ? stylesheet.trimEnd()
    : stylesheet.slice(0, start).trimEnd() + stylesheet.slice(end + endMarker.length).trimStart();
  const result = await postcss([tailwindcss(configPath)]).process('@tailwind utilities;', {
    from: path.join(projectRoot, 'utamaV2.html')
  });

  fs.writeFileSync(
    stylesheetPath,
    `${baseStylesheet}\n${startMarker}\n${result.css.trim()}\n${endMarker}\n`
  );
}

build().catch(error => {
  console.error('Gagal memperbarui utilitas Tailwind di aku.css:', error);
  process.exitCode = 1;
});
