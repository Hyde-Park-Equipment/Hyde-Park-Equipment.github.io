# CLAUDE.md — HPE Sales Platform

> Project memory for Claude Code. Read automatically every session. Keep it
> current — when something here goes stale, fix it in the same change that made
> it stale. This file replaces the old "re-upload + paste handoff" ritual.

> 🏗️ **NEW PLATFORM REBUILD — see [`PLATFORM_HANDOFF.md`](PLATFORM_HANDOFF.md) (2026-06-19).** Decided:
> rebuild HPE's modules (Sales/Service/Parts/Admin) into ONE unified app on a real backend — **Vite +
> React + TS + Tailwind/shadcn** frontend, **Supabase** (Postgres, Canadian region) backend, **Cloudflare
> Pages** hosting, in a **SEPARATE repo**. **This `index.html` app stays 100% live/untouched** during that
> work (parallel build, cut over module-by-module). Start = a live Phase-0 UI skeleton. Full plan +
> decisions (auth model, Adam Mason's coworker repo, invoice automation) in PLATFORM_HANDOFF.md and the
> memory files (`project_backend_migration` is the master record).

> ✅ **Kubota UI redesign SHIPPED to live as v4.0.0 (2026-06-15).** `index.html`
> now carries the full redesign: orange **two-tier side nav** (workspace icon-rail
> + white page panel, collapsible, hover-flyouts; personal "My …" links live in the
> rail's bottom group), light tables/cards, **insight stat rails** (My Quotes, Used
> Full List, Shortline inventory), **sticky quote-total bars**, and a **uniform
> orange + neutral palette** (purple/blue/teal removed; green/red kept only for
> won/lost quote status + alerts). Helvetica Neue UI font, DM Mono for numbers.
> The old read-only sandbox `playground-9k3xq7m2.html` is now BEHIND live (still
> v3.15.3, has the read-only guard) — **re-sync it from `index.html` before any
> future redesign experiments, or delete it.** See **[`PLAYGROUND.md`](PLAYGROUND.md)**.

> 🔧 **v4.0.1 (2026-06-15) — "Traded By" data-loss fix + OPEN follow-ups (likely
> the work-PC task).** Incident: a batch of John's "Traded By" entries on Used
> equipment went missing. Root cause: "Traded By" is stored as the salesperson's
> **display-name string** (`tradedBy[stock] = "John Williams"`, in `app-state.json`
> + localStorage) and matched **exactly** against the live staff list (`STAFF`,
> rebuilt from `salespeople.json`). When the stored name stopped matching a current
> staff name, the row's `<select>` fell back to blank — which both hid the value and
> could **delete** it on a blank save (`saveTradedBy` `else delete`). Fix shipped:
> `tradedByOptionsHtml(stock, blankLabel)` (~line 10419, used by the Full List cell
> and the detail view) renders an unmatched stored name as its **own selected
> option** so it's never silent-blanked, with case/space-tolerant matching. John is
> recovering any *truly* deleted entries manually (localStorage `tradedBy` / Drive
> version history / Drive Trash, 30-day). Note: entries that were only *hidden*
> should reappear on their own under v4.0.1.
> **OPEN (optional, discuss scope first):** (1) re-key Traded By by **email** instead
> of name, with a one-time name→email migration — bulletproof against renames but
> changes the `app-state.json` shape, so stage carefully.

> 🔧 **v4.0.2 (2026-06-15) — Traded By: "I'm not in the dropdown" + My-Trades empty.**
> Same root cause for BOTH: `STAFF` is replaced wholesale by `salespeople.json`
> (`loadSharedSalespeople`, ~line 11266), and if that shared file omits a user / marks
> them `active:false`, the `STAFF.find(s=>s.email===email).name` lookup returns `''`
> — so the user vanished from the Traded By `<select>` AND every "my trades"
> count/filter collapsed to 0 (John hit this himself on launch day). Fix: two helpers
> in the `window.U` scope (~line 10470) — `currentUserStaffName()` (email→STAFF,
> **falls back to the OAuth display name** so the current user is always representable)
> and `sameStaffName(a,b)` (case/space-tolerant compare). `tradedByOptionsHtml` now
> always injects the logged-in user as a self-option; all 5 my-trades derivations
> (`myTradesMissingInfoCount`, `renderMyTrades`, `getMyTradesMissing`,
> `getMyOpenQuotes`, `renderMyTradesMissing`) route through these. **This closes
> open follow-up (2)** above (my-trades is now name-tolerant). Follow-up (1)
> (email re-keying) still parked. **Underlying data question still worth answering:**
> why is John missing from `salespeople.json` in the first place? — worth checking the
> Shortline Salespeople page so the live list actually lists him.

## What this is
Single-file internal sales platform for **Hyde Park Equipment (HPE)**.
- **One file:** `index.html` (~36,700 lines / ~2.5 MB). All HTML, CSS, JS inline.
- **Deployed to:** GitHub Pages under the `Hyde-Park-Equipment` org.
- **Backend:** Google Drive via OAuth, restricted to `@hydeparkequipment.ca`.
- **Developer & primary user:** John Williams.
- **Current version:** v4.27.1 (bump this line whenever you ship — see below).

This is a real production tool reps use daily. Default to caution: small,
reviewable diffs; never break `main`.

## 🔭 DIS live customer lookup — SHIPPED ✅ (v3.14.0–v3.14.2, 2026-06-10)
All three customer-lookup surfaces — the Hub inline typeahead, the Used/SL
"DIS contact lookup" modal (🔍 DIS on quote builders), and the Shortline
My Customers add/edit modal (🔍 DIS button, added v3.14.2) — now search the
**live DIS Quantum API** through the Cloudflare Worker proxy
(`dis-proxy.johnwilliams.workers.dev`), with on-pick phone/email/address
prefill and automatic fallback to the static Contact-List XLSX if the live
path fails. **Tested in production by John 2026-06-10 — working.**
Full reference in **[`DIS_INTEGRATION.md`](DIS_INTEGRATION.md)** — read it before
touching anything DIS/customer-lookup related.

## 🔭 DIS live INVENTORY feed — VALIDATED, SOAK-TESTING (v3.15.0–v3.15.2, 2026-06-10)
Goal: kill the daily All Inventory xlsx upload (and later the Parts one).
**Status:** the live equipment pull is proven 1:1 against John's desktop
ground truth (849/849; cost to the penny; flooring derived exactly from
`ledgerEntry NOTE_BALANCE`; orphan rule `dateUpdated >= 2020` validated
0FP/0FN), and the admin-only **Shortline → DIS Feed (beta)** page (v3.15.0)
diffs live-vs-file in-app — **John is soak-testing it across business days.**
Parts feed also validated (Stihl bulk / Kubota per-part lookup with
latest-product-wins dedup — §2d). Worker whitelist v2 deployed (`cba254b7`).
**Two confirmed API gaps** (reserved units + desktop Location codes — they're
host-side data the Prism sync doesn't replicate): questions drafted for DIS
(§6 q5–q9); until answered they ride the xlsx as an overlay. **Critical API
gotchas:** every paginated query needs `sort=webId` (unstable paging
double-counts/drops rows — fixed in-app v3.15.2) and never mix `|`-OR with
AND terms in one query. Everything is in **[`DIS_INTEGRATION.md`](DIS_INTEGRATION.md)**
§2c (units), §2d (parts) — read those before touching DIS/inventory code.

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
- **Backend / "proper server" migration (long-term architecture)** — parked 2026-06-15,
  direction discussed. **Recommendation: directionally yes, but incremental (strangler-fig),
  never a from-scratch rewrite, and keep the single-file UI.** The real ceiling isn't the
  2.5MB file — it's that the backend is JSON-on-Drive with no transactions / last-write-wins
  concurrency (the Traded By data-loss incident, the duplicate `app-state.json` consolidation
  logic, and stray `(1)` files are all symptoms). That risk scales badly with more
  people/modules writing. The "no server" wall also forces a bolt-on for every event/scheduled/
  integration feature (DIS → Cloudflare Worker; email → Apps Script). **Amalgamation with
  coworkers' service modules is the strongest argument FOR a backend** — a shared DB+API is the
  prerequisite that lets independent front-ends compose into one platform (Google Workspace
  OAuth already gives shared auth). Recommended managed backend: **Supabase** (Postgres + Google
  auth + instant REST/realtime + row-level security) or **Cloudflare D1** (already on CF Workers)
  — both avoid real ops burden. Path: (1) align with coworkers on a SHARED data model/backend
  BEFORE any code; (2) stand up managed DB+API, UI untouched; (3) migrate one data domain at a
  time (quotes or trades first) behind the same screens, verify on real data, Drive can mirror
  during transition; (4) split the single-file UI later, independently. Open scoping Qs for John:
  what are the coworker modules built on (anyone already on a real DB?), what does "amalgamation"
  mean (one shell vs shared data/auth/nav), and who maintains it long-term. See
  [[project_email_notifications]] / [[project_dis_roadmap]].
- **Email notifications (no-reply, staff-facing)** — parked 2026-06-15, feasibility
  already scoped. John wants event emails ("New trade evaluation posted") + aging
  reminders ("quote follow-up due", "trade needs info 15 days — upload pic + list
  price"). **Hard constraint:** the GitHub Pages app is browser-only with no server,
  so it can't send mail or run when closed — needs a small always-on helper. Two
  notification kinds: instant (app pings helper on the event) vs scheduled (a daily
  timer reads `app-state.json`, finds overdue items, emails the owning rep, and logs
  sends so nobody's pestered daily — the dedup log is the fiddly part). **Recommended
  backend: Google Apps Script** (all-Google shop → native Drive read, built-in daily
  triggers, sends from their own domain so `noreply@hydeparkequipment.ca` gets DKIM
  for free, no key in the client). Alt: Cloudflare Worker + Resend (matches DIS proxy
  but needs DNS verification + a service account for Drive). Keep it staff-only (no
  customer emails → no CASL). Effectively free at their volume. ~0.5 day instant,
  ~1 day scheduled.

---

## 🧪 SMOKE TEST (`./smoke.sh`) — run before every commit
Checks: (1) JS syntax of all inline `<script>` blocks via `node --check`;
(2) duplicate-ID count equals the baseline **6** (`set-apikey`, `list-col-vis-style`,
`'+id+'`, `cv-main-img`, `cv-thumb-'+i+'`, `pkg-list-${b.name}` — these are expected
template-literal/repeated-widget IDs; a 7th means real collision → investigate);
(3) the three version touchpoints all agree. Exits non-zero on any failure.
