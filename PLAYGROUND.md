# PLAYGROUND.md — Kubota-style redesign handoff (SHIPPED)

> ## ✅ SHIPPED — the redesign is LIVE (v4.0.0 → v4.0.1), 2026-06-15
> The Kubota redesign was promoted into **`index.html`** (the live app); the
> read-only guard + PLAYGROUND badge were removed. **Work on `index.html`
> directly now** — it is the source of truth again. Everything below about
> "work only in the playground" is **HISTORICAL** (kept as the build log).
> The sandbox `playground-9k3xq7m2.html` is now BEHIND live (still v3.15.3 +
> read-only guard) and is **safe to delete**, or re-sync from `index.html`
> before any *new* redesign experiment. Latest live fix: **v4.0.1** — "Traded By"
> entries no longer silently disappear when a staff name changes.
> **For current workflow, rules, and open follow-ups, see [`CLAUDE.md`](CLAUDE.md)**
> (the always-loaded project memory) — start there.

> **Cross-PC reference (historical build log below).** Claude Code memory/auth/
> history do NOT sync between machines — only the git repo does. Last updated
> **2026-06-15**.

---

## TL;DR
- **`playground-9k3xq7m2.html`** is an isolated sandbox copy of the live app (`index.html`).
  We are rebuilding its UI to mirror **Kubota's dealer portal**. The live app is
  **never touched** during this work.
- **Live playground URL:** https://hyde-park-equipment.github.io/playground-9k3xq7m2.html
  (same origin as the real app, so login / DIS / Google Drive all work).
- **Live app (DO NOT EDIT):** `index.html` → https://hyde-park-equipment.github.io/

## 🚦 Golden rules
1. **Edit `playground-9k3xq7m2.html` ONLY.** Never edit `index.html` during the redesign.
2. **`playground-9k3xq7m2.html` is READ-ONLY against Drive.** The first `<script>` in
   `<head>` wraps `fetch()` and blocks every mutating Drive call
   (POST/PUT/PATCH/DELETE + `/upload/`), returning a synthetic 200 so save flows
   don't crash. It can READ all production JSON but writes nothing. **Do not
   remove or weaken this guard** while it's a playground.
3. **Smoke before every commit:** `./smoke.sh playground-9k3xq7m2.html` must be all-green
   (JS syntax, dup-IDs = 6, the 3 version touchpoints agree). `node` + `python3`
   are installed on both PCs.
4. **Pushing/deploying is automatic.** The home PC's Stop hook commits+pushes;
   GitHub Pages redeploys in ~30–60s. (Work PC: `git pull` at start, `git push`
   when done, or add the same hooks.) After a push, **hard-refresh** (Ctrl+Shift+R)
   — the 2.7 MB file caches aggressively.
5. Functionality must stay intact — this is a visual/structure rebuild, not a
   feature change. Changes so far are CSS + chrome markup + additive JS only.

## 🎨 Kubota brand spec (from Kubota Digital Brand Guidelines PDF)
- **Kubota Orange `#EB421B`** — primary (`--orange`; dark `#C9381A`, light `#FDEBE6`)
- **Black `#000`**, grays **`#7C7C7C`** / **`#DCDCDC`** (`--border`), white
- **Kubota Blue/teal `#00AAAD`** — secondary accent (`--teal`; `.btn-teal`)
- **Font:** Helvetica Neue (UI) — set everywhere; **DM Mono** kept for numbers
- Headlines: bold, often uppercase (we uppercase `.page-title`)

## 🗺 Where the redesign lives (stable identifiers — line numbers drift)
- **Design tokens:** the global `:root` (~line 89). Key adds: `--orange #eb421b`,
  `--teal #00aaad`, `--rail #eb421b`, `--wsrail-w 74px`, `--panel-w 190px`,
  `--border #dcdcdc`, `--bg #f4f4f4`. NOTE: a **second `:root` in the Shortline
  CSS** (~line 1188) re-declares `--orange` etc. — keep it in sync or it overrides
  the global token document-wide.
- **Top bar:** now white (`.topbar`). The old centered section tabs (`.app-switcher`)
  were removed. `.nav-toggle` button → `HPE.ui.toggleNav()` collapses the page
  panel (`body.nav-collapsed`, persisted in `localStorage['hpe_nav_collapsed']`,
  restored by an inline script right after `<aside id="sidenav">`).
- **Two-tier sidebar:**
  - `#wsrail` (slim orange workspace rail) ← `HPE.ui.renderWorkspaceRail()`.
    Shows icon + label per section (Home/Used/Shortline/Kubota); active = white
    pill; each item has a **hover flyout** of that section's pages (visible when
    collapsed). Section icons: `ICONS` map inside that function.
  - `#sidenav` (white page panel) ← `HPE.ui.renderSidebar()` — the current
    section's pages + Quick Quote + bottom "My platform" nav.
  - Both feed off the existing `sections` config + `HPE.router.go(section[,page])`.
    `HPE.ui.updateSidebarActive()` handles active state on page changes.
- **Insights stat rail** (reusable): classes `.insights-rail` + `.insight-tile`
  / `.insight-ico` / `.insight-num` / `.insight-lbl` (sticky, hidden < 980px).
  - **My Quotes:** `HPE.quotes._renderInsights(filtered)`, called from
    `HPE.quotes._render()`; tiles reflect current filters.
  - **Used Full List:** built inline in `renderList()` (Used module = `window.U`)
    into `.list-body-layout` beside `#table-container`.
- **Tables:** light headers (`thead` light bg, gray uppercase). **Pills/chips:**
  `.hqc-status`, `.hqc-source`, `.badge` fully rounded; `.hqc-chip.active` orange;
  `.search-input` + `#section-shortline .filter-select` are pills.
- **Login screen:** light Kubota card (`#auth-screen`, `.auth-card`).
- **Global:** custom scrollbars + orange `::selection` (right after `html,body`).

## ✅ Done
- Tokens, Helvetica Neue, teal accent; v3.15.3 (dup-folder fix ported from live)
- White top bar; top tabs removed; **two-tier orange workspace rail (labeled) +
  white page panel**; collapse toggle + hover-flyout
- Light tables; rounded status pills; orange filter chips; uppercase page titles;
  teal secondary CTA; pill filter inputs; pilled Used loc-toggles
- **Insights rails (filter-aware):** My Quotes (`HPE.quotes._renderInsights`),
  Used Full List (`renderList` → `.list-body-layout`), Shortline inventory
  (inside `#inventory-list` so it hides in Stihl-Parts mode)
- **Quote builders — sticky Kubota grand-total bar** pinned to bottom of each
  modal: Shortline (`#quote-overlay-sl .totals-grand-card`) + Used
  (`#quote-overlay .used-grand-bar`, body now scrolls internally). Pricing IDs
  (`t-total`, `q-m-tat`, etc.) untouched.
- Custom scrollbars; orange `::selection`; Kubota light login; Home hero
  orange top-accent; **color sweep** (all old-orange hardcodes → Kubota orange)

## ⏭ TODO (optional — core redesign is feature-complete)
- **Full-screen two-column quote builders** — IF John decides the sticky bottom
  total bar isn't enough and wants Kubota's true right-side Summary panel. Would
  mean widening the 780px modals to near-full-screen and rebuilding as two
  columns (line items left, summary right). Bigger change — mock first, John
  tests live each step.
- Deeper **Home cockpit** refinement (kept light so far per the color-discipline
  note: Home semantic readout tiles ≠ Used categorical `.dash-card` — don't merge).
- Remaining hardcoded **grays → tokens** (cosmetic consistency).
- **Ship to live** when John approves (see "Shipping to live" above).

## 🚀 Shipping to live (later, only when John approves)
1. Remove the read-only guard `<script>` (top of `<head>`).
2. Port the finished design into `index.html` (or promote playground → index).
3. Bump version across the **3 touchpoints** (`<title>` + build comment, topbar
   pill, `HPE.config.version`/`.build`) and add a rep-facing `CHANGELOG` entry.
4. `./smoke.sh` green, then commit. Pages deploys.

## Smoke / version
`./smoke.sh playground-9k3xq7m2.html`. Current version pill: **v3.15.3** — the
playground now carries the v3.15.3 dup-folder Used-sync fix (ported from live so a
future "promote playground → index" never regresses it). The 🚧 PLAYGROUND topbar
badge marks the build.

> **Incident note (2026-06-13):** the FIRST playground copy (before the read-only
> guard existed) booted against live Drive and its `findOrCreateFolder` spawned an
> empty duplicate "All Inventory" folder; live Used sync then sometimes read the
> empty one. Fixed in v3.15.3 (live + now playground): never take `files[0]` blindly
> — prefer the folder that has contents, tiebreak oldest. The read-only guard now
> prevents the playground from writing/creating anything.
