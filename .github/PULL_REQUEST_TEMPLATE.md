<!-- Pull request template — fill this in on the main -> prod PR BEFORE
requesting Joe's approval in the GitHub `production` environment.
No evidence = no approval. -->

## What changed, and why

<!-- Plain-language summary. For a single-file site, include the line-count
delta. What could break, and what was NOT tested. -->

## Risk assessment

<!-- What could break in production, and what was deliberately not tested. -->

## Test results

- CI run on the exact SHA being promoted: <!-- link -->
- Staging smoke run: <!-- link -->
- Staging preview URL: https://main.sunup-finder.pages.dev
  - Exercised on the preview (mobile + desktop): <!-- which journeys -->
- QA agent verdict: <!-- link / summary -->
- Persona agent verdict (Joe / Senior / Beginner / Organizer): <!-- scores -->

## Screenshots

<!-- Before/after screenshots if the change is visual; otherwise state that
visual regression passed with no diff. -->

## Pre-deploy checklist

- [ ] Commit is on `main` with a green CI run and a green staging smoke run
- [ ] `prod` will be a fast-forward of `main` (no cherry-picks, no direct commits)
- [ ] Footer Privacy/Terms nav present in the deployed file
- [ ] `_headers` read: Permissions-Policy / CSP checked against features the page uses
- [ ] No secrets in the bundle; no new `http://` asset URLs; no broken element IDs
- [ ] Live-verification numbers updated to this build's actual counts

## Rollback plan

Rollback to deployment <!-- ID/SHA --> via the Roll back production workflow (or Cloudflare dashboard); expected restore < 1 minute; then `git revert` on `main`.
