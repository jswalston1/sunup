# SunUp — sunuptee.com

Golf-course finder for Utah (and Florida): one static site, no build step,
no backend. Live at [sunuptee.com](https://sunuptee.com), hosted on
Cloudflare Pages project `sunup-finder`.

## How deploys work

```
push to main ──► CI gates ──► deploy to staging preview ──► smoke check
                     main.sunup-finder.pages.dev
                                          │
              merge main -> prod (fast-forward only)
                                          │
push to prod ──► fast-forward check + gates ──► JOE APPROVES ──► deploy prod
                                                        (GitHub environment)
                                          │
                                   sunuptee.com
```

- **Staging is automatic.** Every push to `main` deploys a preview to
  `https://main.sunup-finder.pages.dev`. Nothing touches production.
- **Production needs Joe.** Pushing to `prod` runs the gates, then GitHub
  pauses the deploy job as "Waiting" until Joe approves it in the
  `production` environment. The job cannot see the production Cloudflare
  token until approval passes. No approval, no deploy.
- **Promotion is a fast-forward merge, nothing else.** `prod` must be
  exactly the `main` tip — the workflow checks tip equality and fails the
  run on any direct commit to `prod`, cherry-pick, or non-fast-forward
  merge. To promote: `git checkout prod && git merge --ff-only main &&
  git push`.
- **GitHub Actions is the only deployer.** No dashboard ZIP uploads, no
  local deploys. The dashboard stays as the break-glass rollback path only.
- **Every deploy is stamped.** `scripts/build-version.mjs` writes
  `public/version.json` and injects a `<!-- build: <sha> ... -->` comment
  into `index.html` in the runner's copy (never committed). "What is live?"
  is answerable from any browser: `curl https://sunuptee.com/version.json`.
  The smoke check asserts the live SHA equals the deployed SHA.
- **Rollback is one click.** Actions -> Roll back production -> paste a
  production deployment ID (from `wrangler pages deployment list
  --project-name sunup-finder --environment production`), or dashboard ->
  Deployments -> ... -> Rollback. Then fix forward on `main`.

## Repo layout

```
sunup/
├── public/                  # the site — the ONLY directory deployed
│   ├── index.html           # 9.7 MB, First Light build (Nov 12, 2026)
│   ├── privacy.html
│   ├── terms.html
│   ├── robots.txt
│   ├── sitemap.xml
│   ├── _headers             # security + cache headers
│   └── version.json         # GENERATED in CI — never committed
├── scripts/
│   ├── build-version.mjs    # build stamp + version.json
│   ├── gates.sh             # shell-only CI gates (one place, called by all workflows)
│   ├── extract-inline-js.mjs# JS syntax gate (the site has no build step)
│   └── smoke.sh             # post-deploy smoke check (URL [SHA])
├── .github/workflows/
│   ├── ci.yml               # gates on PR + push to main/prod (no secrets, no deploy)
│   ├── deploy-staging.yml   # push to main -> preview deploy
│   ├── deploy-prod.yml      # push to prod -> gates -> Joe approves -> prod deploy
│   └── rollback.yml         # manual rollback to a production deployment ID
├── .github/PULL_REQUEST_TEMPLATE.md
├── .gitignore
├── .htmlvalidate.json
└── wrangler.toml            # project name + publish dir (does not deploy by itself)
```

## CI gates (run on every PR and push; a failure stops the deploy)

| Gate | What it catches |
|---|---|
| Gitleaks (full history) | Any secret ever committed |
| JS syntax check | Inline scripts that don't parse — this IS the build gate |
| No `http://` asset URLs | Insecure content on the live site |
| File-size guard | Any file over the 25 MiB Cloudflare Pages limit |
| Required files | Missing `_headers`, `robots.txt`, `sitemap.xml`, `privacy.html`, `terms.html` |
| HTML validation | Malformed markup (see tuning note below) |
| Link check (lychee) | Broken links in the static files (see exclusions below) |

**HTML validation tuning** (`.htmlvalidate.json`): `public/index.html` is a
generated 9.7 MB file whose hand-written shell deliberately uses inline
styles, self-closing void elements (`<meta/>`, `<input/>`), icon buttons
without accessible text, and JS-filled headings/images. The stock
`html-validate:recommended` set flags 39 such issues in the QA-approved
First Light build. Nine rules are disabled (html-validate v11 does not
accept per-file overrides in this config, so the disables apply to all
three pages — `privacy.html` / `terms.html` are small static pages and
the disabled rules are not meaningful for them either), each a deliberate
property of the build, not a defect:
`no-inline-style`, `void-style`, `text-content`, `aria-label-misuse`,
`empty-heading`, `element-required-attributes`, `doctype-style`
(lowercase doctype is valid HTML5), `long-title`, `no-trailing-whitespace`.
Structural rules (unclosed/mismatched tags, duplicate IDs, etc.) stay on
for all files. Verified locally Nov 13, 2026: the tuned config passes all
three files with zero errors. If the page is ever restructured, re-run the
validator with the full set before re-enabling rules one by one — never
weaken the config silently.

**Link-check exclusions** (`ci.yml`, both deploy workflows): documented,
not silent.
- `colonywestccpc.ezlinksgolf.com`, `palmbeachnational.com` — bot-walled,
  return 403 to any automated check (QA-044 / Nov 12 link-check allowlist).
- `country-club-of-coral-springs.book.teeitup.com` — dead link (QA-045).
  The fix awaits Joe's call; excluded so a known pre-existing issue cannot
  block the pipeline itself. Remove the exclusion when the link is fixed.

## Secrets and tokens

| Secret / variable | Where | Value |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` (staging token) | `staging` environment secret | Cloudflare token: Account -> Cloudflare Pages -> Edit, account-scoped, 90-day expiry |
| `CLOUDFLARE_API_TOKEN` (prod token, different value) | `production` environment secret | Same permission, separate token, 90-day expiry, different rotation date |
| `CLOUDFLARE_ACCOUNT_ID` | Environment variable (not a secret) | Account ID from the Cloudflare dashboard |

Rules: never use the Global API Key, never use the "Edit Cloudflare
Workers" template (broader than needed), never commit a token anywhere.
A Cloudflare token cannot be scoped to a single Pages project — only to an
account — so the real isolation is GitHub-side: the prod token lives only
in the `production` environment, readable only by jobs that declare it
after Joe's approval. Rotate both tokens every 90 days; if one is ever
suspected exposed, revoke and reissue immediately (tokens are shown once).

## Setup (run once, in order)

1. **Create the repo — PUBLIC.** Suggested name `sunup` (Joe's call).
   Default branch `main`. Do NOT add a README/license/gitignore from the
   GitHub UI — this scaffold supplies them; an auto-added file conflicts
   on first push. Public is what unlocks environments, required reviewers,
   branch protection, and native secret scanning free — see "Why public"
   below. If the repo must be private instead, see the fallback note.
2. **Push this scaffold** to `main`, then create the `prod` branch from
   `main`'s tip: `git checkout -b prod && git push -u origin prod`.
3. **Cloudflare: confirm the project.** Dashboard -> Workers & Pages ->
   `sunup-finder`: confirm `sunuptee.com` is attached. Note the current
   `production_branch` (Direct Upload projects have no dashboard control
   for it).
4. **Set the production branch to `prod`** (one-off API call — Direct
   Upload projects have no dashboard control for this):
   ```bash
   curl --request PATCH "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/sunup-finder" \
     -H "Authorization: Bearer <ONE-OFF-ADMIN-TOKEN>" -H "Content-Type: application/json" \
     --data '{"production_branch": "prod"}'
   ```
   Verify with `GET .../pages/projects/sunup-finder`. Existing
   deployments are kept — changing the branch deletes nothing.
5. **Create the two Cloudflare API tokens** (dashboard -> My Profile ->
   API Tokens -> Create Token -> Create Custom Token): permission
   **Account -> Cloudflare Pages -> Edit** and nothing else, account
   resources = only this account, 90-day expiry. Name them
   `github-actions-sunup-finder-staging` and
   `github-actions-sunup-finder-prod`. Copy each value once — Cloudflare
   shows it only once.
6. **Create the GitHub environments** `staging` and `production` (repo
   Settings -> Environments). Each gets its token as
   `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` as a variable.
   `production` additionally: required reviewer = Joe, deployment
   branches = `prod` only.
7. **Branch protection** (repo Settings -> Branches -> Add rule, for
   `main` and `prod`): require a pull request before merging, require
   status checks to pass (the `CI gates` job), require linear history,
   block force pushes and branch deletion, include administrators.
   (With one maintainer, "require PR review" is theatre; the valuable
   rules are status checks + linear history + no force-push/delete.)
8. **Code security** (repo Settings -> Code security): enable secret
   scanning + push protection. (Gitleaks in CI is the second scanner.)
9. **Test staging.** Push a trivial change to `main` (e.g. an HTML
   comment), watch the staging run, open
   `https://main.sunup-finder.pages.dev/version.json` and confirm the SHA
   matches the pushed commit.
10. **Test prod.** `git checkout prod && git merge --ff-only main &&
    git push`, approve the paused deploy job, verify
    `https://sunuptee.com/version.json` shows the same SHA and the smoke
    steps pass. Confirm the `prod-<date>-<sha>` tag appears.
11. **Test rollback.** Note the previous production deployment ID, run
    the Roll back production workflow, verify the old SHA is live, then
    roll forward again with the current SHA. This validates the runbook
    before it is needed.
12. **Retire manual ZIP uploads.** From the first Actions deploy onward,
    dashboard uploads stop — they bypass every gate. Keep dashboard
    access as the break-glass rollback path only.
13. **Monitoring (optional, $0).** UptimeRobot Free monitor for
    `https://sunuptee.com/` (keyword monitor — catches "200 but wrong
    content") + `https://sunuptee.com/version.json`, email alerts to Joe.
    Set a quarterly calendar reminder for token rotation.

## Why public (and the private fallback)

Native GitHub required-reviewer approval does **not** work on a private
repo on the Free plan — GitHub Pro ($4/mo) does not fix it either; the
docs say required reviewers are public-only on Free/Pro/Team, and private
needs Enterprise. A public repo unlocks environments, required reviewers,
branch protection, and native secret scanning free. The site's files are
already served to the whole internet, so publishing the repo exposes no
content that isn't already public — it must still never contain a secret
(Gitleaks + push protection guard that). If the repo must be private:
keep everything else identical, delete the `push: branches: [prod]`
trigger in `deploy-prod.yml` (keep `workflow_dispatch` with its `confirm`
input), and put both tokens in repository secrets
(`CLOUDFLARE_API_TOKEN_STAGING` / `CLOUDFLARE_API_TOKEN_PROD`). The
manual Run click in the Actions tab then IS the approval. Cost stays $0
(private repos get 2,000 free Actions minutes/month; this pipeline uses
~2–4 minutes per run).

## Cost

$0/month end-to-end. Cloudflare Pages Free (this site: ~7 files, largest
9.7 MB, a handful of deploys/month — nowhere near the 20,000-file,
25 MiB-per-file, or 500-build limits), GitHub Actions free for public
repos, Wrangler free, UptimeRobot Free optional. The only recurring cost
is the sunuptee.com domain renewal, already paid.

## Notes on this build

- First Light build (Nov 12, 2026) is the initial repo content, copied
  byte-for-byte from the verified deploy bundle
  (`sunup-deploy-2026-11-12-firstlight.zip`, index.html md5
  `2aba677fcb281b9d43c2b5bac1fe30fb`), with exactly ONE intentional diff:
  `public/_headers` gains a `/version.json` `Cache-Control: no-cache`
  rule so the smoke check's SHA assertion cannot read a stale cached
  copy. Everything else is identical, including the known stale Florida
  data (Delray shown verified, Boca Raton Municipal still listed) — that
  fix never survived into the Dev source and ships as-is until Joe
  decides otherwise.
- Live sunuptee.com still serves the Nov 2 Design C build until the first
  production deploy through this pipeline.
- Action pins (full commit SHAs, resolved Nov 13, 2026): checkout v6.0.3,
  setup-node v5, wrangler-action v4.1.3, gitleaks-action v2,
  lychee-action v2. Re-check for newer majors before changing them, and
  update the SHA + the version comment together.
- Design sources: `research_notes/cloudflare-api-deploy-pipeline-20261113-1633/report.md`
  (API/security/redundancy/cost research, Nov 13, 2026) and the Nov 12
  pipeline drafts (workflows, gates, PR template), simplified to the
  recommended shape: one job for staging, two jobs for prod, shared
  `scripts/gates.sh`, build stamp + smoke scripts extracted from the
  drafts' inline copies.

Staging test: first pipeline deploy check, Nov 13, 2026.
