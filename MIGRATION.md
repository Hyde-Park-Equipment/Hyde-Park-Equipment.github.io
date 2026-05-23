# Moving HPE to Claude Code — one-time setup

A short checklist for the switch. The recurring project knowledge lives in
`CLAUDE.md`; this file is just the migration itself.

## 1. Get the repo locally
You're already deploying from a GitHub repo (`Hyde-Park-Equipment` org, Pages from
`main`/`(root)`). Clone it to your machine if you haven't:

```
git clone https://github.com/Hyde-Park-Equipment/<repo>.git
cd <repo>
```

The `index.html` Claude Code edits is the one in this repo — the same file Pages
serves. No more uploading/downloading copies.

## 2. Drop in these two files at the repo root
- `CLAUDE.md` — Claude Code reads this automatically every session. It's the
  replacement for pasting your handoff each time.
- `smoke.sh` — make it executable: `chmod +x smoke.sh`

Then verify it runs green against the current file:
```
./smoke.sh
```
You should see JS OK / Duplicate-IDs = 6 / version consistent / ALL CHECKS PASSED.

## 3. Sanity-check local deps
`smoke.sh` needs `node` and `python3` on your PATH. Confirm:
```
node --version && python3 --version
```
(Optional, only if you want CSS preview screenshots like the ones from chat:
`pip install playwright && python3 -m playwright install chromium`.)

## 4. Working rhythm in Claude Code
- Ask Claude to make a change → it edits `index.html` in place.
- Claude (or you) runs `./smoke.sh` — green before committing.
- Review the diff (`git diff`), then commit + push. Pages redeploys.
- **For anything experimental, branch first** so `main` stays deployable:
  ```
  git checkout -b polish-experiment
  # ...work, commit...
  git checkout main        # discard by just not merging
  ```
  This is your new "revert if I don't like it" — cleaner and per-change.

## 5. What does NOT carry over
- **Chat memory and past-conversation search don't exist in Claude Code.** That's
  the whole reason for `CLAUDE.md` — it reconstructs the continuity. If you teach
  Claude Code something new about the project, ask it to add the fact to `CLAUDE.md`
  so it persists.
- **The Google Drive / OAuth backend** isn't available locally. Anything that needs
  the live app talking to Drive still has to be tested in the deployed/browser app.

## Current state at handoff
- Version: **v3.13.13** (May 23 2026), ~36,700 lines.
- Smoke test: green (JS OK, 6 dup-IDs, versions aligned).
- No known functional bugs open. Recent work was UI polish (v3.13.12 sidebar
  labels + typography; v3.13.13 Used-dashboard color hierarchy).
- Next candidate if you keep polishing: frozen TAG column in the Full List table
  (see PARKED in CLAUDE.md).
