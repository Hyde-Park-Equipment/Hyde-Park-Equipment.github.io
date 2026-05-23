# CLAUDE.md — HPE Sales Platform

> Project memory for Claude Code. Read automatically every session. Keep it
> current — when something here goes stale, fix it in the same change that made
> it stale. This file replaces the old "re-upload + paste handoff" ritual.

## What this is
Single-file internal sales platform for **Hyde Park Equipment (HPE)**.
- **One file:** `index.html` (~36,700 lines / ~2.5 MB). All HTML, CSS, JS inline.
- **Deployed to:** GitHub Pages under the `Hyde-Park-Equipment` org.
- **Backend:** Google Drive via OAuth, restricted to `@hydeparkequipment.ca`.
- **Developer & primary user:** John Williams.
- **Current version:** v3.13.27 (bump this line whenever you ship — see below).

This is a real production tool reps use daily. Default to caution: small,
reviewable diffs; never break `main`.

---

## ⚙️ WORKFLOW (Claude Code)

1. Edit `index.html` in place.
2. **Run `./smoke.sh`** — must be all-green before committing.
3. Show John the diff. For anything experimental, **work on a branch**, not `main`.
4. Commit with a short message; John pushes (or you push if asked).
5. GitHub's "pages build and deployment" workflow publishes automatically.

There is **no** "upload / outputs dir" step anymore — the file on disk is the
source of truth. `git` is the safety net: `git diff` to review, `git checkout .`
or `git stash` to bail out, branch-per-experiment for risky work.

### Local deps
`./smoke.sh` needs `node` + `python3`. Optional UI previews use `playwright`
(`pip install playwright && python3 -m playwright install chromium`) — handy for
eyeballing CSS changes by rendering a small standalone snippet, but not required.

### What can/can't be tested locally
- **Can:** JS syntax, dup-ID scan, version consistency (all via `./smoke.sh`),
  static CSS/layout previews via playwright screenshots.
- **Can't locally:** anything that needs the live Google Drive backend or OAuth —
  that only works in the deployed/browser app. Test data-touching changes there.

---

## 🔢 VERSION BUMP — DO THIS ON EVERY SHIPPED CHANGE
John flagged forgetting this as a recurring miss. `./smoke.sh` now checks the
three touchpoints agree, so a drift fails the smoke test. Update all three:

1. **`<title>`** (~line 6) + the `<!-- build:... -->` comment after it.
2. **Topbar pill** — the `...flex-shrink:0;cursor:pointer">vX.Y.Z</div>` (~line 2726).
3. **`HPE.config.version`** + **`.build`** (~line 4413).

**Semver:** patch = fix/polish (almost everything), minor = feature, major = big
change. **Polish defaults to a patch bump.** Never reuse a version across two
change batches.

### Changelog (single source of truth — keep it fed)
Right after `HPE.config` (~line 4420) is a `const CHANGELOG = [...]` array. On
every version bump, add **ONE** entry at the **TOP**:
`{ v: '3.13.x', date: '…', note: '…' }`. Notes are **rep-facing** — "what you'd
notice," plain language, not implementation detail. The version pill renders this.

---

## 🎨 DESIGN SYSTEM (theme via CSS variables — don't hardcode hex)
Tokens live in the global `:root` (~line 30). **Gotcha:** there are MULTIPLE
`:root` blocks — a global one plus per-section overrides (e.g. `#section-shortline`
~line 962). Token names are consistent; when editing section-scoped styles, check
whether that section redefines a token before assuming the global value.

Core tokens: `--black/-2/-3` (dark chrome) · `--bg #f5f5f5` · `--card #fff` ·
`--border` / `--border-strong` · `--text/-2/-3` · `--gray-50…900` ramp ·
`--orange #e85d04` (PRIMARY BRAND) · `--green` `--blue` `--amber` `--red`
`--purple` (+ `-light`/`-bg` variants) · `--topbar-h 54px` · `--sidenav-w 240px` ·
`--radius 8px` / `--radius-lg 14px` · `--shadow` / `--shadow-md`.

**Fonts:** `'DM Sans'` for UI, `'DM Mono'` for versions/codes/numeric data.

**Brand feel:** clean, light, dark topbar with orange accent. White cards, 1px
gray borders, `--radius-lg`. **Orange is for emphasis/primary actions/section
anchors only — not a fill everywhere.** (See color-discipline notes below.)

### Color discipline (established in v3.13.12–13 polish, keep it consistent)
- **Orange = "this is a section header or the primary action."** Section labels,
  Quick Quote, primary buttons. Don't use it decoratively.
- **Status colors mean status:** red = problem/missing, the green→amber→red
  age-bucket ramp = freshness. Don't reuse these decoratively or you dilute the signal.
- **Categorical cards (locations, totals) are neutral** so status colors pop.
- **Home readout tiles are SEMANTIC** (orange=sales, green=profit, blue=pipeline,
  purple=needs-attention). Used dashboard `.dash-card` colors are a separate
  *categorical/status* system — deliberately NOT unified with Home. Don't force-merge.
- Subsection labels use `.dash-subhead` (muted gray), not orange.

### Reusable patterns (match these, don't reinvent)
- `.modal-overlay` + inner card — bug-report modal, changelog panel
  (`HPE.ui.showChangelog`, ~line 5500). Copy this for any new modal.
- `.admin-only` (inline) / `.admin-only-block` (block) — hide unless
  `body.admin-mode`. Use these instead of JS show/hide for admin-gated UI.
- `.nav-section.admin-only` — admin divider in the sidebar nav.
- `.sidenav-section-label` — sidebar group labels (workspace name + "My Sales Platform").
- `.skel-line` + `@keyframes skelShimmer` (~line 240) — shimmer skeleton loader;
  respects `prefers-reduced-motion`. Reuse for loading states (don't add spinners).
- `.age-dot` (.ok/.warn/.red/.gray) — status dots.
- `.dash-subhead` — muted subsection labels on the Used dashboard.
- Toast: `HPE.ui.toast(msg, ms)`.
- Topbar data-status pills: `HPE.ui.dataStatus` (Commissions/Inventory/Used/Modules).

---

## 🗺 ARCHITECTURE QUICK-REFERENCE
- **IIFEs / namespaces:**
  - Hub (Home) = `HPE.sectionImpl.hub` — dashboard cockpit, communications,
    customers, My Quotes.
  - Used = `window.U` — dynamic `render()` dispatch (not per-page divs).
  - Shortline = `window.S` = `HPE.sectionImpl.shortline` — also owns parts
    inventory + commissions. Inventory accessors on `window.S` via `invBridge`;
    commissions/JSON-config helpers via `slHelper`.
  - Kubota = `HPE.sectionImpl.kubota` — 660 Stock Checker.
- **Router:** `HPE.router` — `parse`/`serialize`/`go` (validates)/`apply` (the
  chokepoint every nav flows through; has a catch-all that redirects unknown
  slugs to the section dashboard + toast)/`handleHashChange`. Hash routes like
  `#/`, `#/used`, `#/kubota/660-checker`. (A label↔slug naming mismatch exists but
  is harmless thanks to the catch-all.)
- **UI helpers:** `HPE.ui` — `toast`, `showChangelog`, `_copyBuild`,
  `renderSidebar`, `dataStatus`, modal patterns, `setNavBadge`.
- **Sections config:** `const sections = {...}` (~line 4490). Each has
  `nav` (module-specific, top) + `bottomNav` (personal "My …" links, built by
  `buildMyBottomNav`). `renderSidebar` (~line 5290) emits a workspace label above
  `nav` and a "My Sales Platform" label above `bottomNav`.
- **Pages** are `.page` divs toggled by `.active` (display:block). Section
  containers: `#section-{hub|used|shortline|kubota}`.
- **Permissions:** admin = bootstrap-admin email OR salesperson `is_admin`.
  `body.admin-mode` drives admin-only UI. Per-person flags:
  `can_view_all_commissions`, `can_view_team`. Per-rep: `commission_codes`.
- **Commissions cache:** IndexedDB `hpe_comm_cache` / store `parsed`, keyed by
  `fileId|modifiedTime`. Per-browser, fully fail-safe (any IDB error falls back to
  live download+parse — can only be faster, never broken). Self-maintaining: a new
  year file changes its modifiedTime → only that year re-parses. `⏱` timing logs in
  `loadCommissionsFiles` are intentional/harmless.

---

## ⚠️ COMMON PITFALLS (read before writing guards/checks)

- **`HPE` is NOT on `window`.** It's declared as `const HPE = (function(){...})()`
  at script top level (~line 4455). Top-level `const`/`let` in classic scripts
  do NOT become `window` properties — only `var` does. So `window.HPE` is always
  `undefined`. **Never** write `if(window.HPE && ...)` — the guard short-circuits
  and your code silently no-ops. Guard with `HPE.ui && ...` /
  `HPE.sectionImpl && ...` instead (see `loadCommissionsFiles` for the canonical
  pattern). If you need an "is HPE in scope at all" check (rare, early-boot only),
  use `typeof HPE !== 'undefined'`. This bug cost v3.13.20 → v3.13.23 to fully
  clean up; the worst casualty was the changelog modal silently showing "No
  changelog entries yet" because the same `window.HPE` guard was in `showChangelog`.

## 👥 SALESPEOPLE (STAFF list) — all @hydeparkequipment.ca
John Williams (johnwilliams@), Larry Annaert (larry@), Bryan Macpherson (bryan@),
Kris Zantingh (zinger@), Nick Stub (nick@), Tyler Talbot (tyler@),
Brian Apfelbeck (bapfelbeck@), Adam Mason (adam@).
> Note: a Shortline admin entry historically had the typo "Machperson" — correct
> to "Macpherson" if you encounter it.

---

## 📦 DEPLOYMENT
- GitHub Pages, source = "Deploy from a branch" / `main` / `(root)`.
  **Confirmed correct — do NOT suggest changing it.**
- Published by GitHub's built-in "pages build and deployment" workflow.
- **If a deploy fails at the `git checkout` step** with `could not read Username …
  terminal prompts disabled` — that's a **transient auth blip, NOT a code or
  file-size issue.** First action: **re-run the failed job** from the Actions tab
  (usually clears it). If it persists: Settings → Actions → General → Workflow
  permissions = "Read and write".

---

## ✅ CLOSED / VERIFIED — DO NOT REOPEN
- Dashboard cockpit `$0`-on-first-land bug (fixed v3.13.7 by watching data, not
  render timing — don't revisit render-timing approaches).
- Router blank page on unknown hash routes (catch-all redirect, v3.13.8).
- Commissions load speed: ~16.5s → ~0.67s warm (parallel downloads v3.13.10 +
  IndexedDB parse cache v3.13.11). Parse was the bottleneck (CPU, not network).
- 660 Kubota inventory browser — done and working perfectly. Drop any 660
  virtualization/performance items unless John raises a new issue.
- 2023 commissions blank-invoice-column — closed (v3.1.15 orphan-deal workaround).
- AP- prefix Kubota(660) models gap — closed; no code change needed.
- SL backfill helper for legacy Won quotes — dropped; legacy quotes don't matter.
- `#14` (My Sales major update) and `#9` (quote status transitions / CRM) — dropped.

---

## 🔮 PARKED / FUTURE (only if John raises)
- **Frozen TAG (and maybe LOCATION) columns** in the Full List used-inventory table
  while the rest scrolls horizontally — big scanability win, more involved, interacts
  with the column-visibility toggles. v3.13.9 already fixed the AGE column clipping
  (right padding); the sticky-column idea is the bigger un-started piece.
- **Communications panel layout** — at some widths the right-side dashboard cards
  get pushed under/behind the scrollbar. Best tackled with a screenshot from John at
  the width where it misbehaves; likely a max-width container or responsive grid.
- Boot-time profiling beyond commissions (DIS contacts ~38k records, inventory, SKU
  rebuild, Stihl pricing) — only if John wants the *whole* boot faster.
- Drive-shared commissions cache (vs per-browser IndexedDB) — only if reps start
  hopping between machines a lot.
- Label↔route-slug naming cleanup — cosmetic; catch-all already makes it harmless.

---

## 🧪 SMOKE TEST (`./smoke.sh`) — run before every commit
Checks: (1) JS syntax of all inline `<script>` blocks via `node --check`;
(2) duplicate-ID count equals the baseline **6** (`set-apikey`, `list-col-vis-style`,
`'+id+'`, `cv-main-img`, `cv-thumb-'+i+'`, `pkg-list-${b.name}` — these are expected
template-literal/repeated-widget IDs; a 7th means real collision → investigate);
(3) the three version touchpoints all agree. Exits non-zero on any failure.
