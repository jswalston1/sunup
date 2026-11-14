#!/usr/bin/env bash
# smoke.sh — post-deploy smoke check for SunUp (sunup-finder).
# Usage: ./scripts/smoke.sh <URL> [SHA]
#        ./scripts/smoke.sh --liveness <URL>
#   URL  — base URL to check (e.g. https://main.sunup-finder.pages.dev)
#   SHA  — full commit SHA the deploy should serve; when given, the build
#          stamp and version.json must match it exactly.
#   --liveness — after a rollback: assert liveness + headers + supporting
#          pages only. version.json is NOT required: pre-pipeline builds
#          never had one, so requiring it calls a good rollback a failure.
#          If version.json happens to exist it is printed, never asserted.
# Exits non-zero on the first failed check. No secrets, no deploys.
set -euo pipefail

LIVENESS=0
if [ "${1:-}" = "--liveness" ]; then
  LIVENESS=1
  shift
fi

URL="${1:?usage: smoke.sh [--liveness] URL [SHA]}"
SHA="${2:-}"

echo "Checking $URL"

# 1. Page answers 200.
curl -fsS -o /dev/null -w "HTTP %{http_code}\n" "$URL"

# 2. / and /index.html serve Cache-Control: no-cache (per _headers).
curl -fsSI "$URL" | grep -qi "cache-control: no-cache" || { echo "FAIL: no no-cache on $URL/"; exit 1; }
curl -fsSI "$URL/index.html" | grep -qi "cache-control: no-cache" || { echo "FAIL: no no-cache on $URL/index.html"; exit 1; }

# 3. Permissions-Policy still allows geolocation in-page (the finder uses it).
curl -fsSI "$URL" | grep -qi "permissions-policy: .*geolocation=(self)" || { echo "FAIL: geolocation not (self) on $URL"; exit 1; }

# 4. Supporting pages answer 200. version.json is required in strict mode
#    only — pre-pipeline builds never had one.
PAGES="privacy.html terms.html robots.txt sitemap.xml"
if [ "$LIVENESS" -eq 0 ]; then
  PAGES="$PAGES version.json"
fi
for p in $PAGES; do
  curl -fsS -o /dev/null "$URL/$p" || { echo "FAIL: $URL/$p not 200"; exit 1; }
done

# 5. version.json: strict mode parses it and prints the live commit.
#    Liveness mode prints it only if it exists; absence is not a failure.
if [ "$LIVENESS" -eq 1 ]; then
  if LIVE_SHA="$(curl -fsS "$URL/version.json" 2>/dev/null | node -e "let d=''; process.stdin.on('data', (c) => { d += c; }).on('end', () => { try { console.log(JSON.parse(d).commit); } catch (e) { process.exit(1); } });" 2>/dev/null)"; then
    echo "live commit: $LIVE_SHA"
  else
    echo "live commit: unknown (no version.json — pre-pipeline build; liveness-only check)"
  fi
else
  LIVE_SHA="$(curl -fsS "$URL/version.json" | node -e "let d=''; process.stdin.on('data', (c) => { d += c; }).on('end', () => { try { console.log(JSON.parse(d).commit); } catch (e) { console.error('FAIL: version.json is not valid JSON'); process.exit(1); } });")"
  echo "live commit: $LIVE_SHA"
fi

# 6. When an expected SHA is given, the deployed bytes must be exactly it.
# Download to a file first: piping curl straight into `grep -q` lets grep
# exit on first match, which SIGPIPEs curl and (under pipefail) fails the
# check even when the stamp IS present.
if [ -n "$SHA" ]; then
  PAGE="$(mktemp)"
  curl -fsS "$URL" -o "$PAGE"
  grep -Fq "<!-- build: ${SHA:0:7}" "$PAGE" || { echo "FAIL: build stamp missing/wrong on $URL"; rm -f "$PAGE"; exit 1; }
  rm -f "$PAGE"
  [ "$LIVE_SHA" = "$SHA" ] || { echo "FAIL: version.json commit $LIVE_SHA != $SHA"; exit 1; }
fi

echo "OK: smoke passed for $URL"
