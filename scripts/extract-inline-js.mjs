// Build gate: the site has no build step, so "does the JS parse" IS the build gate.

// Purpose: the site has no build step, so "does the JS parse" IS the build
// gate. This script extracts every inline <script> block (no src attribute)
// from public/index.html and syntax-checks it with node:vm (compiles
// without executing). Exits non-zero on the first syntax error, or if no
// inline script blocks are found at all (that would mean the file changed
// shape under us).
// Usage in CI: node scripts/extract-inline-js.mjs

import fs from 'node:fs';
import vm from 'node:vm';

const FILE = 'public/index.html';

const html = fs.readFileSync(FILE, 'utf8');
const blocks = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)]
  .map((m) => m[1]);

if (blocks.length === 0) {
  console.error(`FAIL: no inline <script> blocks found in ${FILE}`);
  process.exit(1);
}

console.log(`inline script blocks: ${blocks.length}`);
let totalBytes = 0;
for (let i = 0; i < blocks.length; i++) {
  const code = blocks[i];
  totalBytes += Buffer.byteLength(code, 'utf8');
  try {
    new vm.Script(code, { filename: `${FILE}#inline-script-${i}` });
  } catch (err) {
    console.error(`FAIL: inline script block ${i} does not parse: ${err.message}`);
    process.exit(1);
  }
  console.log(`  block ${i}: ${Buffer.byteLength(code, 'utf8')} bytes — parses OK`);
}
console.log(`OK: all ${blocks.length} inline script blocks parse (${totalBytes} bytes total)`);
