#!/usr/bin/env bash
# gates.sh — shell-only CI gates for SunUp (sunup-finder).
# Called by ci.yml, deploy-staging.yml and deploy-prod.yml so the gates live
# in exactly one place. No secrets, no deploys. Gitleaks and lychee run as
# GitHub Actions steps in the workflows (they need their actions to run).
# Run from the repo root. Exits non-zero on the first failed gate.
set -euo pipefail

echo "== JS syntax (inline scripts) =="
node scripts/extract-inline-js.mjs

echo "== No http:// asset URLs =="
if grep -nE 'src="http://' public/index.html; then
  echo "FAIL: http:// URL in a src attribute"
  exit 1
fi
if grep -nE 'href="http://[^"]+\.(css|js|png|jpe?g|gif|svg|webp|woff2?|ico)' public/index.html; then
  echo "FAIL: http:// asset URL in an href"
  exit 1
fi
echo "OK: no http:// asset URLs"

echo "== File-size guard (25 MiB per file, the Cloudflare Pages limit) =="
if find public -type f -size +25M -print | grep -q .; then
  echo "FAIL: a file is over 25 MiB"
  exit 1
fi
echo "index.html: $(stat -c%s public/index.html) bytes"

echo "== Required files =="
for f in public/_headers public/robots.txt public/sitemap.xml public/privacy.html public/terms.html; do
  test -f "$f" || { echo "FAIL: $f missing"; exit 1; }
done
echo "OK: _headers, robots.txt, sitemap.xml, privacy.html, terms.html present"

echo "== HTML validation =="
npx --yes html-validate public/index.html public/privacy.html public/terms.html

echo "OK: all shell gates passed"
