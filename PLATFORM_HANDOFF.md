# HPE Platform — Build Handoff (new unified app + backend)

> **For a FRESH conversation.** This repo's `CLAUDE.md` + memory index auto-load; read those, then this.
> Deep detail lives in memory: `project_backend_migration` (the master record — every decision below is
> there), `project_admin_invoice_automation`, `reference_dis_importunits_format`,
> `reference_invoice_parser_profiles`, `project_email_notifications`, `project_dis_roadmap`.
> Written 2026-06-19. **Direction is decided — don't re-litigate; execute.**

---

## The goal
Build a **new, unified platform** that amalgamates HPE's modules — **Sales / Service / Parts / Admin** —
into ONE app on a shared backend, replacing the pile of independent single-file/Apps-Script apps. John's
sales platform and coworkers' service tools get **reworked** into it (their current code = reference
specs, not code to preserve).

## Hard constraints (non-negotiable)
1. **The existing app stays 100% live and untouched** the whole time. It's the current single-file
   `index.html` on GitHub Pages (`hyde-park-equipment.github.io`) — DO NOT modify it for this work.
2. **Build in parallel:** the new platform is a **separate repo at its own URL**. Cut over module-by-
   module later; **never a big-bang flag day**. The old app is the fallback until each piece is replaced.

## Locked decisions
- **Frontend stack:** **Vite + React + TypeScript**, **Tailwind + shadcn/ui** for one consistent design
  system. (John deferred the choice to Claude; this is the pick — well-supported, maintainable, others
  may touch it.)
- **Backend:** **Supabase** (managed Postgres + Google auth + auto REST/realtime API + row-level
  security). **Canadian region** (data residency).
- **Hosting:** **Cloudflare Pages** (free; keeps a "push → auto-deploy" flow even with a build step;
  sits near the existing CF DIS worker). Vercel is the equal alternative.
- **Build order (John's sequencing):**
  - **Phase 0 — SKELETON FIRST:** the unified UI shell (Sales/Service/Parts/Admin, consistent nav +
    layout + components, **placeholder pages, NO data, NO workers**) + the login-flow UI as placeholders.
    Get it **deployed live** so John can click it. ← START HERE.
  - **Phase 1 — unify/polish the UI** across all four modules (still no real data).
  - **Phase 2 — make it work:** wire functionality per data-domain against Supabase, cutting over from
    the old app one piece at a time.

## Auth model (decided)
- **Google OAuth is the single front door for everyone** (`@hydeparkequipment.ca`).
- **Three shared accounts** trigger a SECOND screen (**pick your name + enter PIN**) to set the acting
  technician: **`service@`, `service-scotland@`, `techs@hydeparkequipment.ca`**. Everyone else (their own
  Google account) logs **straight in, no PIN screen**.
- Per-tech identity is **app-level**: a `technicians` table (name + **hashed** PIN + active); a
  `technician_id` set after the PIN step attributes their work. Because the DB sees the shared account as
  one user, **per-tech isolation is app-enforced**, not RLS (acceptable — they're already inside the
  Google gate; rate-limit PINs; can later harden to a PIN→scoped-token). Staff with own accounts get
  normal RLS.
- **REQUIRED: a User Admin section (RBAC)** — John controls who sees/has access to what (roles +
  permissions per person and per module). Build the data model for this early even if the UI comes later.

## Team context (this is now a TEAM effort, not solo)
- **Adam Mason** built the Service side: `github.com/AdamMason00/hpe-platform` — **KPI Incentive Manager
  + Warranty Management**. Stack: **vanilla JS static site (GitHub Pages) + Google Apps Script + Google
  Sheets** (the `KPI Manager 2026` Apps Script web app is its backend). Warranty techs use the PIN model
  above.
- These are **reference specs** for rebuilding Service in the unified app; Adam's Apps Script becomes a
  **worker** (or gets reimplemented vs Supabase). His Sheets data migrates to Postgres.
- **OPEN / needs the team:** (a) **one shared monorepo vs separate repos** — lean monorepo for "one
  unified shell," but it's a team call; (b) **Adam's buy-in** on the stack + ownership split; (c) loop
  Adam in early so you don't diverge further. **The Phase-0 skeleton doubles as the alignment artifact**
  to show Adam.

## Architecture shape
Shared **Supabase** DB+API in the middle. **Front-ends** (the unified React platform; future modules)
read/write through its API. **Serverless workers** (Apps Script: KPI logic, email reminders, the invoice
Gmail puller) also hit the same DB for scheduled/Google jobs. **Google Workspace OAuth** = one shared
sign-in. The **current single-file app stays live and mirrors data in** until each domain cuts over.

## What exists today (the thing being replaced, for reference)
- Single-file `index.html` (~37k lines), GitHub Pages, all inline. Current version ~v4.27.1.
- "Backend" = Google Drive JSON (`app-state.json`, `sku-catalog.json`, etc.) via OAuth + `gfetch`;
  last-write-wins (the *Traded By* data-loss incident is the poster child for why we're doing this).
- One CF Worker proxies DIS (`dis-proxy.johnwilliams.workers.dev`).
- **Data domains** to migrate later: quotes, trades, inventory (DIS + daily xlsx), price book / SKU
  catalog, customers (DIS), commissions, brands, salespeople, the invoice pipeline; + KPI, warranty.

## Invoice Automation (a major in-flight feature that intersects this)
- Admin → Invoice Automation **cockpit UI shipped** in the live app (v4.27.0): kanban pipeline + per-brand
  parser stub. Engine (Gmail pull on `ap@`, AI parse, Drive filing, queues) needs the backend — though the
  **parse + editable preview + CSV export can run browser-side** (like the price-file parser).
- **Target output:** DIS/Keystone `ImportUnits.csv`, 45-col positional. **Prices = implied-cents
  (775.38→77538), date MM/DD/YY, Year = current, Location M/S from ship-to.** Builder module exists
  (`hpe-dis-importunits.js` in John's Downloads). See `reference_dis_importunits_format`.
- **Per-vendor parser profiles** already trained: **Toro** ✓ and **Pro-Power/Walker** ✓ (one row per
  serial; accessory lines fold cost into a unit + go to External Specs; ES1 = exact long description;
  brand resolved via price book for multi-brand distributors). See `reference_invoice_parser_profiles`.
- **Design principle (John):** target ~**90–95% time saved, NOT zero-touch** — the editable preview keeps
  a human in the loop to catch the 5–10%.

## Open questions for the new conversation
- Monorepo vs separate repos (lean monorepo). Loop Adam in?
- Subdomain for the new app — e.g. `app.hydeparkequipment.ca`?
- Design direction — keep the current orange/clean HPE look, or rethink it?
- Per-module left-nav structure — mirror today's, or reorganize?
- First data domain to wire in Phase 2 — **Trades** (where data loss bit) or **Quotes**? (parked till UI works)

## Concrete first steps (Phase 0)
1. (Team) Align with Adam on monorepo + stack; or build the skeleton first and show him.
2. Scaffold a **new repo**: Vite + React + TS + Tailwind + shadcn/ui.
3. Build the **unified shell** — top nav Sales/Service/Parts/Admin + per-module left nav + shared
   header/cards/tables, **placeholder pages**. Plus the **login UI** (Google sign-in → name+PIN screen for
   the 3 shared accounts) as non-wired placeholders.
4. Run locally + show John via preview, then guide the one-time **Cloudflare Pages connect** for the live URL.

## What only John can do (hands-on, guide him)
- Create the **Supabase** project (Canadian region).
- Connect the new repo to **Cloudflare Pages** (one-time, ~5 min) → live URL.
- Create the **shared tech Google accounts** (`service@`, `service-scotland@`, `techs@`) in Workspace.
- (Team) Get Adam aligned.

---
*Direction decided 2026-06-16→19. This kicks off Phase 0 (the live UI skeleton). The existing single-file
app is not to be touched for this effort.*
