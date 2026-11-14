import fs from 'node:fs';

// build-version.mjs — CI build stamp for SunUp (sunup-finder).
// Writes public/version.json and injects an HTML comment stamp into
// public/index.html (before </head>) for the exact checked-out commit.
// The stamp is injected into the runner's copy only — it is never committed.
// Refuses to run twice on the same copy (double-stamp guard).
// Env: GITHUB_SHA (required), GITHUB_REF_NAME, ENVIRONMENT (staging|production|local).

const sha = process.env.GITHUB_SHA;
const branch = process.env.GITHUB_REF_NAME || 'local';
const environment = process.env.ENVIRONMENT || 'local';

if (!sha) {
  console.error('FAIL: GITHUB_SHA is not set');
  process.exit(1);
}

const short = sha.slice(0, 7);
const now = new Date().toISOString();
const stamp = `<!-- build: ${short} ${now} branch:${branch} env:${environment} -->`;

const p = 'public/index.html';
let html = fs.readFileSync(p, 'utf8');
if (!html.includes('</head>')) {
  console.error('FAIL: no </head> in public/index.html');
  process.exit(1);
}
if (html.includes('<!-- build: ')) {
  console.error('FAIL: index.html already contains a build stamp — refusing to double-stamp');
  process.exit(1);
}
html = html.replace('</head>', stamp + '\n</head>');
fs.writeFileSync(p, html);

fs.writeFileSync(
  'public/version.json',
  JSON.stringify(
    {
      commit: sha,
      short,
      branch,
      environment,
      built_at: now,
      deployed_at: now,
      project: 'sunup-finder',
    },
    null,
    2,
  ) + '\n',
);

console.log('stamp:', stamp);
