# DIS Quantum API Integration — Status & Handoff

> **Purpose of this doc:** let any Claude Code session (esp. John's work PC) pick
> up the DIS live-lookup integration without re-discovering anything. Last
> updated **2026-06-10** by the home-PC session. Supersedes the original
> `Downloads/DIS_API_HANDOFF.md` (which had two wrong assumptions — noted below).
>
> **2026-06-10 BREAKTHROUGH:** DIS sent the official GET-entity list — **phone &
> email DO exist** in the API (`contact` + `communicationDetail` entities, singular
> paths). The §6 "phone/email blocked" question is ANSWERED; full prefill parity is
> achievable. See §2a. The Worker whitelist must be extended before wiring (§4).

---

## TL;DR — where we are

**Goal:** replace the static ~38k-row "Contact List" XLSX feeding the customer
typeahead with a **live** lookup against the DIS *Quantum* API, via a Cloudflare
Worker proxy (so the API key never touches the browser).

| Piece | Status |
|---|---|
| DIS API reverse-engineered (auth, format, entities, query lang) | ✅ done |
| Cloudflare Worker proxy built, deployed, secured, verified | ✅ **done & live** |
| Phone/email source found & verified (`contact`/`communicationDetail`, §2a) | ✅ **done 2026-06-10** |
| Worker whitelist extended with `contact` + `communicationDetail` + redeploy | ⬜ **needed before wiring** |
| `index.html` typeahead wired to the Worker | ⬜ **NOT started — this is the next task** |
| In-app positive-path auth test | ⬜ John to do once wired |

**Next task = extend the Worker whitelist (1-line change, §4 step 0), then wire
the app (§4).** Everything it needs is below.

---

## 1. The Worker (server side) — DONE, do not rebuild

- **Live URL:** `https://dis-proxy.johnwilliams.workers.dev`
- **Cloudflare account:** `421b266ca743101979e4d08af668b8cd` (johnwilliams@hydeparkequipment.ca), subdomain `johnwilliams.workers.dev`
- **Deployed version:** `b3d4d5a1` (2026-06-09)
- **Secret:** `DIS_API_KEY` is set in the Worker (Settings → Variables & Secrets). Never in code/repo.
- **Canonical source:** on the home PC at `C:\Users\johnr\dis-proxy-worker\` AND embedded in §7 below. **Not yet its own git repo** (a good follow-up; for now this doc is the backup).
- **Endpoint shape:** `GET /dis/{entity}?query=…&page=&size=&sort=`
- **Verified:** unauthenticated → 401, bogus token → 401, `OPTIONS` → 204, forwards to DIS with the key. The **only** untested path is a real logged-in token returning data — John tests that in-app after wiring.

**Existing unrelated Worker:** `hpe-site-proxy` (a generic `?url=` proxy to
`www.hydeparkequipment.ca`) — **leave it alone**, it's a different feature.

### How the Worker authenticates callers (IMPORTANT — corrects the old handoff)
The old handoff assumed the app sends a Google **ID token (JWT)**. It does **not** —
the app uses `google.accounts.oauth2.initTokenClient` with **drive scope only**, so
it holds an **access token**. The Worker therefore validates the access token with
two checks:
1. **tokeninfo** → `aud`/`azp` === the HPE OAuth client ID (proves the token was
   minted for this app; works regardless of scope).
2. **userinfo** (`https://www.googleapis.com/oauth2/v3/userinfo`) → `email` ends
   with `@hydeparkequipment.ca` and `email_verified` (the same endpoint the app's
   own login uses; reliably returns email even for drive-scoped tokens, where
   `tokeninfo.email` may be absent).

So the **client must send the app's existing access token**:
`Authorization: Bearer <access_token>`.

### Redeploying the Worker (only if you change it)
Dashboard: Workers & Pages → `dis-proxy` → Edit code → paste `src/worker.js` →
Deploy. (No Node needed.) Or with Node: `cd dis-proxy-worker && npx wrangler deploy`
(needs `wrangler login` first; secret already set).

---

## 2. DIS API reference (confirmed empirically, 2026-06-09)

- **Base:** `https://hy2303.disprism.com/api`
- **Auth header:** `X-API-Key: <key>` (raw key — **NOT** `Authorization: Bearer`; Bearer returns 403)
- **Response:** HAL / Spring-Data-REST — records under `_embedded.{entity}[]`, paging under `.page` (`size`, `totalElements`, `totalPages`, `number`)
- **⚠️ Path naming gotcha:** DIS's query doc says endpoints are "the pluralized
  form" of the model, and `customers`/`addresses` do work pluralized — but the
  official entity list (sent by DIS 2026-06-10, full list in §2b) uses the model
  names **as-is**, and `contact`/`communicationDetail` only respond on the
  **singular** path (`/contacts` → 404, `/contact` → 200). When probing a new
  entity, try the list's exact name first, then the plural.
- **Entities confirmed live:** `equipment`, `customers` (38,568 rows), `addresses`
  (68,031 rows), `contact` (38,154 rows), `communicationDetail` (~49k rows).
- **`customers` fields:** `webId, customerNumber, customerName (single combined name — NO first/last), active, businessEntity, mainAddressId, contactId, branchId, …` (`contact`/`contactId` were empty on the records sampled).
- **`addresses` fields:** `webId, name, name2, city, state, street, postalCode, customerId, addressType, useForShipTo/BillTo/Main, …` (linked to a customer via `customerId`; no phone/email on the address itself — they're in `communicationDetail`, §2a).

### Query language
`?query={field}{op}{value}`, comma-separated = AND, prefix `|` (URL-encode `%7C`) = OR. Paging: `page`, `size`, `sort`.
Strings (case-insensitive): `:` eq · `!` ne · `:foo*` startsWith · `:*foo` endsWith · `*foo*` contains. Nested via dot notation (don't prefix the top entity's own name).

### Confirmed working customer search (use this for the typeahead)
```
GET /dis/customers?query=customerName:*{input}*&size=10&sort=customerName
```
(e.g. `customerName:*construction*` → 193 matches, returns customerNumber + customerName + active). **NOTE:** the old handoff's `lastName:{input}*` is WRONG — there is no `lastName` field; use `customerName`.

---

## 2a. Phone & email — FOUND (verified live 2026-06-10)

The earlier "no phone/email anywhere" conclusion was wrong — the probe only tried
pluralized paths. Two singular-path entities hold everything the Contact List
XLSX had:

- **`/contact`** (38,154 rows ≈ the XLSX row count): `webId, firstName, lastName,
  middleName, nickname, organizationName, title, notes, addressId, customerId,
  usedForWorkOrderRecipient, deleted, …` + `_links` to `customer`, `address`,
  `communicationDetails`.
- **`/communicationDetail`** (~49k rows): `webId, communicationMethod
  (enum: PHONE | EMAIL | CELL | FAX — case-sensitive), information (the actual
  number/email string), extension, main (bool), addressId, contactId, deleted`.
  A detail links to an address OR a contact (either id can be null).

### Verified lookup chain for the typeahead (per selected customer)
1. Typeahead search (unchanged): `/customers?query=customerName:*{q}*&size=10&sort=customerName`
   → take `webId`, `customerNumber`, `customerName`, **`mainAddressId`**.
2. Phone/email on pick: **`/communicationDetail?query=addressId:{mainAddressId}&size=10`**
   → filter `deleted`, prefer `main:true`; `communicationMethod` tells you which
   field each `information` value fills. Verified on 5 random customers — every
   one returned its PHONE (and EMAIL where present).
3. City/province on pick (optional): `/addresses?query=webId:{mainAddressId}&size=1`
   → `city`, `state`.

So a pick costs 2 small extra GETs and achieves **full prefill parity** (name,
customer#, phone, email, city, province). Note the reverse direction does NOT
work: `communicationDetail?query=address.customerId:{custId}` returns 0 because
customer-main addresses carry `customerId: null` — always go customer →
`mainAddressId` → `addressId`.

### Worker prerequisite
`ALLOWED_ENTITIES` in the Worker (§7) must gain `"contact"` and
`"communicationDetail"` and be **redeployed** before the app can use them.
(Read-only GETs, same gate — no other Worker change needed.)

---

## 2b. Official GET-entity list (from DIS, 2026-06-10)

Full catalog DIS sent (use exact names; singular unless confirmed otherwise):
`accountReceivablePayment, address, agreementGroup, agreement, branch, checklist,
checklistAcceptedResult, checklistCategory, checklistDisclaimer, checklistItem,
checklistItemDisclaimer, communicationDetail, consolidatedInvoice, company,
configurationDescription, configurationKey, configurationOption, contact,
customer, customerPoRules, customerPurchaseOrder, department, equipment,
equipmentGroup, updateEquipmentHourMeter, equipmentHistory, equipmentMeter,
equipmentWarranty, equipmentFinancials, file, folder, generalLedgerAccount,
generalLedgerAccountGroup, generalLedgerAccountRelationship,
generalLedgerSummary, inventory, invoice, invoiceLine, invoiceSegment, laborCode,
laborTimeType, ledgerEntry, ledgerEntryAging, ledgerEntryDocument,
ledgerEntryMatch, manufacturer, metadata, notificationRecord, operation,
partsOrder, partsOrderLine, periodicMaintenance, periodicMaintenanceSchedule,
product, productBranch, requestedPartsOrderLine, scheduleEvent, serviceType,
signature, solvencyCode, standardJobCode, standardJobCodeManufacturer,
standardJobCodeManufacturerStructure,
standardJobCodeManufacturerStructureFieldName, standardJobCodeName, statement,
stockArea, stockAreaAssignment, submittedPartsOrderLine, task, taskBoard,
taskComment, team, technicianClock, timeCard, timeCardLine, truck, vendor,
webHook, webUser, workOrderFreeField, workOrderHeader, workOrderLine,
workInProcess, workOrderSegment, workOrderTechnician`
plus special routes: `public/v1/file/{list,urls,resolve}`,
`workOrderHeader/convert`, `workOrderSegment/{webId}/workOrderTechnicians`,
`configurationOption/{webId}`.

Interesting for future features: `invoice`/`invoiceLine`, `workOrderHeader`
(service status for customers), `inventory`, `partsOrder`, `equipmentHistory`.

DIS also sent the query-language doc (operators, wildcards, `,` = AND,
`|`-prefix = OR, dot-notation nesting) — it matches what §2 already documents.
Swagger UI exists at `https://hy2303.disprism.com/api/swagger-ui/index.html`
(browser; the raw spec URL behind it hasn't been found via common api-docs paths —
open it in a browser and check its network tab if the full schema is ever needed).

---

## 3. How the app's typeahead works today (what you're changing)

- **`dis` module** (`index.html` ~line 5045, inside `HPE.shared`): loads the static
  "Contact List" XLSX from Drive into in-memory `_contacts`, exposes **synchronous**
  `searchContacts(query, limit)` and `findByCustomerNumber(num)`. Contact record
  shape: `{ name, customerNumber, phone, phoneDisplay, email, city, province, isCompany }`.
- **Loader:** `loadDISContacts()` in the Hub IIFE (~line 9239), called at bootstrap (~6933).
- **Consumer A — quote-builder "New Customer" typeahead:** `onDISSearchInput(rawQ)`
  (~9357) → renders dropdown → `pickDISSearchResult(custNum)` (~9419) →
  `applyDISContactToModal(contact)` (~9329) prefills the form.
- **Consumer B — standalone DIS lookup modal:** `HPE.disLookup` (~9736) + render at
  ~9786, also calls `dis.searchContacts`.
- The token to send to the Worker: the app's access token is `state.token` (auth
  IIFE) / `accessToken` (shell); `drive.gfetch` (~5248) shows the refresh pattern.

---

## 4. NEXT TASK — wire the typeahead to the Worker

**Scope update (2026-06-10):** the original "lean v1, name + customer# only" scope
existed because phone/email looked unavailable. §2a removes that blocker — **full
prefill parity is now possible** (search still on `customerName`; on pick, 2 extra
GETs fill phone/email/city/province). Confirm with John whether to ship full-parity
v1 directly or still stage it lean-first.

**Plan:**
0. **Worker first:** add `"contact"` and `"communicationDetail"` to
   `ALLOWED_ENTITIES` in `dis-proxy-worker/src/worker.js`, redeploy (dashboard
   paste or `npx wrangler deploy`), update the §7 copy + deployed-version note.
1. Add a config constant, e.g. `disProxyUrl: 'https://dis-proxy.johnwilliams.workers.dev'` near `googleClientId` (~line 4658).
2. Add an **async** live-search helper (in the `dis` module or alongside the consumers) that calls:
   `GET {disProxyUrl}/dis/customers?query=customerName:*{q}*&size=10&sort=customerName`
   with header `Authorization: 'Bearer ' + state.token`. Map `_embedded.customers` →
   `{ name: r.customerName, customerNumber: r.customerNumber, isCompany: true, active: r.active }`.
   On non-200 return null so the UI can show a graceful message (don't hard-crash the quote builder — handoff rule).
3. Rework **`onDISSearchInput`** to be **debounced (~250ms) + async**, calling the live
   helper instead of `dis.searchContacts`. Render name + `#customerNumber` (show
   phone/email/city only if fetched — see step 4).
4. Rework **`pickDISSearchResult`** to use the live result set (keep the last results
   array keyed by customerNumber) → on pick, fetch phone/email (+city) via the §2a
   chain (`communicationDetail?query=addressId:{mainAddressId}` +
   `addresses?query=webId:{mainAddressId}`) → `applyDISContactToModal`; ensure any
   still-missing fields degrade gracefully (verify `applyDISContactToModal`
   ~9329 doesn't choke on undefined).
5. Decide whether to also switch **Consumer B** (`disLookup` modal) now or leave it on
   the static source for v1 — the handoff wants both eventually; smallest safe step is
   the quote-builder typeahead first.
6. **Auth-expiry handling:** if the Worker returns 401, try one silent token refresh
   (see `auth._silentRefresh` ~4901 / the gfetch refresh ~5254) then retry; else show
   "session expired, refresh".

**Ship checklist (from CLAUDE.md):**
- Work on branch **`dis-live-lookup`** (already created locally on the home PC; recreate on work PC: `git checkout -b dis-live-lookup`).
- **Version bump v3.13.50 → v3.14.0** (minor = feature) across the 3 touchpoints (`<title>`+build comment, topbar pill, `HPE.config.version`/`.build`) + add ONE `CHANGELOG` entry at the top (rep-facing note, e.g. "Customer search now pulls live from DIS").
- `./smoke.sh` must be green (JS syntax, dup-IDs = 6, version consistent).
- Show John the diff; **do not merge to `main` until he's tested** the live lookup in the deployed/preview app (needs login + the Worker).

---

## 5. Environment notes (work PC)

- The work PC already runs `smoke.sh`, so Node + python3 are presumably installed there.
- **No API key needed locally to wire the app** — the app just calls the Worker URL; the key lives only in the Worker secret.
- If you want to **probe DIS directly** from the work PC (optional), set the key as a user env var and read it without printing:
  `[Environment]::SetEnvironmentVariable('DIS_API_KEY','<key>','User')` then in curl use `-H "X-API-Key: $k"` where `$k=[Environment]::GetEnvironmentVariable('DIS_API_KEY','User')`.
- Repo sync is plain git (`git pull` at start, `git push` when done). The home PC has auto-sync hooks; the work PC can too (ask John).

---

## 6. Open questions for DIS / Lauren

1. ~~**Phone & email** — where do they live?~~ **ANSWERED 2026-06-10:** in
   `contact` + `communicationDetail` (singular paths) — see §2a. DIS's entity
   list + query-doc link confirmed it; verified live.
2. ~~Location of the full entity catalog~~ **Mostly answered:** DIS sent the GET-entity
   list (§2b) + the query-language doc. Still nice-to-have: the raw OpenAPI spec
   URL behind their swagger-ui (for per-entity field schemas).
3. **Write scope** of the issued key + is there a **sandbox/test environment**? (Until confirmed: **reads only, never write against production.**)
4. ~~Confirm canonical customer lookup entity/fields~~ **Confirmed** — `customer(s).customerName` is it (list has no other customer-name-bearing entity).

---

## 7. Worker source (canonical copy — `dis-proxy-worker/src/worker.js`)

> Deployed as version `b3d4d5a1`. No secrets here (the key is a Worker secret).
> If you edit, update both this block and the deployment.
> **⚠️ PENDING CHANGE (2026-06-10):** `ALLOWED_ENTITIES` below still lacks
> `"contact"` and `"communicationDetail"` — add them + redeploy before wiring the
> app (§4 step 0), then update this block and the deployed-version line.

```js
/**
 * DIS Quantum API proxy — Cloudflare Worker (dependency-free).
 *
 * Purpose: let the HPE Sales Platform (static GitHub Pages app) do live
 * customer/equipment lookups against the DIS Quantum API WITHOUT exposing the
 * API key to the browser and without CORS problems.
 *
 * Auth model (matches the app's existing pattern):
 *   The HPE app authenticates users with Google's OAuth token client (scope:
 *   drive only) and holds a Google *access token*. It already trusts that token
 *   for login by reading Google's USERINFO and checking the email domain. This
 *   Worker does the server-side equivalent, with two checks:
 *     1. tokeninfo  -> aud (or azp) === the HPE OAuth client ID (token minted
 *        for THIS app; tokeninfo always returns aud/azp regardless of scope).
 *     2. userinfo   -> email ends with @hydeparkequipment.ca and email_verified
 *        (the SAME endpoint the app's own login uses — proven to return email
 *        for these drive-scoped tokens, where tokeninfo's email field may not).
 *   The client sends: Authorization: Bearer <access_token>.
 *
 * Confirmed by Task-0 probe (2026-06-09):
 *   - DIS auth header is `X-API-Key` (raw key), NOT `Authorization: Bearer`.
 *   - Response is HAL JSON: records under `_embedded.{entity}[]`.
 *
 * The DIS key lives ONLY as the Worker secret `DIS_API_KEY`. Read-only: only
 * whitelisted GET entities are forwarded. No write methods, ever.
 *
 * Endpoint shape:
 *   GET https://<worker>.workers.dev/dis/{entity}?query=...&page=&size=&sort=
 */

// ─── Config ──────────────────────────────────────────────────────────────────
const DIS_BASE = "https://hy2303.disprism.com/api";
const ALLOWED_ENTITIES = new Set(["equipment", "customers", "addresses"]); // expand as confirmed
const ALLOWED_ORIGIN = "https://hyde-park-equipment.github.io";            // GitHub Pages origin (no CNAME)
const GOOGLE_CLIENT_ID =
  "659141396162-8iilhoicrtpnnpie0m88m8f69lulgg4l.apps.googleusercontent.com"; // HPE app's OAuth client
const ALLOWED_DOMAIN = "hydeparkequipment.ca";
const TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo?access_token=";
const USERINFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo";
// Only these query params are passed through to DIS.
const PASSTHROUGH_PARAMS = ["query", "page", "size", "sort"];

// ─── CORS ────────────────────────────────────────────────────────────────────
function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
    "Access-Control-Allow-Methods": "GET,OPTIONS",
    "Access-Control-Allow-Headers": "Authorization,Content-Type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}
function json(status, obj) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders(), "Content-Type": "application/json" },
  });
}

// ─── Access-token validation (cached in module scope) ─────────────────────────
const _tokCache = new Map();

async function validateAccessToken(authHeader) {
  if (!authHeader || !authHeader.startsWith("Bearer ")) return false;
  const token = authHeader.slice(7).trim();
  if (!token) return false;

  const now = Date.now();
  const cached = _tokCache.get(token);
  if (cached && now < cached.exp) return cached.ok;

  // Check 1 — tokeninfo: confirm the token was minted for THIS app (aud/azp).
  let ti;
  try {
    const res = await fetch(TOKENINFO_URL + encodeURIComponent(token));
    if (!res.ok) {
      _tokCache.set(token, { ok: false, exp: now + 60000 });
      return false;
    }
    ti = await res.json();
  } catch {
    return false;
  }
  const audOk = ti.aud === GOOGLE_CLIENT_ID || ti.azp === GOOGLE_CLIENT_ID;
  if (!audOk) {
    _tokCache.set(token, { ok: false, exp: now + 60000 });
    return false;
  }

  // Check 2 — userinfo: confirm the user's email domain.
  let ui;
  try {
    const res = await fetch(USERINFO_URL, {
      headers: { Authorization: "Bearer " + token },
    });
    if (!res.ok) {
      _tokCache.set(token, { ok: false, exp: now + 60000 });
      return false;
    }
    ui = await res.json();
  } catch {
    return false;
  }
  const emailOk =
    typeof ui.email === "string" &&
    ui.email.toLowerCase().endsWith("@" + ALLOWED_DOMAIN);
  const verified = ui.email_verified === true || ui.email_verified === "true";
  const ok = emailOk && verified;

  let ttl = 300000;
  if (ti.exp) {
    const ms = parseInt(ti.exp, 10) * 1000 - now;
    if (ms > 0) ttl = Math.min(ttl, ms);
  }
  _tokCache.set(token, { ok, exp: now + (ok ? ttl : 60000) });
  if (_tokCache.size > 2000) {
    const k = _tokCache.keys().next().value;
    if (k !== undefined) _tokCache.delete(k);
  }
  return ok;
}

// ─── Worker ──────────────────────────────────────────────────────────────────
export default {
  async fetch(req, env) {
    if (req.method === "OPTIONS")
      return new Response(null, { status: 204, headers: corsHeaders() });
    if (req.method !== "GET")
      return json(405, { error: "method_not_allowed" });

    const ok = await validateAccessToken(req.headers.get("Authorization"));
    if (!ok) return json(401, { error: "unauthorized" });

    const url = new URL(req.url);
    const entity = url.pathname.replace(/^\/dis\//, "").replace(/\/+$/, "");
    if (!ALLOWED_ENTITIES.has(entity))
      return json(403, { error: "forbidden_entity", entity });

    const out = new URLSearchParams();
    for (const p of PASSTHROUGH_PARAMS) {
      const v = url.searchParams.get(p);
      if (v != null) out.set(p, v);
    }
    const qs = out.toString();
    const target = `${DIS_BASE}/${entity}${qs ? "?" + qs : ""}`;

    let upstream;
    try {
      upstream = await fetch(target, {
        method: "GET",
        headers: { "X-API-Key": env.DIS_API_KEY, Accept: "application/json" },
      });
    } catch {
      return json(502, { error: "upstream_unreachable" });
    }

    const body = await upstream.text();
    return new Response(body, {
      status: upstream.status,
      headers: {
        ...corsHeaders(),
        "Content-Type":
          upstream.headers.get("Content-Type") || "application/json",
      },
    });
  },
};
```

---

## 8. Hard security rules (unchanged)
1. DIS key only as the Worker secret — never in client code, repo, URLs, or logs.
2. **Reads only.** No POST/PUT/PATCH/DELETE against production until DIS confirms write scope + provides a sandbox.
3. Worker is not an open relay — entity whitelist + Google-token gate on every request.
4. If the key is ever exposed anywhere shared, rotate it before go-live.
